# Advanced Workspace Configuration

## Instance Types

| Instance | vCPUs | RAM | Storage | Arch | Region |
|----------|-------|-----|---------|------|--------|
| `aws:m5d.4xlarge` | 16 | 64 GB | 600 GB NVMe | x86_64 | All |
| `aws:m6gd.4xlarge` | 16 | 64 GB | 950 GB NVMe | ARM Graviton2 | All |
| `aws:g5.2xlarge` | 8 | 32 GB + GPU | 450 GB NVMe | x86_64 + NVIDIA A10G | us-east-1 only |

## Persistent Configuration

Save defaults in `~/.config/datadog/workspaces/config.yaml`:

```yaml
shell: fish
region: eu-west-3
dotfiles: https://github.com/rtfpessoa/dotfiles
vscode-extensions:
  - "bazelbuild.vscode-bazel"
```

## Secrets Management

```bash
workspaces secrets set KEY=VALUE            # Register secret (future workspaces only)
workspaces secrets set KEY=VALUE --export   # Set as env var (not just file)
workspaces secrets list                     # List registered secrets
workspaces secrets get KEY                  # View metadata (not value)
workspaces secrets remove KEY               # Unregister
```

Secrets land in workspace at: `/run/user/$(id -u bits)/secrets/<key>`.

Secrets only propagate to **future** workspaces, not existing ones. To inject into an existing workspace, recreate it.

Disallowed secret names: `PATH`, `ENV`, `USER`, `SHELL`, `HOME`.

## Claude Code in Workspaces

Claude Code is pre-installed in workspaces. If API key is not auto-injected:

```bash
# Before workspace creation — register API key as a secret
workspaces secrets set ANTHROPIC_APIKEY1=<key>
```

## Workspace Lifecycle

| Event | Timing |
|-------|--------|
| Garbage collection | After 20 days of SSH inactivity |
| Hard TTL | 6 months regardless of activity |
| Notifications | Slack SDM Bot at 14, 7, 1 day(s) before deletion |

SSHing in (directly or via IDE) resets the 20-day inactivity clock.

## Devcontainer

Default: `.devcontainer/datadog/default/devcontainer.json` in the repo.

Override with `--devcontainer-config <path>` flag on create.

Pre-built images available for: `dd-source`, `dd-go`, `logs-backend`, `driveline`.

## Regions

| Region | Location |
|--------|----------|
| `us-east-1` | N. Virginia, USA |
| `eu-west-3` | Paris, France |

Choose the region closest to your physical location.

## Additional Create Flags

| Flag | Purpose |
|------|---------|
| `--open-editor` | Open editor immediately after creation |
| `--editor` | `vscode`, `cursor`, `intellij`, `pycharm`, `goland` |
| `--vscode-extensions` | Comma-delimited extension IDs |
| `--jetbrains-plugins` | Comma-delimited plugin IDs |
| `--vscode-template` | Path to a `.code-workspace` template file |
| `--devcontainer-config` | Path to a `devcontainer.json` |
| `--instance-type` | Override instance type |

## Updating Tools Inside Workspace

```bash
update-tool <name>    # NOT brew — use the workspace tool manager
```

## Workspaces API (gRPC)

For programmatic access:

| Endpoint | URL |
|----------|-----|
| Staging | `workspaces-api.us1.ddbuild.staging.dog:443` |
| Production | `workspaces-api.us1.ddbuild.io:443` |

Auth: `ddtool auth token --datacenter <datacenter> rapid-devex-workspaces`

Key RPCs on `workspaces_api.WorkspacesAPI`: `ListWorkspaces`, `CreateWorkspace`, `DeleteWorkspace`, `GetWorkspace`, `StreamWorkflowStatus`, `AgentRun`.

Proto source: `domains/devex/workspaces/apps/apis/workspaces-api/workspaces-api-pb/workspaces_api.proto` in `dd-source`.

## Support

- Slack: [#workspaces](https://dd.enterprise.slack.com/archives/C02PW2547B9)
- Confluence: "Workspaces (official)" in DEVX space
