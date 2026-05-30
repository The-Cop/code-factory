// Subagent runner extension for pi.dev (in-process).
//
// Registers a single `subagent` tool that delegates a task to one of the
// agent definitions under ~/.pi/agent/agents/ by spinning up an in-process
// AgentSession via pi's exported SDK. No child processes, no extra startup
// cost, shares auth/model registry with the parent.
//
// This uses pi's internal SDK surface (`createAgentSession`,
// `SessionManager.inMemory`, `AuthStorage.create`, `ModelRegistry.create`).
// These are exported from `@earendil-works/pi-coding-agent` but they are
// not a stability contract -- pin a pi version when shipping, and re-check
// after pi upgrades.
//
// Env knobs:
//   PI_SUBAGENT_MAX_CONCURRENCY  Max concurrent in-process sessions (default 4)
//   PI_SUBAGENT_MAX_DEPTH        Max nesting depth (default 2)
//   PI_AGENTS_DIR                Override the agent definitions directory

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  AuthStorage,
  createAgentSession,
  getAgentDir,
  ModelRegistry,
  parseFrontmatter,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import { AsyncLocalStorage } from "node:async_hooks";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

type AgentDef = {
  name: string;
  description: string;
  tools?: string[];
  model?: string;
  body: string;
};

type TextContentBlock = { type: "text"; text: string };

const AGENTS_DIR = process.env.PI_AGENTS_DIR ?? join(getAgentDir(), "agents");
const MAX_CONCURRENCY = parsePositiveInt(process.env.PI_SUBAGENT_MAX_CONCURRENCY, 4);
const MAX_DEPTH = parsePositiveInt(process.env.PI_SUBAGENT_MAX_DEPTH, 2);
const depthStore = new AsyncLocalStorage<number>();

