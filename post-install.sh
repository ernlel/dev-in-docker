#!/bin/bash
set -euo pipefail

echo ">>> Post-install: installing CLI agents …"

brew install anomalyco/tap/opencode
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
npm install -g @google/gemini-cli
npm install -g @qwen-code/qwen-code@latest
brew install uv
uv tool install --python 3.13 kimi-cli
npm install -g @github/copilot

echo ">>> Done. Run each tool with --help to verify."
