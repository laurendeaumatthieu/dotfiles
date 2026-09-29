#!/usr/bin/env bash
set -e

DOTFILES_VSCODE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect OS configuration path
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  TARGET_DIR="$HOME/.config/Code/User"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  TARGET_DIR="$HOME/Library/Application Support/Code/User"
else
  echo "Unsupported OS for automatic symlinking."
  exit 1
fi

# Over SSH (Remote-SSH terminal), settings come from the client: only install extensions
if [ -z "$SSH_CONNECTION" ]; then
  mkdir -p "$TARGET_DIR"

  # Link configuration files (existing real files are backed up once)
  echo "Linking VS Code configuration files..."
  for item in settings.json keybindings.json snippets; do
    target="$TARGET_DIR/$item"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      mv "$target" "$target.backup"
    fi
    ln -sfn "$DOTFILES_VSCODE/$item" "$target"
  done

  # MesloLGS NF font used by Powerlevel10k and the integrated terminal
  FONT_DIR="$HOME/.local/share/fonts"
  if ! fc-list 2>/dev/null | grep -q "MesloLGS NF"; then
    echo "Installing MesloLGS NF font..."
    mkdir -p "$FONT_DIR"
    for style in Regular Bold Italic "Bold Italic"; do
      curl -fsSL -o "$FONT_DIR/MesloLGS NF $style.ttf" \
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${style// /%20}.ttf"
    done
    fc-cache -f "$FONT_DIR" 2>/dev/null || true
  fi
fi

# Install extensions
if command -v code &>/dev/null; then
  echo "Installing VS Code extensions..."
  while IFS= read -r ext || [[ -n "$ext" ]]; do
    [[ -z "$ext" || "$ext" =~ ^# ]] && continue
    code --install-extension "$ext" --force
  done < "$DOTFILES_VSCODE/extensions.txt"
else
  echo "Warning: 'code' CLI not found. Extensions were not installed."
fi

echo "VS Code configuration deployed successfully."