function parsePositiveInt(v: string | undefined, fallback: number): number {
  if (!v) return fallback;
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function loadAgent(name: string): AgentDef | undefined {
  const resolvedName = resolveAgentName(name);
  let text: string;
  try {
    text = readFileSync(join(AGENTS_DIR, `${resolvedName}.md`), "utf8");
  } catch {
    return undefined;
  }
  const { frontmatter, body } = parseFrontmatter<{
    name?: string;
    description?: string;
    tools?: unknown;
    model?: string;
  }>(text);
  if (!frontmatter.name) return undefined;

  return {
    name: String(frontmatter.name),
    description: String(frontmatter.description ?? ""),
    tools: parseToolList(frontmatter.tools),
    model: frontmatter.model ? String(frontmatter.model) : undefined,
    body: body.trim(),
  };
}

function resolveAgentName(name: string): string {
  const unqualified = name.includes(":") ? name.split(":").pop() ?? name : name;
  const aliases: Record<string, string> = {
    Explore: "explorer",
    "general-purpose": "explorer",
  };
  return aliases[unqualified] ?? unqualified;
}

function listAgents(): AgentDef[] {
  let entries: string[];
  try {
    entries = readdirSync(AGENTS_DIR);
  } catch {
    return [];
  }
  const agents: AgentDef[] = [];
  for (const entry of entries) {
    if (!entry.endsWith(".md")) continue;
    const def = loadAgent(entry.slice(0, -3));
    if (def) agents.push(def);
  }
  return agents;
}

function parseToolList(v: unknown): string[] | undefined {
  if (Array.isArray(v)) return v.map(String);
  if (typeof v !== "string") return undefined;
  const m = v.match(/^\s*\[([^\]]*)\]\s*$/);
  if (!m) return undefined;
  return m[1]
    .split(",")
    .map((t) => t.trim().replace(/^["']|["']$/g, ""))
    .filter(Boolean);
}

function textContent(text: string): TextContentBlock[] {
  return [{ type: "text", text }];
}

function toolResult(text: string): { content: TextContentBlock[] } {
  return { content: textContent(text) };
}

function errorResult(text: string): { isError: true; content: TextContentBlock[] } {
  return { isError: true, content: textContent(text) };
}

// Map Claude-style tool names to pi's tool names.
function normalizeTools(tools: string[]): string[] {
  return [...new Set(tools.map(normalizeToolName))];
}

function normalizeToolName(tool: string): string {
  if (tool.startsWith("mcp__")) {
    const match = tool.match(/^mcp__([^_]+)__/);
    if (match) return match[1].replace(/-/g, "_");
  }
  if (tool === "Task") return "subagent";
  if (tool === "AskUserQuestion") return "ask_question";
  return tool.toLowerCase();
}

// Extract plain text from an AssistantMessage by concatenating text-typed
// content blocks. Thinking blocks and tool calls are discarded.
function assistantText(message: { role?: string; content?: unknown }): string {
  if (message.role !== "assistant" || !Array.isArray(message.content)) return "";
  return message.content
    .filter((c: any) => c && c.type === "text" && typeof c.text === "string")
    .map((c: any) => c.text)
    .join("");
}

// Simple async semaphore.
class Semaphore {
  private inFlight = 0;
  private waiters: Array<() => void> = [];
  constructor(private readonly limit: number) {}
  async acquire(): Promise<void> {
    if (this.inFlight < this.limit) {
      this.inFlight++;
      return;
    }
    await new Promise<void>((resolve) => this.waiters.push(resolve));
    this.inFlight++;
  }
  release(): void {
    this.inFlight--;
    const next = this.waiters.shift();
    if (next) next();
  }
}

export default function register(pi: ExtensionAPI): void {
  const sem = new Semaphore(MAX_CONCURRENCY);
  const agentList = listAgents()
    .map((a) => `- ${a.name}: ${a.description.split(". ")[0]}`)
    .join("\n");

  pi.registerTool({
    name: "subagent",
    label: "Delegate to subagent",
    description:
      `Delegate a task to a specialized agent. Spins up an in-process pi session ` +
      `with the agent's body as the prompt prologue and runs it to completion.\n` +
      `Available agents:\n${agentList || "(no agents found at " + AGENTS_DIR + ")"}`,
    // Plain JSON Schema. Pi accepts any object that conforms; we avoid the
    // @sinclair/typebox dependency by hand-writing it.
    parameters: {
      type: "object",
      properties: {
        agent: { type: "string", description: "Agent name (must match an agent file in ~/.pi/agent/agents/)" },
        task: { type: "string", description: "Task description for the subagent" },
        model: { type: "string", description: "Override the agent's default model, e.g. anthropic/claude-opus-4-7" },
        tools: { type: "array", items: { type: "string" }, description: "Override the agent's tool allowlist" },
      },
      required: ["agent", "task"],
    } as any,
    async execute(_id, params, signal, onUpdate) {
      const { agent, task, model: modelOverride, tools: toolsOverride } = params as {
        agent: string;
        task: string;
        model?: string;
        tools?: string[];
      };

      const currentDepth = depthStore.getStore() ?? 0;
      if (currentDepth >= MAX_DEPTH) {
        return errorResult(
          `Subagent depth ${currentDepth} >= max ${MAX_DEPTH}. Refusing to spawn (set PI_SUBAGENT_MAX_DEPTH higher to allow).`,
        );
      }

      const def = loadAgent(agent);
      if (!def) {
        const available = listAgents().map((a) => a.name).sort().join(", ");
        return errorResult(`Unknown agent: ${agent}. Available: ${available || "(none)"}.`);
      }

      const effectiveTools = toolsOverride ?? def.tools;
      const effectiveModelSpec = modelOverride ?? def.model;

      // Resolve the optional model override against pi's registry. Format:
      // "provider/id", e.g. "anthropic/claude-opus-4-7".
      let resolvedModel: any = undefined;
      if (effectiveModelSpec) {
        const slash = effectiveModelSpec.indexOf("/");
        if (slash > 0) {
          const provider = effectiveModelSpec.slice(0, slash);
          const id = effectiveModelSpec.slice(slash + 1);
          const auth = AuthStorage.create();
          const registry = ModelRegistry.create(auth);
          resolvedModel = registry.find(provider, id);
          if (!resolvedModel) {
            return errorResult(`Model not found in registry: ${effectiveModelSpec}`);
          }
        }
      }

      await sem.acquire();
      try {
        return await depthStore.run(currentDepth + 1, async () => {
          const { session } = await createAgentSession({
            cwd: process.cwd(),
            sessionManager: SessionManager.inMemory(process.cwd()),
            tools: effectiveTools ? normalizeTools(effectiveTools) : undefined,
            model: resolvedModel,
          });

          // Surface assistant text as it arrives so the parent UI can show progress.
          const unsub = session.subscribe((ev) => {
            if (ev.type === "message_end") {
              const text = assistantText(ev.message as any);
              if (text && onUpdate) onUpdate({ content: text });
            }
          });

          // Forward cancellation: signal -> session.abort().
          const onAbort = () => {
            void session.abort();
          };
          signal?.addEventListener("abort", onAbort);

          try {
            await new Promise<void>((resolve, reject) => {
              const unsubEnd = session.subscribe((ev) => {
                if (ev.type === "agent_end") {
                  unsubEnd();
                  resolve();
                }
              });
              // Prepend the agent body as a user-message prologue. Pi has no
              // public API to override the system prompt mid-flight, so this is
              // the cleanest portable injection point. The LLM treats it as
              // role instructions because it's a wall of declarative text
              // before the task.
              const prompt = `${def.body}\n\n---\n\nTask: ${task}`;
              session.prompt(prompt).catch(reject);
            });

            // Pull the last assistant message from the in-memory transcript.
            const messages = session.messages;
            let text = "";
            for (let i = messages.length - 1; i >= 0; i--) {
              text = assistantText(messages[i] as any);
              if (text) break;
            }

            return toolResult(text || "(no assistant output)");
          } finally {
            signal?.removeEventListener("abort", onAbort);
            unsub();
            session.dispose();
          }
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return errorResult(msg);
      } finally {
        sem.release();
      }
    },
  });
}
