#!/bin/bash

echo "Starting dotfiles installation..."

# ==========================
# Core Installation
# ==========================

# Install core dependencies
echo "Installing Zsh, Tmux, Git, and Curl..."
for pkg in zsh tmux git curl; do
    if ! command -v $pkg &> /dev/null; then
        echo " -> $pkg is missing."
        
        # Check sudo privileges
        if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
            echo "    Attempting to install $pkg via sudo..."
            sudo apt update && sudo apt install -y "$pkg"
        else
            echo "====================================================="
            echo " ERROR: '$pkg' is missing and '$USER' does not have sudo rights."
            echo " Please ask the server admin to install it, or install it locally in ~/.local/bin directory."
            echo "====================================================="
            exit 1
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
mkdir -p "$HOME/.config/tmux"
ln -sf "$HOME/dotfiles/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"

# Change default shell to Zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "Changing default shell to zsh..."
    chsh -s $(which zsh) $(whoami)
fi

echo "Installation complete! Please restart your terminal."