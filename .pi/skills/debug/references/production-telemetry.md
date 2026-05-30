# Production Telemetry (Phase 0)

Load when a bug targets a deployed service (prod or staging) and you need
Datadog evidence before attempting reproduction. Skip for purely local bugs.

## Environment Inference

Classify the bug's environment from `$ARGUMENTS` and conversation context.

| Signals | Scope | Org flag |
|---|---|---|
| `prod`, `production`, `live`, `customer`, `incident`, `outage`, `5xx`, `pager`, named deployed service | PROD | none (default = org 2) |
| `staging`, `stage`, `pre-prod`, `test env`, `staging-deployed`, `staging deploy` | STAGING | `--org 197728` |
| `my test`, `on my machine`, `local`, no service name, build/lint/unit failure | LOCAL | n/a — skip Phase 0 |
| Service name present but env unclear | AMBIGUOUS | ask user before continuing |

Datadog site is always `datadoghq.com`. Never pass `--site datad0g.com`.
The default site is correct.

## Ambiguity Fallback

When inference is ambiguous, ask the user:

```
ask_question(questions=[{
  "question": "Where is <service> deployed?",
  "header": "Environment",
  "multiSelect": false,
  "options": [
    {"label": "Production", "description": "Investigate Datadog org 2 (datadoghq.com)"},
    {"label": "Staging",    "description": "Investigate Datadog org 197728 (datadoghq.com)"},
    {"label": "Local only", "description": "Skip Phase 0, reproduce locally"}
  ]
}])
```

Persist the answer to `DEBUG.md` frontmatter as `scope`, `org`, `service`.

## Phase 0 Subagent Dispatch

Dispatch a general-purpose subagent that invokes the `/datadog` skill. The
subagent has no prior context — give it everything it needs in the prompt.

```
subagent(
  agent = "explorer",
  description = "Phase 0 telemetry for <service> in <env>",
  task = "
  <context>
  Bug: <one-line description>
  Service: <service-name>
  Environment: <prod|staging>
  Datadog org: <2|197728>          # leave empty for prod (default)
  Datadog site: datadoghq.com      # always
  Time window: <from-epoch> to <to-epoch>   # default: last 1h
  </context>

  <role>
  You are a read-only Datadog telemetry agent.
  Use the productivity:datadog skill via the pup CLI. Do not propose fixes.
  </role>

  <rules>
  - Never pass --site (default datadoghq.com is correct).
  - For staging, every pup command must include --org 197728.
  - For prod, do not pass --org (default org 2 is correct).
  - All pup output is JSON. Cache to /tmp/debug-phase0-*.json.
  - Write complex jq filters to /tmp/filter.jq and run jq -f.
  - Batch initial queries in parallel with & ... wait.
  </rules>

  <task>
  Run these queries in parallel and save responses to /tmp:

  1. Error logs:
     pup logs search --query 'service:<svc> status:error' --from <window> \\
       > /tmp/debug-phase0-logs.json

  2. Error tracking issues:
     pup error-tracking issues search > /tmp/debug-phase0-issues.json
     (then jq-filter for service tag)

  3. APM service stats:
     pup apm services stats --env <env> --start <from-epoch> --end <to-epoch> \\
       > /tmp/debug-phase0-apm.json

  4. Recent deploys:
     pup events search --query 'source:deploy service:<svc>' \\
       > /tmp/debug-phase0-deploys.json

  5. Alerting monitors:
     pup monitors list --tags 'service:<svc>' \\
       > /tmp/debug-phase0-monitors.json

  Then summarize:
  - Top 3 error messages (count, first/last seen, sample stack line)
  - Top 3 error-tracking issues (id, count, first occurrence)
  - Slowest or failing trace examples (operation, duration, error)
  - Last deploy event in the bug window (version/commit, timestamp)
  - Monitors currently in alert state (name, status, last triggered)
  </task>

  <constraints>
  - Cite the exact pup command for every finding.
  - Separate observations from inference.
  - Do not propose fixes or root causes.
  - If a query returns empty after retry with widened time window, say so.
  </constraints>"
)
```

## Telemetry Recipe (Reference)

Epoch math on macOS:

```bash
FROM=$(date -v-1H +%s)         # 1 hour ago
TO=$(date +%s)                 # now
```

On Linux: `FROM=$(date -d '1 hour ago' +%s)`.

Parallel query batch (prod service):

```bash
SVC=<service-name>
pup logs search --query "service:$SVC status:error" --from "1h" \
  > /tmp/debug-phase0-logs.json &
pup error-tracking issues search \
  > /tmp/debug-phase0-issues.json &
pup apm services stats --env prod --start "$FROM" --end "$TO" \
  > /tmp/debug-phase0-apm.json &
pup events search --query "source:deploy service:$SVC" --from "4h" \
  > /tmp/debug-phase0-deploys.json &
pup monitors list --tags "service:$SVC" \
  > /tmp/debug-phase0-monitors.json &
wait
```

Same batch for a staging service: add `--org 197728` to every `pup` call.
Replace `--env prod` with `--env staging` on the APM call.

## DEBUG.md Section Template

Append to `DEBUG.md` after Phase 0 completes:

```markdown
## Production Telemetry (Phase 0)

- Service: <name>
- Environment: <prod|staging>
- Org: <2|197728>
- Site: datadoghq.com
- Time window: <from-iso> to <to-iso>
- Phase 0 subagent run: <timestamp>

### Top Errors
- <count> x "<message>" — first <ts>, last <ts>

### Top Error-Tracking Issues
- ETI-<id>: <count> occurrences, first seen <ts>

### Failing Traces
- <operation> — <duration> — <error>

### Recent Deploys
- <version/commit> at <ts>

### Alerting Monitors
- <monitor-name> — <status> — last triggered <ts>

### Raw Responses
- /tmp/debug-phase0-logs.json
- /tmp/debug-phase0-issues.json
- /tmp/debug-phase0-apm.json
- /tmp/debug-phase0-deploys.json
- /tmp/debug-phase0-monitors.json
```

## Anti-Patterns

| Rationalization | Reality |
|---|---|
| "I'll pass `--site datad0g.com` for staging" | Wrong site. Staging services are queried on `datadoghq.com` with `--org 197728`. |
| "I'll guess the org from gut feel" | Check the env signals or ask. Wrong org returns empty results that look like the bug is silent. |
| "Just list all logs, I'll filter later" | Unfiltered listings are slow, expensive, and hit rate limits. Always pass `service:` and `--from`. |
| "Phase 0 is optional — I'll reproduce first" | The whole point of Phase 0 is that reproduction is faster with telemetry inputs (timestamps, payloads, error variants). |
| "I'll propose a fix from Phase 0 evidence" | Phase 0 gathers evidence only. Hypotheses and fixes belong to Phase 1+. |
| "I'll skip parallelism" | Five sequential pup calls is five round-trips. Batch with `&` and `wait`. |

## Cross-References

- `/datadog` skill — full pup CLI usage, query syntax, jq patterns.
- `productivity/skills/datadog/references/query-patterns.md` — response
  schemas and jq filters per domain.
- `references/root-cause-tracing.md` — how to use Phase 0 findings to
  start backward tracing in Phase 1.
