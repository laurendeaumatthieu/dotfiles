# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:/opt/nvim-linux-x86_64/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load (https://github.com/ohmyzsh/ohmyzsh/wiki/Themes)
ZSH_THEME="powerlevel10k/powerlevel10k"

# Use hyphen-insensitive completion: _ and - will be interchangeable.
HYPHEN_INSENSITIVE="true"

# Time stamp format
HIST_STAMPS="yyyy-mm-dd"

# Auto activate python venv environment when cd into it. Need plugin python
export PYTHON_AUTO_VRUN=true

# Plugins loaded
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
plugins=(zoxide
	 fzf zsh-interactive-cd
	 zsh-autosuggestions
	 zsh-syntax-highlighting
	 python
	 git
	 docker
	 dirhistory
	 extract
	 command-not-found
	 web-search
	 )

source $ZSH/oh-my-zsh.sh

# User configuration

# Users are encouraged to define aliases in $ZSH_CUSTOM/aliases.zsh
# For a full list of active aliases, run `alias`.

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


# Custom commands

# Add venv as ipykernel
add_venv_kernel() {
    # Check if a virtual environment is currently active
    if [ -z "$VIRTUAL_ENV" ]; then
        echo "Error: No virtual environment activated."
        echo "Please run 'source path/to/venv/bin/activate' first."
        return 1
    fi

    # Check if the user provided a name for the kernel
    if [ -z "$1" ]; then
        echo "Usage: add_venv_kernel <kernel-name>"
        echo "Example: add_venv_kernel my_data_project"
        return 1
    fi

    KERNEL_NAME=$1

    echo "Installing ipykernel in the active virtual environment..."
    pip install ipykernel

    echo "egistering the kernel with Jupyter..."
    python -m ipykernel install --user --name="$KERNEL_NAME" --display-name="$KERNEL_NAME"

    echo "Success! When you open Jupyter Notebook, look for the '$KERNEL_NAME' kernel."
}

# Use zoxide with cd command (must stay at the end of the file)
# Silence the doctor warning in non-interactive shells (e.g. Claude Code snapshots)
export _ZO_DOCTOR=0
eval "$(zoxide init zsh --cmd cd)"
