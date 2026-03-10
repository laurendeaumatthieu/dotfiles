#!/bin/bash

echo "Starting dotfiles installation..."

# Ensure ~/.local/bin is in PATH for this script session
export PATH="$HOME/.local/bin:$PATH"

# ==========================
# Core Installation
# ==========================

echo "Checking core dependencies (Zsh, Tmux, Git, Curl, xclip)..."
for pkg in zsh tmux git curl xclip; do
    # Check if package is in PATH or in common local installation directories
    if ! command -v $pkg &> /dev/null && [ ! -f "$HOME/.local/bin/$pkg" ]; then
        echo " -> $pkg is missing."
        
        # Check sudo privileges
        if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
            echo "    Attempting to install $pkg via sudo..."
            # Try apt (Debian/Ubuntu) or dnf/yum (RHEL/CentOS)
            if command -v apt-get &> /dev/null; then
                sudo apt update && sudo apt install -y "$pkg"
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y "$pkg"
            elif command -v yum &> /dev/null; then
                sudo yum install -y "$pkg"
            fi
        else
            echo "    No sudo rights detected for $pkg."
            
            # Ask the user for confirmation to install locally
            read -p "    Do you want to attempt a local (non-root) installation for $pkg? (y/n) " -n 1 -r
            echo " "
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                case $pkg in
                    xclip)
                        echo "    Attempting to install xclip locally in ~/.local/bin..."
                        mkdir -p "$HOME/.local/bin" "$HOME/xclip_tmp"
                        cd "$HOME/xclip_tmp" || exit
                        
                        # Detect OS and extract accordingly
                        if command -v apt-get &> /dev/null; then
                            echo "    Detected Debian/Ubuntu system..."
                            apt-get download xclip 2>/dev/null
                            if ls *.deb 1> /dev/null 2>&1; then
                                dpkg -x *.deb .
                                mv usr/bin/xclip "$HOME/.local/bin/"
                                echo "    xclip successfully installed to ~/.local/bin/"
                            fi
                        elif command -v dnf &> /dev/null || command -v yumdownloader &> /dev/null; then
                            echo "    Detected RHEL/CentOS/Fedora system..."
                            if command -v dnf &> /dev/null; then
                                dnf download xclip 2>/dev/null
                            else
                                yumdownloader xclip 2>/dev/null
                            fi
                            if ls *.rpm 1> /dev/null 2>&1; then
                                rpm2cpio *.rpm | cpio -idmv
                                mv usr/bin/xclip "$HOME/.local/bin/"
                                echo "    xclip successfully installed to ~/.local/bin/"
                            fi
                        else
                            echo "    WARNING: Unknown package manager. Cannot download xclip automatically."
                        fi
                        cd "$HOME" || exit
                        rm -rf "$HOME/xclip_tmp"
                        ;;
                    zsh)
                        echo "    Attempting to install Zsh locally using zsh-bin..."
                        sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/master/install)"
                        ;;
                    *)
                        echo "    ====================================================="
                        echo "    ERROR: Automated local installation for '$pkg' is not supported."
                        echo "    Please ask your server admin to install it."
                        echo "    ====================================================="
                        exit 1
                        ;;
                esac
            else
                echo "    Skipping local installation for $pkg."
                if [[ "$pkg" == "zsh" || "$pkg" == "tmux" ]]; then
                    echo "    Fatal error: $pkg is strictly required for this setup. Exiting."
                    exit 1
                fi
            fi
        fi
    else
        echo " -> $pkg is already installed."
    fi
done

# Install Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    KEEP_ZSHRC=yes RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install Powerlevel10k
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
    echo "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
fi

# Install Zoxide
if ! command -v zoxide &> /dev/null; then
    echo "Installing Zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
fi

# Install FZF
if [ ! -d "$HOME/.fzf" ]; then
    echo "Installing FZF..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
fi

# Install Zsh Plugins
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
fi

if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
fi

# Add xclip cleanup to .zlogout to help ssh disconnections
if ! grep -q "killall xclip 2>/dev/null" "$HOME/.zlogout" 2>/dev/null; then
    echo 'killall xclip 2>/dev/null' >> "$HOME/.zlogout"
fi

# ==========================
# Create Symlinks
# ==========================
echo "Creating symlinks..."

# Zsh symlink (backs up old .zshrc if it exists)
if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    mv "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi
ln -sf "$HOME/dotfiles/zsh/.zshrc" "$HOME/.zshrc"

# Tmux symlink
TMUX_VERSION=$(tmux -V | awk '{print $2}' | sed 's/[^0-9.]*//g') # extract the version number
if awk "BEGIN {exit !($TMUX_VERSION >= 3.1)}"; then
    mkdir -p "$HOME/.config/tmux"
    ln -sf "$HOME/dotfiles/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
else
    ln -sf "$HOME/dotfiles/tmux/tmux.conf" "$HOME/.tmux.conf"
fi

# Change default shell to Zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "Changing default shell to zsh..."
    chsh -s $(which zsh) $(whoami)
fi

echo "Installation complete! Please restart your terminal."