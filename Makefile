.PHONY: all install lint check check-frontmatter check-agents check-refs check-agent-refs check-descriptions check-structure check-versions check-opencode-sync sync-opencode check-codex-sync sync-codex check-pi-sync sync-pi check-mcp-sync sync-mcp help

all: check lint ## Run all checks (frontmatter, agents, refs, structure, plugins, lint)

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Symlink configuration files into the home directory
	./init.sh

lint: ## Validate JSON and JSONC files
	@echo "Validating JSON files..."
	@ok=true; \
	for f in $$(find . -name '*.json' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); do \
		if python3 -m json.tool "$$f" > /dev/null 2>&1; then \
			echo "  OK  $$f"; \
		else \
			echo "  FAIL  $$f"; \
			python3 -m json.tool "$$f" 2>&1 | head -3 | sed 's/^/         /'; \
			ok=false; \
		fi; \
	done; \
	if [ "$$ok" = false ]; then exit 1; fi
	@echo "Validating JSONC files..."
	@ok=true; \
	jsonc_files=$$(find . -name '*.jsonc' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); \
	if [ -z "$$jsonc_files" ]; then \
		echo "  SKIP  no JSONC files found"; \
	elif command -v node > /dev/null 2>&1; then \
		for f in $$jsonc_files; do \
			if node ./validate-jsonc.mjs "$$f" 2>/dev/null; then \
				echo "  OK  $$f"; \
			else \
				echo "  FAIL  $$f"; \
				node ./validate-jsonc.mjs "$$f"; \
				ok=false; \
			fi; \
		done; \
		if [ "$$ok" = false ]; then exit 1; fi \
	else \
		echo "  SKIP  JSONC files (node not found; install Node.js for JSONC validation)"; \
	fi
	@echo "Done."

check-frontmatter: ## Validate SKILL.md files have required YAML frontmatter fields
	@echo "Checking skill frontmatter..."
	@ok=true; \
	for skill in $$(find . -path '*/skills/*/SKILL.md' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); do \
		missing=""; \
		if ! head -20 "$$skill" | grep -q '^name:'; then \
			missing="$$missing name"; \
		fi; \
		if ! head -20 "$$skill" | grep -q '^description:'; then \
			missing="$$missing description"; \
		fi; \
		if ! head -20 "$$skill" | grep -q '^argument-hint:'; then \
			missing="$$missing argument-hint"; \
		fi; \
		if ! head -20 "$$skill" | grep -q '^user-invocable:'; then \
			missing="$$missing user-invocable"; \
		fi; \
		if [ -n "$$missing" ]; then \
			echo "  FAIL  $$skill (missing:$$missing)"; \
			ok=false; \
		else \
			echo "  OK  $$skill"; \
		fi; \
	done; \
	if [ "$$ok" = false ]; then exit 1; fi
	@echo "All frontmatter checks passed."

check-agents: ## Validate agent files have required YAML frontmatter fields
	@echo "Checking agent frontmatter..."
	@ok=true; \
	agents=$$(find . -path '*/agents/*.md' -not -path '*/agents/references/*' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); \
	if [ -z "$$agents" ]; then \
		echo "  SKIP  no agent files found"; \
	else \
		for agent in $$agents; do \
			missing=""; \
			if ! head -20 "$$agent" | grep -q '^name:'; then \
				missing="$$missing name"; \
			fi; \
			if ! head -20 "$$agent" | grep -q '^description:'; then \
				missing="$$missing description"; \
			fi; \
			if [ -n "$$missing" ]; then \
				echo "  FAIL  $$agent (missing:$$missing)"; \
				ok=false; \
			else \
				echo "  OK  $$agent"; \
			fi; \
		done; \
	fi; \
	if [ "$$ok" = false ]; then exit 1; fi
	@echo "All agent frontmatter checks passed."

