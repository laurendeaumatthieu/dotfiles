# Searches upward for a venv and activates it.
find_and_source_venv() {
    local current_dir="$PWD"
    
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/venv/bin/activate" ]]; then
            source "$current_dir/venv/bin/activate"
            echo "Activated: $current_dir/venv"
            return 0
        fi
        current_dir=$(dirname "$current_dir")
    done

    echo "No venv found in current or parent directories."
    return 1
}

alias sv='find_and_source_venv'