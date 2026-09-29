#!/bin/bash
# Non-root installer: every tool lands in $HOME (~/.local/bin, ~/.pixi, ~/.oh-my-zsh).
# Safe to re-run: each step is skipped when already done.

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
LOCAL_ENV="$HOME/.config/dotfiles/env.zsh"
VAULT_REPO="git@github.com:laurendeaumatthieu/claude-vault.git"
export PATH="$HOME/.local/bin:$HOME/.pixi/bin:$PATH"

echo "Starting dotfiles installation from $DOTFILES..."

if ! command -v curl &> /dev/null; then
    echo "ERROR: curl is required to download the other tools."
    exit 1
fi

# ==========================
# Workspace (machine-specific, not versioned)
# ==========================
if [ ! -f "$LOCAL_ENV" ]; then
    read -rp "Workspace directory (projects, data) [$HOME]: " ws
    ws="${ws:-$HOME}"; ws="${ws/#\~/$HOME}"
    read -rp "Temporary directory for all applications (empty = system default): " tmp
    tmp="${tmp/#\~/$HOME}"
    mkdir -p "$ws" "$(dirname "$LOCAL_ENV")"
    echo "export WORKSPACE=\"$ws\"" > "$LOCAL_ENV"
    if [ -n "$tmp" ]; then
        mkdir -p "$tmp" && chmod 700 "$tmp"
        echo "export TMPDIR=\"$tmp\"" >> "$LOCAL_ENV"
    fi
fi
echo "Machine settings ($LOCAL_ENV, delete it to reconfigure):"
sed 's/^/    /' "$LOCAL_ENV"

# ==========================
# CLI tools (pixi installs missing ones from conda-forge, no root needed)
# ==========================
missing=()
for tool in zsh git tmux tree btop fzf zoxide; do
    command -v "$tool" &> /dev/null || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Installing via pixi: ${missing[*]}"
    if ! command -v pixi &> /dev/null; then
        curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash
    fi
    pixi global install "${missing[@]}"
fi

# Claude Code and herdr (both install into ~/.local/bin)
if ! command -v claude &> /dev/null; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi
if ! command -v herdr &> /dev/null; then
    echo "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
fi
herdr integration install claude

# ==========================
# Oh My Zsh and plugins
# ==========================
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    KEEP_ZSHRC=yes RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    echo "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Add xclip cleanup to .zlogout to help ssh disconnections
if ! grep -q "killall xclip 2>/dev/null" "$HOME/.zlogout" 2>/dev/null; then
    echo 'killall xclip 2>/dev/null' >> "$HOME/.zlogout"
fi

# ==========================
# Claude vault (global CLAUDE.md + project memory)
# ==========================
if [ ! -d "$HOME/claude-vault" ]; then
    echo "Cloning claude-vault..."
    git clone "$VAULT_REPO" "$HOME/claude-vault" \
        || echo "WARNING: vault clone failed (SSH key not registered on GitHub?). Re-run after fixing it."
fi
if [ -f "$HOME/claude-vault/CLAUDE.md" ]; then
    mkdir -p "$HOME/.claude"
    ln -sf "$HOME/claude-vault/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi

# ==========================
# Create Symlinks
# ==========================
echo "Creating symlinks..."

# Zsh symlink (backs up old .zshrc if it exists)
if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    mv "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi
ln -sf "$DOTFILES/zsh/.zshrc" "$HOME/.zshrc"

# Link the aliases file
ln -sf "$DOTFILES/zsh/aliases.zsh" "$ZSH_CUSTOM/aliases.zsh"

# Tmux symlink
TMUX_VERSION=$(tmux -V | awk '{print $2}' | sed 's/[^0-9.]*//g') # extract the version number
if awk "BEGIN {exit !($TMUX_VERSION >= 3.1)}"; then
    mkdir -p "$HOME/.config/tmux"
    ln -sf "$DOTFILES/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
else
    ln -sf "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
fi

# ==========================
# Default shell
# ==========================
# chsh needs zsh listed in /etc/shells (root-owned); otherwise bash execs zsh at login
ZSH_BIN="$(command -v zsh)"
if [ "$SHELL" != "$ZSH_BIN" ]; then
    if ! { grep -qx "$ZSH_BIN" /etc/shells && chsh -s "$ZSH_BIN"; }; then
        if ! grep -q ">>> dotfiles zsh >>>" "$HOME/.bashrc" 2>/dev/null; then
            echo "chsh unavailable: bash will exec zsh from ~/.bashrc."
            cat >> "$HOME/.bashrc" << 'EOF'
# >>> dotfiles zsh >>>
export PATH="$HOME/.local/bin:$HOME/.pixi/bin:$PATH"
if [[ $- == *i* ]] && [[ "$SHELL" != */zsh ]] && command -v zsh &> /dev/null; then
    export SHELL="$(command -v zsh)"
    exec zsh -l
fi
# <<< dotfiles zsh <<<
EOF
        fi
    fi
fi

echo "Installation complete! Please restart your terminal."
