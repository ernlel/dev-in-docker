# Dev Environment — code-server + AionUI Web + mise

## Quick start

```bash
# 1. Copy and edit environment
cp .env.example .env
#    Edit .env: set HOST_HOME, CODE_SERVER_PASSWORD, AIONUI_PASSWORD, etc.

# 2. First build (takes 5-15 min)
docker compose build --no-cache

# 3. Start
docker compose up -d

# 4. Check logs
docker compose logs -f
```

| Service | URL | Credentials |
|---------|-----|-------------|
| code-server | http://localhost:8443 | password: set in .env|
| AionUI Web | http://localhost:3000 | username: admin, password set in .env|

## What's inside

- **code-server** — VS Code in the browser
- **AionUI Web** — AI agent cowork platform (starts alongside code-server)
- **mise** — polyglot tool version manager (Node.js, Rust, Go, Python, …)
- **Docker CLI** — talks to the host Docker socket (no Docker-in-Docker)
- Your **home/project directory** mounted — dotfiles, SSH keys, code, mise data all persist

## AionUI admin password

AionUI generates a random password on first launch. Find it in the logs:

```bash
docker compose logs dev | grep "AionUI:"
```

Expected output:
```
>>> AionUI: Initial admin password: R3pL8x...
>>> AionUI: Login username: admin
```

To set a **specific** password, set `AIONUI_PASSWORD` in `.env` before starting:

```env
AIONUI_PASSWORD=my-secure-pass
```

If you forget the password, generate a new random one:

```bash
docker compose exec dev bun /app/aionui/scripts/resetpass.ts
```

## Data persistence

Your chosen directory is mounted at `/home/dev` inside the container. Everything stored there persists across rebuilds.

Set it in [`.env`](.env):

```env
HOST_HOME=/mnt/Data/Dev   # Host path to mount (default: ~)
CONTAINER_HOME=/home/dev  # Mount target (don't change unless you update entrypoint)
```

> **Note**: The directory must be writable by your user on the host. If you see EACCES errors, check `ls -ld $HOST_HOME` — it should be owned by you, not root.

## Updating components

All build-time versions are in [`.env`](.env):

```env
NODE_VERSION=24          # Node.js version for the AionUI builder
AIONUI_TAG=v2.1.18       # AionUI release tag
AIONCORE_VERSION=v0.1.30 # AionCore backend binary
CODE_SERVER_VERSION=4.123.0  # code-server release
```

Change any value, then rebuild:

```bash
docker compose build --no-cache && docker compose up -d
```

Override without editing `.env`:

```bash
AIONUI_TAG=v2.2.0 AIONCORE_VERSION=v0.1.31 docker compose build --no-cache
```

## Common commands

```bash
# Start / stop
docker compose up -d
docker compose down

# Logs
docker compose logs -f
docker compose logs dev -f --tail=50

# Rebuild and restart
docker compose build --no-cache && docker compose up -d

# Open a shell inside the container
docker compose exec dev bash

# Change code-server password
docker compose exec dev sed -i "s/password:.*/password: newpass/" ~/.config/code-server/config.yaml
docker compose restart dev
```

## Architecture

```
┌───────────────────────────────────────────────────────┐
│  Container dev                                         │
│                                                         │
│  ┌──────────────┐   ┌─────────────────────────────┐   │
│  │ code-server  │   │ AionUI Web                  │   │
│  │ :8443        │   │                             │   │
│  │              │   │  ┌──────────────────────┐   │   │
│  │              │   │  │ webui.ts (Bun) :3000 │   │   │
│  │              │   │  └─────────┬────────────┘   │   │
│  └──────────────┘   │            │                 │   │
│                      │  ┌────────┴────────────┐   │   │
│  ┌────────────────┐  │  │ aioncore (Rust)     │   │   │
│  │ docker (CLI)   │  │  │ SQLite / MCP / ACP  │   │   │
│  │ ↓/var/run/     │  │  └─────────────────────┘   │   │
│  │   docker.sock  │  │                             │   │
│  └────────────────┘  │  ┌──────────────────────┐   │   │
│                       │  │ mise (Node, Rust,    │   │   │
│                       │  │ Go, Python, …)       │   │   │
│                       │  └──────────────────────┘   │   │
│                                                         │
│  Mounts: <HOST_HOME> → /home/dev  (persistent)          │
│          /var/run/docker.sock                           │
└───────────────────────────────────────────────────────┘
```

## File layout

```
├── Dockerfile         # Multi-stage: builds AionUI + dev tools + agents
├── docker-compose.yml # Service definition + build args
├── entrypoint.sh      # UID matching, mise, code-server + AionUI launch
├── .env               # All configurable versions and settings
└── README.md
```

