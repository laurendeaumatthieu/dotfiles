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
# Profile and workspace (machine-specific, not versioned)
# ==========================
# Values come from $LOCAL_ENV only, not from the calling shell
unset DOTFILES_PROFILE WORKSPACE
[ -f "$LOCAL_ENV" ] && source "$LOCAL_ENV"
if [ -z "$DOTFILES_PROFILE" ]; then
    # Graphical session without SSH -> desktop (folders, Dolphin, backup); else server (CLI only)
    default=server
    [ -z "$SSH_CONNECTION" ] && [ -n "$DISPLAY$WAYLAND_DISPLAY" ] && default=desktop
    read -rp "Profile: desktop or server [$default]: " DOTFILES_PROFILE
    DOTFILES_PROFILE="${DOTFILES_PROFILE:-$default}"
    mkdir -p "$(dirname "$LOCAL_ENV")"
    echo "export DOTFILES_PROFILE=\"$DOTFILES_PROFILE\"" >> "$LOCAL_ENV"
fi
if [ -z "$WORKSPACE" ]; then
    read -rp "Workspace directory (git repos) [$HOME/work]: " ws
    ws="${ws:-$HOME/work}"; ws="${ws/#\~/$HOME}"
    read -rp "Directory for tmp/cache/state of all applications (empty = /tmp, ~/.cache, ~/.local/state): " scratch
    scratch="${scratch/#\~/$HOME}"
    mkdir -p "$ws" "$(dirname "$LOCAL_ENV")"
    echo "export WORKSPACE=\"$ws\"" >> "$LOCAL_ENV"
    if [ -n "$scratch" ]; then
        mkdir -p "$scratch"/{tmp,cache,state} && chmod 700 "$scratch"
        # pip, uv, HuggingFace, torch, pixi... all follow XDG_CACHE_HOME
        cat >> "$LOCAL_ENV" << EOF
export TMPDIR="$scratch/tmp"
export XDG_CACHE_HOME="$scratch/cache"
export XDG_STATE_HOME="$scratch/state"
EOF
    fi
fi
echo "Machine settings ($LOCAL_ENV, delete it to reconfigure):"
sed 's/^/    /' "$LOCAL_ENV"
source "$LOCAL_ENV"

# ~/share: one symlink per network disk mounted under /mnt (autofs, cifs, nfs)
for mnt in $(findmnt -rn -t autofs,cifs,nfs,nfs4 -o TARGET | grep '^/mnt/' | sort -u); do
    mkdir -p "$HOME/share"
    link="$HOME/share/$(basename "$mnt")"
    # Remove then recreate: some ln implementations ignore -n and would write inside the mount
    [ -L "$link" ] && rm "$link"
    [ -e "$link" ] || ln -s "$mnt" "$link"
done

# ==========================
# CLI tools (pixi installs missing ones from conda-forge, no root needed)
# ==========================
missing=()
for tool in zsh git tmux tree btop fzf zoxide gh; do
    command -v "$tool" &> /dev/null || missing+=("$tool")
