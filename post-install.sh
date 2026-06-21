#!/bin/bash
set -u
set -o pipefail

source /etc/profile.d/mise.sh

# Activate Nix profile
if [ -f /etc/profile.d/nix.sh ]; then
    . /etc/profile.d/nix.sh
fi
# nix profile add installs to ~/.nix-profile/bin — ensure it's in PATH
export PATH="$HOME/.nix-profile/bin:$PATH"

echo ">>> Post-install: installing CLI agents …"

nix profile add nixpkgs#uv
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
npm install -g @google/gemini-cli
npm install -g @qwen-code/qwen-code@latest
uv tool install --python 3.13 kimi-cli
npm install -g @github/copilot
nix profile add nixpkgs#fresh-editor

echo ">>> Done. Run each tool with --help to verify."