## Details

### File ownership

The entrypoint reads the UID/GID from your mounted directory and creates a `dev` user that matches. Files created inside the container are owned by you on the host.

### code-server

Config is at `~/.config/code-server/config.yaml` (persisted on host). The entrypoint pre-creates it with the password from `CODE_SERVER_PASSWORD` env var (default: `devpass`). The user data directory at `~/.local/share/code-server/` is also created on startup.

### AionUI Web

AionUI consists of two repos:
- **AionUi** (TypeScript) — cloned from `AIONUI_REPO` at tag `AIONUI_TAG` and built at Docker build time
- **AionCore** (Rust) — downloaded as a prebuilt binary from GitHub releases at version `AIONCORE_VERSION`

Both run in the same container. Data persists at `~/.aionui-web/` on the host.

### Docker access

`/var/run/docker.sock` is mounted read-write. The entrypoint detects the socket's group GID and adds the `dev` user to it. Use `docker` CLI inside the container as if you were on the host.

### mise

Installed at build time. Tools defined in `MISE_DEFAULT_TOOLS` are installed automatically on first run. All mise data persists at `~/.local/share/mise/` on the host.

### CLI agents

AionUI auto-detects CLI coding agents on PATH. Set `AIONUI_CLI_AGENTS` in `.env` before **building** to bake agents into the image:

```env
AIONUI_CLI_AGENTS=claude,codex,copilot,opencode
```

Then rebuild:

```bash
docker compose build --no-cache && docker compose up -d
```

Agents install at build time in the `aionui-builder` stage — the resulting binaries land in `/usr/local/bin/` and are copied to the final image. This avoids download overhead and interactive prompts at container start.

Supported agent names:

| Agent name      | CLI command    | Install method                                                               | AionUI |
|-----------------|----------------|------------------------------------------------------------------------------|--------|
| `claude`        | `claude`       | `npm install -g @anthropic-ai/claude-code`                                   | ✓      |
| `codex`         | `codex`        | `npm install -g @openai/codex`                                               | ✓      |
| `copilot`       | `copilot`      | `npm install -g @github/copilot`                                             | ✓      |
| `opencode`      | `opencode`     | `npm install -g opencode-ai`                                                 | ✓      |
| `goose`         | `goose`        | Direct binary download from GitHub releases                                  | ✓      |
| `gemini`        | `gemini`       | `npm install -g @google/gemini-cli`                                          | ✓      |
| `qwen`          | `qwen`         | `curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh \| bash` | ✓ |
| `augment`       | `auggie`       | `npm install -g @augmentcode/auggie`                                         | ✓      |
| `codebuddy`     | `codebuddy`    | `npm install -g @tencent-ai/codebuddy-code`                                  | ✓      |
| `kimi`          | `kimi`         | `curl -fsSL https://code.kimi.com/kimi-code/install.sh \| bash`               | ✓      |
| `factory`       | `droid`        | `curl -fsSL https://app.factory.ai/cli \| sh`                                 | ✓      |
| `qoder`         | `qoder`        | `curl -fsSL https://qoder.com/install \| bash`                                | ✓      |
| `mistral-vibe`  | `vibe-acp`     | `curl -LsSf https://mistral.ai/vibe/install.sh \| bash`                        | ✓      |
| `snow`          | `snow`         | `npm install -g snow-ai`                                                     | ✓      |
| `hermes`        | `hermes`       | `curl -fsSL https://hermes-agent.nousresearch.com/install.sh \| bash`          | ✓      |
| `cursor-agent`  | `cursor-agent` | `npm install -g @cursor/cli`                                                 | ✓      |
| `kiro`          | `kiro`         | `curl -fsSL https://cli.kiro.dev/install \| bash`                             | ✓      |
| `openclaw`      | `openclaw`     | `npm install -g openclaw@latest`                                             | ✓      |
| `nanobot`       | `nanobot`      | `pip install nanobot-ai`                                                     | ✓      |
| `iflow`         | `iflow`        | `npm install -g @iflow-ai/iflow-cli`                                         | ✓      |
| `pi`            | `pi`           | `npm install -g @earendil-works/pi-coding-agent`                             | ✗      |
| `kilo`          | `kilo`         | `npm install -g @kilocode/cli`                                               | ✗      |
| `grok`          | `grok`         | `curl -fsSL https://x.ai/cli/install.sh \| bash`                              | ✗      |

Agents marked ✗ are **not supported by AionUI** — AionUI won't auto-detect them on PATH. They are still installed and can be used from the command line.

To add an agent after build, use `npm install -g <package>` inside the container (mise-managed Node.js is on PATH). Each agent needs its own API key or subscription configured separately (e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) — set those in your `.env` or shell profile.
