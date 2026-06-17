# ======================================================================
#  Version overrides — pass via --build-arg or docker-compose build.args
# ======================================================================
ARG NODE_VERSION=20
ARG AIONUI_REPO=https://github.com/iOfficeAI/AionUi.git
ARG AIONUI_TAG=v2.1.9
ARG AIONCORE_VERSION=v0.1.29
ARG CODE_SERVER_VERSION=4.96.4

# ======================================================================
# Stage 1 — Build AionUI web renderer
# ======================================================================
FROM node:${NODE_VERSION}-slim AS aionui-builder

ARG AIONUI_REPO
ARG AIONUI_TAG
ARG AIONCORE_VERSION

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl bzip2 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "$AIONUI_TAG" "$AIONUI_REPO" .

RUN npm install -g bun \
    && bun install --ignore-scripts \
    && bun install

RUN bun run package

RUN curl -fsSL -o /tmp/aioncore.tar.gz \
    "https://github.com/iOfficeAI/AionCore/releases/download/${AIONCORE_VERSION}/aioncore-${AIONCORE_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    && mkdir -p resources/bundled-aioncore/linux-x64 \
    && tar -xzf /tmp/aioncore.tar.gz -C resources/bundled-aioncore/linux-x64/ \
    && chmod +x resources/bundled-aioncore/linux-x64/aioncore

# ======================================================================
# Stage 2 — Dev environment base
# ======================================================================
FROM debian:bookworm-slim AS dev-env

ARG CODE_SERVER_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    bzip2 \
    ca-certificates \
    curl \
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

# ── Bun runtime (for AionUI) — install globally, not under /root/
RUN curl -fsSL https://bun.sh/install | bash \
    && cp /root/.bun/bin/bun /usr/local/bin/bun \
    && chmod 755 /usr/local/bin/bun

# ── code-server ──
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version "$CODE_SERVER_VERSION" \
    && ln -s /usr/lib/code-server/bin/code-server /usr/local/bin/code-server

# ── mise (polyglot tool version manager) ──
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

# ── AionUI web artifacts from builder ──
WORKDIR /app/aionui
COPY --from=aionui-builder /app/out          /app/aionui/out
COPY --from=aionui-builder /app/scripts      /app/aionui/scripts
COPY --from=aionui-builder /app/packages     /app/aionui/packages
COPY --from=aionui-builder /app/package.json /app/aionui/
COPY --from=aionui-builder /app/bun.lock     /app/aionui/
COPY --from=aionui-builder /app/patches      /app/aionui/patches
COPY --from=aionui-builder /app/resources    /app/aionui/resources
COPY --from=aionui-builder /app/node_modules /app/aionui/node_modules

# ── AionUI node modules + bun from builder ──
COPY --from=aionui-builder /usr/local/bin/bun /usr/local/bin/bun
COPY --from=aionui-builder /usr/local/lib/node_modules /usr/local/lib/node_modules

# ── Homebrew (Linuxbrew) — portable tarball, user-copied at runtime ──
RUN curl -fsSL https://github.com/Homebrew/brew/tarball/master -o /tmp/brew.tar.gz \
    && mkdir -p /opt/linuxbrew \
    && tar xzf /tmp/brew.tar.gz --strip-components 1 -C /opt/linuxbrew \
    && rm /tmp/brew.tar.gz

# ── Entrypoint & Post-install ──
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
COPY post-install.sh /app/post-install.sh
RUN chmod +x /app/post-install.sh

WORKDIR /workspace
EXPOSE 8443 3000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["code-server", "--disable-telemetry"]
