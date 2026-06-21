# Dev Environment — code-server + opencode + mise

## Quick start

```bash
# 1. Copy and edit environment
cp .env.example .env
#    Edit .env: set HOME_MOUNT, CODE_SERVER_PASSWORD, OPENCODE_PASSWORD, etc.

# 2. First build (takes 5-15 min)
docker compose build --no-cache

# 3. Start
docker compose up -d

# 4. Check logs
docker compose logs -f
```

| Service | URL | Credentials |
|---------|-----|-------------|
| code-server | http://localhost:8443 | password: set in .env |
| opencode web | http://localhost:3000 | password: set in .env |

## What's inside

- **code-server** — VS Code in the browser
- **opencode** — open source AI coding agent with web UI (starts automatically on boot)
- **Nix** — functional package manager for additional CLI tools
- **mise** — polyglot tool version manager (Node.js, Rust, Go, Python, …)
- **Docker CLI** — talks to the host Docker socket (no Docker-in-Docker)
- Your **home/project directory** mounted — dotfiles, SSH keys, code, mise data all persist

## Data persistence

Your chosen directory is mounted at `/home/dev` inside the container. Everything stored there persists across rebuilds.

Set it in [`.env`](.env):

```env
HOME_MOUNT=/mnt/Data/Dev   # Host path to mount (default: ~)
```

> **Note**: The directory must be writable by your user on the host. If you see EACCES errors, check `ls -ld $HOME_MOUNT` — it should be owned by you, not root.

The Nix store is persisted at `$HOME_MOUNT/.nix` on the host, so installed packages survive container rebuilds.

To mount additional host paths (e.g. another project directory), create [`docker-compose.override.yml`](docker-compose.override.yml) (Docker Compose loads it automatically):

```yaml
services:
  dev:
    volumes:
      - "${HOME_MOUNT:-~}:/home/dev:consistent,z"
      - /var/run/docker.sock:/var/run/docker.sock
      - ./post-install.sh:/app/post-install.sh:ro
      # ^ copy default volumes above, then add yours:
      - /path/to/project:/workspace/project
      - /another/path:/another:ro
```

## Updating components

All build-time versions default to `latest`. Set specific versions in `.env` to pin:

```env
NIX_VERSION=2.34.7           # Nix package manager
CODE_SERVER_VERSION=4.123.0  # code-server release
OPENCODE_VERSION=latest      # opencode AI agent
```

Rebuild to update:

```bash
docker compose build --no-cache && docker compose up -d
```

Override without editing `.env`:

```bash
CODE_SERVER_VERSION=4.123.0 docker compose build --no-cache
```

mise tools also default to latest:

```env
MISE_DEFAULT_TOOLS=nodejs@latest python@latest rust@latest go@latest
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
docker compose exec -u dev dev bash

# Change code-server password
docker compose exec dev sed -i "s/password:.*/password: newpass/" ~/.config/code-server/config.yaml
docker compose restart dev
```

## Architecture

```
┌───────────────────────────────────────────────────────┐
│  Container dev                                         │
│                                                         │
│  ┌──────────────┐   ┌──────────────────────┐          │
│  │ code-server  │   │ opencode web          │          │
│  │ :8443        │   │ :3000                 │          │
│  └──────────────┘   └──────────────────────┘          │
│                                                         │
│  ┌────────────────┐  ┌──────────────────────┐          │
│  │ docker (CLI)   │  │ mise (Node, Rust,    │          │
│  │ ↓/var/run/     │  │ Go, Python, …)       │          │
│  │   docker.sock  │  └──────────────────────┘          │
│  └────────────────┘  ┌──────────────────────┐          │
│                       │ Nix (/nix)           │          │
│                       │ persisted via bind   │          │
│                       └──────────────────────┘          │
│                                                         │
│  Mounts: <HOME_MOUNT> → /home/dev  (persistent)          │
│          <HOME_MOUNT>/.nix → /nix  (persistent)          │
│          /var/run/docker.sock                           │
└───────────────────────────────────────────────────────┘
```

## File layout

```
├── Dockerfile         # Single-stage: dev tools + Nix + opencode
├── docker-compose.yml # Service definition + build args
├── entrypoint.sh      # UID matching, mise, Nix, code-server + opencode launch
├── post-install.sh    # Run inside container to install CLI agents
├── .env               # All configurable versions and settings
└── README.md
```

## Details

### File ownership

The entrypoint reads the UID/GID from your mounted directory and creates a `dev` user that matches. Files created inside the container are owned by you on the host.

### code-server

Config is at `~/.config/code-server/config.yaml` (persisted on host). The entrypoint pre-creates it with the password from `CODE_SERVER_PASSWORD` env var (default: `devpass`). The user data directory at `~/.local/share/code-server/` is also created on startup.

### opencode

Installed at build time via the official install script. The web server starts automatically on container boot at `0.0.0.0:3000`. Set `OPENCODE_PASSWORD` in `.env` to require authentication.

### Nix

Installed at build time. The Nix store (`/nix`) is persisted via a bind mount at `$HOME_MOUNT/.nix`. On first start, the entrypoint restores the store from an image backup. Use `nix profile add nixpkgs#<pkg>` to install packages.

### Docker access

`/var/run/docker.sock` is mounted read-write. The entrypoint detects the socket's group GID and adds the `dev` user to it. Use `docker` CLI inside the container as if you were on the host.

### mise

Installed at build time. Tools defined in `MISE_DEFAULT_TOOLS` are installed automatically on first run. All mise data persists at `~/.local/share/mise/` on the host.

### Post-install script

Run [`post-install.sh`](post-install.sh) inside the container to install additional CLI tools (agents, editors, utilities, …):

```bash
docker compose exec -u dev dev bash
bash /app/post-install.sh
```

Edit the script on the host to add or remove tools, then re-run it. Changes take effect immediately (no rebuild).
