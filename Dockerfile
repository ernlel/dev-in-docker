# ======================================================================
#  Version overrides — pass via --build-arg or docker-compose build.args
#  Defaults to "latest" — set specific versions in .env to pin.
# ======================================================================
ARG NIX_VERSION=latest
ARG CODE_SERVER_VERSION=latest
ARG OPENCODE_VERSION=latest

# ======================================================================
# Stage 1 — Dev environment
# ======================================================================
FROM debian:bookworm-slim AS dev-env

ARG NIX_VERSION
ARG CODE_SERVER_VERSION
ARG OPENCODE_VERSION

# ── System packages ──
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    bzip2 \
    ca-certificates \
    curl \
    nano \
    git \
    gnupg \
    openssh-client \
    python3 \
    python3-pip \
    sudo \
    unzip \
    xz-utils \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://raw.githubusercontent.com/ncopa/su-exec/master/su-exec.c \
       -o /tmp/su-exec.c \
    && gcc -o /usr/local/bin/su-exec /tmp/su-exec.c \
    && rm /tmp/su-exec.c

# ── Docker CLI (talks to host socket) ──
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# ── code-server ──
RUN if [ "$CODE_SERVER_VERSION" = "latest" ]; then \
        curl -fsSL https://code-server.dev/install.sh | sh; \
    else \
        curl -fsSL https://code-server.dev/install.sh | sh -s -- --version "$CODE_SERVER_VERSION"; \
    fi \
    && ln -s /usr/lib/code-server/bin/code-server /usr/local/bin/code-server

# ── mise (polyglot tool version manager) ──
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

# ── Nix package manager — store at /nix, persisted via bind mount ──
RUN groupadd -r nixbld \
    && for i in $(seq 1 30); do \
         useradd -r -M -d /var/empty -s /sbin/nologin -G nixbld -u $((30000 + i)) nixbld$i; \
       done \
    && mkdir -m 0755 /etc/nix \
    && echo 'sandbox = false' > /etc/nix/nix.conf \
    && echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf \
    && mkdir -m 0755 /nix \
    && if [ "$NIX_VERSION" = "latest" ]; then \
         curl -fsSL https://nixos.org/nix/install -o /tmp/nix-install.sh \
         && USER=root bash /tmp/nix-install.sh --no-daemon --no-modify-profile \
         && rm /tmp/nix-install.sh; \
       else \
         curl -fsSL https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-$(uname -m)-linux.tar.xz -o /tmp/nix.tar.xz \
         && tar xf /tmp/nix.tar.xz \
         && USER=root sh nix-${NIX_VERSION}-$(uname -m)-linux/install --no-modify-profile \
         && rm -rf /tmp/nix.tar.xz nix-${NIX_VERSION}-$(uname -m)-linux; \
       fi \
    && ln -s /nix/var/nix/profiles/default/etc/profile.d/nix.sh /etc/profile.d/nix.sh \
    && /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-old \
    && /nix/var/nix/profiles/default/bin/nix-store --optimise \
    && /nix/var/nix/profiles/default/bin/nix-store --verify --check-contents \
    && cp -a /nix /opt/nix-backup

# ── opencode (AI coding agent) ──
RUN if [ "$OPENCODE_VERSION" = "latest" ]; then \
        curl -fsSL https://opencode.ai/install | bash; \
    else \
        curl -fsSL https://opencode.ai/install | bash -s -- --version "$OPENCODE_VERSION"; \
    fi \
    && cp /root/.opencode/bin/opencode /usr/local/bin/opencode

# ── Entrypoint ──
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 8443 3000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["code-server", "--disable-telemetry"]
