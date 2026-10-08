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

# Empties user caches and temp files. Keeps vault/dotfiles state in the cache and
# temp entries touched in the last 24h (live sockets of tmux, herdr, VS Code, Claude).
purge() {
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}" t
    local -a tmps=(/tmp) items
    [[ -n "$TMPDIR" && "${TMPDIR%/}" != /tmp ]] && tmps+=("${TMPDIR%/}")

    items=(${(0)"$(find "$cache" -mindepth 1 -maxdepth 1 ! -name claude-vault ! -name dotfiles -print0)"})
    for t in $tmps; do
        items+=(${(0)"$(find "$t" -mindepth 1 -maxdepth 1 -user "$USER" -mtime +0 -print0 2>/dev/null)"})
    done
    items+=($HOME/.var/app/*/cache/*(DN))
    (( $#items )) || { echo "Nothing to purge."; return 0; }

    local size=$(du -sch $items 2>/dev/null | tail -1 | cut -f1)
    read -q "?Delete $#items items ($size)? [y/N] " || { echo; return 1; }
    echo
    rm -rf $items 2>/dev/null
    echo "Freed $size"
}