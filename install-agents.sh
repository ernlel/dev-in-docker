#!/bin/bash
set -uo pipefail

if [ -z "${AIONUI_CLI_AGENTS:-}" ]; then
    exit 0
fi

for agent in $(echo "$AIONUI_CLI_AGENTS" | tr ',' ' '); do
    case "$agent" in
        claude)     npm install -g @anthropic-ai/claude-code ;;
        codex)      npm install -g @openai/codex ;;
copilot)    npm install -g @github/copilot || true ;;
opencode)   npm install -g opencode-ai || true ;;
pi)         npm install -g @earendil-works/pi-coding-agent || true ;;
kilo)       npm install -g @kilocode/cli || true ;;
gemini)     npm install -g @google/gemini-cli || true ;;
qwen)       curl -fsSL https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.sh | bash || true ;;
augment)    npm install -g @augmentcode/auggie || true ;;
codebuddy)  npm install -g @tencent-ai/codebuddy-code || true ;;
kimi)       curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash || true
            if [ -f "$HOME/.kimi-code/bin/kimi" ] && [ ! -f "$HOME/.local/bin/kimi" ]; then
                ln -sf "$HOME/.kimi-code/bin/kimi" "$HOME/.local/bin/kimi"
            fi ;;
factory)    curl -fsSL https://app.factory.ai/cli | sh || true ;;
qoder)      curl -fsSL https://qoder.com/install | bash || true ;;
mistral-vibe) curl -LsSf https://mistral.ai/vibe/install.sh | bash || true ;;
snow)       npm install -g snow-ai || true ;;
hermes)     curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash || true ;;
cursor-agent) npm install -g @cursor/cli || true ;;
kiro)       curl -fsSL https://cli.kiro.dev/install | bash || true
            if [ -f "$HOME/.local/bin/kiro-cli" ] && [ ! -f "$HOME/.local/bin/kiro" ]; then
                ln -sf kiro-cli "$HOME/.local/bin/kiro"
            fi ;;
openclaw)   npm install -g openclaw@latest || true ;;
nanobot)    pip install nanobot-ai || true ;;
iflow)      npm install -g @iflow-ai/iflow-cli || true ;;
grok)       curl -fsSL https://x.ai/cli/install.sh | bash || true ;;
        goose)      mkdir -p "$HOME/.local/bin" || true && \
                    curl -fsSL -o /tmp/goose.tar.bz2 \
                      "https://github.com/aaif-goose/goose/releases/download/stable/goose-x86_64-unknown-linux-gnu.tar.bz2" \
                    && tar -xjf /tmp/goose.tar.bz2 -C "$HOME/.local/bin/" \
                    && rm /tmp/goose.tar.bz2 || true ;;
        *)          echo "Warning: unknown agent '$agent', skipping" ;;
    esac
done
exit 0