check-refs: ## Validate skill cross-references (e.g. /commit, /branch) resolve to real skills
	@echo "Checking skill cross-references..."
	@ok=true; \
	for skill in $$(find . -path '*/skills/*/SKILL.md' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); do \
		refs=$$(grep -oE '`/[a-z][-a-z0-9]+`' "$$skill" | sed 's/`//g;s|^/||' | sort -u); \
		for ref in $$refs; do \
			found=$$(find . -path "*/skills/$$ref/SKILL.md" -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' 2>/dev/null); \
			if [ -z "$$found" ]; then \
				echo "  FAIL  $$skill references /$$ref but no skill found at */skills/$$ref/SKILL.md"; \
				ok=false; \
			fi; \
		done; \
	done; \
	if [ "$$ok" = false ]; then exit 1; fi
	@echo "All cross-reference checks passed."

check-descriptions: ## Validate skill descriptions start with "Use when" (convention)
	@echo "Checking skill description conventions..."
	@ok=true; \
	for skill in $$(find . -path '*/skills/*/SKILL.md' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); do \
		desc=$$(awk '/^description:/{found=1; sub(/^description:[[:space:]]*>?[[:space:]]*/, ""); if(NF) print; next} found && /^[[:space:]]/{sub(/^[[:space:]]+/, ""); print; next} found{exit}' "$$skill" | head -1); \
		if echo "$$desc" | grep -q '^Use when'; then \
			echo "  OK  $$skill"; \
		else \
			echo "  WARN  $$skill (description should start with 'Use when')"; \
		fi; \
	done
	@echo "Done."

check-agent-refs: ## Validate skill references in agent files resolve to real skills
	@echo "Checking agent skill cross-references..."
	@ok=true; \
	agents=$$(find . -path '*/agents/*.md' -not -path '*/agents/references/*' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); \
	if [ -z "$$agents" ]; then \
		echo "  SKIP  no agent files found"; \
	else \
		for agent in $$agents; do \
			refs=$$(grep -oE '`/[a-z][-a-z0-9]+`' "$$agent" | sed 's/`//g;s|^/||' | sort -u); \
			for ref in $$refs; do \
				found=$$(find . -path "*/skills/$$ref/SKILL.md" -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' 2>/dev/null); \
				if [ -z "$$found" ]; then \
					echo "  FAIL  $$agent references /$$ref but no skill found at */skills/$$ref/SKILL.md"; \
					ok=false; \
				fi; \
			done; \
		done; \
	fi; \
	if [ "$$ok" = false ]; then exit 1; fi
	@echo "All agent cross-reference checks passed."

check-structure: ## Validate SKILL.md files have required structure (Announce, Steps, Error Handling)
	@echo "Checking skill structure..."
	@ok=true; \
	for skill in $$(find . -path '*/skills/*/SKILL.md' -not -path './.git/*' -not -path './.plans/*' -not -path './.codex/*' -not -path './.pi/*' | sort); do \
		missing=""; \
		if ! grep -q '^Announce:' "$$skill"; then \
			missing="$$missing Announce"; \
		fi; \
		if ! grep -qE '^## Step [0-9]+' "$$skill"; then \
			missing="$$missing Steps"; \
		fi; \
		if ! grep -q '^## Error Handling' "$$skill"; then \
			missing="$$missing ErrorHandling"; \
		fi; \
		if [ -n "$$missing" ]; then \
			echo "  WARN  $$skill (missing:$$missing)"; \
		else \
			echo "  OK  $$skill"; \
		fi; \
	done
	@echo "Done."

check-versions: ## Warn if plugin content changed since last commit without a version bump
	@echo "Checking plugin version bumps..."
	@for source in $$(python3 -c "import json; data=json.load(open('.claude-plugin/marketplace.json')); print('\n'.join(p['source'] for p in data['plugins']))"); do \
		plugin=$$(basename "$$source"); \
		manifest="$$source/.claude-plugin/plugin.json"; \
		if [ ! -f "$$manifest" ]; then continue; fi; \
		content_changed=$$(git diff HEAD -- "$$source/skills/" "$$source/agents/" 2>/dev/null | head -1); \
		if [ -z "$$content_changed" ]; then \
			content_changed=$$(git diff --cached HEAD -- "$$source/skills/" "$$source/agents/" 2>/dev/null | head -1); \
		fi; \
		if [ -n "$$content_changed" ]; then \
			version_changed=$$(git diff HEAD -- "$$manifest" 2>/dev/null | head -1); \
			if [ -z "$$version_changed" ]; then \
				version_changed=$$(git diff --cached HEAD -- "$$manifest" 2>/dev/null | head -1); \
			fi; \
			if [ -z "$$version_changed" ]; then \
				echo "  WARN  $$plugin: skills/agents changed but $$manifest version not bumped"; \
			else \
				echo "  OK  $$plugin"; \
			fi; \
		else \
			echo "  OK  $$plugin (no content changes)"; \
		fi; \
	done
	@echo "Done."

sync-opencode: ## Sync skills and agents to OpenCode config directory
	@./sync-opencode.sh

check-opencode-sync: ## Validate OpenCode sync is up-to-date
	@./sync-opencode.sh --check

sync-codex: ## Sync skills and agents to Codex config directory
	@./sync-codex.sh

check-codex-sync: ## Validate Codex sync is up-to-date
	@./sync-codex.sh --check

sync-pi: ## Sync skills, prompts, agents, and MCP extension to Pi config directory
	@./sync-pi.sh

check-pi-sync: ## Validate Pi sync is up-to-date
	@./sync-pi.sh --check

sync-mcp: ## Sync MCP servers from mcp.json to opencode.jsonc
	@./sync-mcp.sh

check-mcp-sync: ## Validate opencode.jsonc MCP block is up-to-date with mcp.json
	@./sync-mcp.sh --check

check: check-frontmatter check-agents check-refs check-agent-refs check-descriptions check-structure check-versions check-opencode-sync check-codex-sync check-pi-sync check-mcp-sync ## Run all validation checks (frontmatter, agents, refs, structure, plugins)
	@echo "Checking plugin references..."
	@ok=true; \
	for source in $$(python3 -c "import json; data=json.load(open('.claude-plugin/marketplace.json')); print('\n'.join(p['source'] for p in data['plugins']))"); do \
		manifest="$$source/.claude-plugin/plugin.json"; \
		if [ -d "$$source" ] && [ -f "$$manifest" ]; then \
			echo "  OK  $$source ($$manifest exists)"; \
		else \
			echo "  FAIL  $$source (missing $$manifest)"; \
			ok=false; \
		fi; \
	done; \
	if [ "$$ok" = false ]; then exit 1; fi
	@echo "All checks passed."
