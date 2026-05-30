// Interactive question tool for pi.dev.
//
// Generated Pi skills are rewritten from Claude's AskUserQuestion calls to
// `ask_question`. This extension provides that tool using Pi's UI primitives.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type TextContentBlock = { type: "text"; text: string };

type QuestionSpec = {
  id?: unknown;
  header?: unknown;
  title?: unknown;
  question?: unknown;
  message?: unknown;
  placeholder?: unknown;
  options?: unknown;
  multiSelect?: unknown;
};

type NormalizedOption = {
  label: string;
  value?: string;
  description?: string;
};

type QuestionAnswer = {
  id?: string;
  question: string;
  answer: string;
  value?: string;
  description?: string;
};

function textContent(text: string): TextContentBlock[] {
  return [{ type: "text", text }];
}

function toolResult(text: string): { content: TextContentBlock[] } {
  return { content: textContent(text) };
}

function errorResult(text: string): { isError: true; content: TextContentBlock[] } {
  return { isError: true, content: textContent(text) };
}

function stringValue(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return undefined;
}

function normalizeQuestions(params: Record<string, unknown>): QuestionSpec[] {
  if (Array.isArray(params.questions) && params.questions.length > 0) {
    return params.questions.filter((q): q is QuestionSpec => q !== null && typeof q === "object");
  }
  return [params as QuestionSpec];
}

function normalizeOptions(value: unknown): NormalizedOption[] {
  if (!Array.isArray(value)) return [];

  const options: NormalizedOption[] = [];
  for (const item of value) {
    if (typeof item === "string") {
      const label = item.trim();
      if (label) options.push({ label });
      continue;
    }

    if (!item || typeof item !== "object") continue;
    const raw = item as Record<string, unknown>;
    const label = stringValue(raw.label) ?? stringValue(raw.value) ?? stringValue(raw.description);
    if (!label) continue;
    const valueText = stringValue(raw.value);
    const description = stringValue(raw.description);
    options.push({
      label,
      value: valueText && valueText !== label ? valueText : undefined,
      description: description && description !== label ? description : undefined,
    });
  }

  return options;
}

function questionTitle(question: QuestionSpec): string {
  return (
    stringValue(question.question) ??
    stringValue(question.message) ??
    stringValue(question.title) ??
    stringValue(question.header) ??
    "Question"
  );
}

function inputPlaceholder(question: QuestionSpec, options: NormalizedOption[]): string | undefined {
  const explicit = stringValue(question.placeholder) ?? stringValue(question.message);
  if (options.length === 0) return explicit;

  const rendered = options.map((option) => option.label).join(", ");
  const prefix = explicit ? `${explicit} ` : "";
  return `${prefix}Options: ${rendered}`;
}

function optionDisplay(option: NormalizedOption): string {
  return option.description ? `${option.label} - ${option.description}` : option.label;
}

function formatAnswer(answer: QuestionAnswer): string {
  return JSON.stringify(answer, null, 2);
}

function formatAnswers(answers: QuestionAnswer[]): string {
  if (answers.length === 1) return formatAnswer(answers[0]);
  return JSON.stringify({ answers }, null, 2);
}

export default function register(pi: ExtensionAPI): void {
  pi.registerTool({
    name: "ask_question",
    label: "Ask user",
    description:
      "Ask the user a clarifying question. Supports a single question or a questions array, with optional choices.",
    promptSnippet: "ask_question: ask the user for clarification or a decision when required.",
    parameters: {
      type: "object",
      properties: {
        header: { type: "string", description: "Short title for the prompt" },
        title: { type: "string", description: "Prompt title" },
        question: { type: "string", description: "Question to ask" },
        message: { type: "string", description: "Question or supporting text" },
        placeholder: { type: "string", description: "Placeholder text for free-form input" },
        options: {
          type: "array",
          description: "Optional answer choices",
          items: {
            anyOf: [
              { type: "string" },
              {
                type: "object",
                properties: {
                  label: { type: "string" },
                  value: { type: "string" },
                  description: { type: "string" },
                },
                additionalProperties: true,
              },
            ],
          },
        },
        multiSelect: { type: "boolean", description: "Whether the user may enter multiple choices" },
        questions: {
          type: "array",
          description: "Claude AskUserQuestion-style question list",
          items: {
            type: "object",
            properties: {
              id: { type: "string" },
              header: { type: "string" },
              title: { type: "string" },
              question: { type: "string" },
              message: { type: "string" },
              placeholder: { type: "string" },
              options: {
                type: "array",
                items: {
                  anyOf: [
                    { type: "string" },
                    { type: "object", additionalProperties: true },
                  ],
                },
              },
              multiSelect: { type: "boolean" },
            },
            additionalProperties: true,
          },
        },
      },
      additionalProperties: true,
    } as any,
    executionMode: "sequential",
    async execute(_id, params, signal, _onUpdate, ctx) {
      const questions = normalizeQuestions(params as Record<string, unknown>);
      if (questions.length === 0) {
        return errorResult("No question was provided.");
      }

      const answers: QuestionAnswer[] = [];
      for (const question of questions) {
        const title = questionTitle(question);
        const options = normalizeOptions(question.options);
        const id = stringValue(question.id);

        if (options.length > 0 && question.multiSelect !== true) {
          const displays = options.map(optionDisplay);
          const selected = await ctx.ui.select(title, displays, { signal });
          if (!selected) return errorResult(`No response provided for: ${title}`);

          const selectedIndex = displays.indexOf(selected);
          const option = options[selectedIndex] ?? { label: selected };
          answers.push({
            id,
            question: title,
            answer: option.label,
            value: option.value,
            description: option.description,
          });
          continue;
        }

        const answer = await ctx.ui.input(title, inputPlaceholder(question, options), { signal });
        if (!answer) return errorResult(`No response provided for: ${title}`);
        answers.push({ id, question: title, answer });
      }

      return toolResult(formatAnswers(answers));
    },
  });
}
