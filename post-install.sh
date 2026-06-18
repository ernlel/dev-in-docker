#!/bin/bash
set -u
set -o pipefail

source /etc/profile.d/mise.sh

# Activate Nix profile
if [ -f /etc/profile.d/nix.sh ]; then
    . /etc/profile.d/nix.sh
fi

echo ">>> Post-install: installing CLI agents …"

nix profile install nixpkgs#opencode
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
npm install -g @google/gemini-cli
npm install -g @qwen-code/qwen-code@latest
nix profile install nixpkgs#uv
uv tool install --python 3.13 kimi-cli
npm install -g @github/copilot
nix profile install nixpkgs#fresh-editor

echo ">>> Done. Run each tool with --help to verify."