done
# Real rg binary needed by rtk (Claude Code's rg is only a shell function)
command -v rg &> /dev/null || missing+=(ripgrep)
if [ ${#missing[@]} -gt 0 ]; then
    echo "Installing via pixi: ${missing[*]}"
    if ! command -v pixi &> /dev/null; then
        curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash
    fi
    pixi global install "${missing[@]}"
fi

# Claude Code, herdr and rtk (all install into ~/.local/bin)
if ! command -v claude &> /dev/null; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi
if ! command -v herdr &> /dev/null; then
    echo "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
fi
herdr integration install claude
if ! command -v rtk &> /dev/null; then
    echo "Installing rtk..."
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
fi
# Hook only: no RTK.md, and ~/.claude/CLAUDE.md (symlink into the vault) stays untouched
"$HOME/.local/bin/rtk" init -g --hook-only --auto-patch

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
# Claude Code settings
# ==========================
# Merge shared keys into the local file (3-way, see the script); also run at every
# Claude session start by the claude-vault hook, so install.sh is needed only once.
python3 "$DOTFILES/claude/merge-settings.py"

# ==========================
# GitHub repositories (login first: it can also register the SSH key used below)
# ==========================
# SSH to GitHub over port 443: works wherever HTTPS does (port 22 is often blocked)
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if ! grep -q "Hostname ssh.github.com" "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" << 'EOF'

Host github.com
    Hostname ssh.github.com
    Port 443
    User git
EOF
    chmod 600 "$HOME/.ssh/config"
fi
# Trust GitHub host keys fetched over HTTPS, so non-interactive git (scripts, Claude) never prompts
if ! ssh-keygen -F "[ssh.github.com]:443" -f "$HOME/.ssh/known_hosts" &> /dev/null; then
    curl -fsSL https://api.github.com/meta \
        | python3 -c 'import json, sys; [print("[ssh.github.com]:443", k) for k in json.load(sys.stdin)["ssh_keys"]]' \
        >> "$HOME/.ssh/known_hosts"
fi

read -rp "Clone GitHub repositories into $WORKSPACE now? (later: clone-repos.sh) [y/N]: " ans
[[ "$ans" =~ ^[yY] ]] && bash "$DOTFILES/clone-repos.sh"

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

# VS Code config and extensions (only where the `code` CLI exists)
if command -v code &> /dev/null; then
    bash "$DOTFILES/vscode/install.sh"
fi

# ==========================
# Desktop profile: home folders, Dolphin places, restic backup
# ==========================
if [ "$DOTFILES_PROFILE" = desktop ]; then
    mkdir -p "$HOME"/{desktop,downloads,images,screenshots,apps}
    if command -v xdg-user-dirs-update &> /dev/null; then
        xdg-user-dirs-update --set DESKTOP "$HOME/desktop"
        xdg-user-dirs-update --set DOWNLOAD "$HOME/downloads"
        xdg-user-dirs-update --set PICTURES "$HOME/images"
    fi
    # GNOME saves screenshots into <pictures>/Screenshots
    ln -sfn ../screenshots "$HOME/images/Screenshots"

    # Dolphin places: template only on a fresh machine (the file also holds per-machine devices)
    PLACES="$HOME/.local/share/user-places.xbel"
    if [ ! -f "$PLACES" ]; then
        mkdir -p "$(dirname "$PLACES")"
        sed "s#@HOME@#$HOME#g" "$DOTFILES/desktop/user-places.xbel" > "$PLACES"
    fi

    # restic: repository asked once (several machines can share one), password never versioned
    RESTIC_DIR="$HOME/.config/restic"
    if [ ! -f "$RESTIC_DIR/env" ]; then
        read -rp "restic repository for the daily home backup (e.g. /mnt/<share>/restic, empty = none): " repo
        if [ -n "$repo" ]; then
            mkdir -p "$RESTIC_DIR" && chmod 700 "$RESTIC_DIR"
            echo "RESTIC_REPOSITORY=$repo" > "$RESTIC_DIR/env"
        fi
    fi
    if [ -f "$RESTIC_DIR/env" ]; then
        command -v restic &> /dev/null || pixi global install restic
        if [ ! -f "$RESTIC_DIR/password" ]; then
            read -rsp "restic password (from the password manager; new repository: choose one): " pw; echo
            (umask 077; printf '%s\n' "$pw" > "$RESTIC_DIR/password")
        fi
        (
            set -a; source "$RESTIC_DIR/env"; set +a
            export RESTIC_PASSWORD_FILE="$RESTIC_DIR/password" GODEBUG=asyncpreemptoff=1
            restic cat config &> /dev/null || restic init
        )
        mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
        ln -sf "$DOTFILES/backup/backup-home" "$HOME/.local/bin/backup-home"
        ln -sf "$DOTFILES/backup/backup-home.service" "$DOTFILES/backup/backup-home.timer" "$HOME/.config/systemd/user/"
        systemctl --user daemon-reload
        systemctl --user enable --now backup-home.timer
    fi
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
