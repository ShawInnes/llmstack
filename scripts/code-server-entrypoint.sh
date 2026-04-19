#!/bin/bash
# Custom entrypoint for code-server: installs Claude Code CLI + VS Code extension on first boot.
# Idempotent — skips installation if already present (persisted in codeserver_data volume).
set -e

echo "=== code-server entrypoint ==="

# Install Node.js + npm via NodeSource if not present
# Note: /usr/bin is not persisted in the volume — runs on every fresh container.
# Claude CLI install is idempotent via the claude command check below.
if ! command -v npm &>/dev/null; then
  echo "Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y nodejs
  echo "Node.js installed: $(node --version), npm: $(npm --version)"
fi

# Ensure home dirs exist and are owned by coder (volume mount can create them as root)
sudo mkdir -p \
  "$HOME/.local/bin" \
  "$HOME/.local/state" \
  "$HOME/.local/share/code-server/User" \
  "$HOME/.config/code-server"
sudo chown -R "$(id -u):$(id -g)" "$HOME/.local" "$HOME/.config"

# Inject configs from /etc/code-server (mounted outside the named volume)
cp /etc/code-server/config.yaml "$HOME/.config/code-server/config.yaml"
# Copy settings only if not already customised by the user
if [ ! -f "$HOME/.local/share/code-server/User/settings.json" ]; then
  cp /etc/code-server/settings.json "$HOME/.local/share/code-server/User/settings.json"
fi

# Install Claude Code CLI (idempotent)
# install.sh puts claude in ~/.local/bin — add to PATH for this session
export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude &>/dev/null; then
  echo "Installing Claude Code CLI..."
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
else
  echo "Claude Code CLI already installed: $(claude --version 2>/dev/null || echo 'unknown')"
fi

# Install Claude Code VS Code extension (idempotent)
EXT_DIR="$HOME/.local/share/code-server/extensions"
if ! ls "$EXT_DIR"/anthropic.claude-code-* &>/dev/null 2>&1; then
  echo "Installing Claude Code VS Code extension..."
  code-server --install-extension anthropic.claude-code
else
  echo "Claude Code extension already installed"
fi

echo "=== handing off to code-server ==="

# Hand off to the default entrypoint
exec /usr/bin/entrypoint.sh --bind-addr 0.0.0.0:8080 .
