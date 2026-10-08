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
    local -a tmps=(/tmp) targets
    [[ -n "$TMPDIR" && "${TMPDIR%/}" != /tmp ]] && tmps+=("${TMPDIR%/}")
    targets=("$cache" ${tmps[@]} $HOME/.var/app/*/cache(N))
    local before=$(du -sck $targets 2>/dev/null | tail -1 | cut -f1)

    find "$cache" -mindepth 1 -maxdepth 1 ! -name claude-vault ! -name dotfiles -exec rm -rf {} +
    for t in $tmps; do
        find "$t" -mindepth 1 -maxdepth 1 -user "$USER" -mtime +0 -exec rm -rf {} + 2>/dev/null
    done
    for t in $HOME/.var/app/*/cache(N); do rm -rf "$t"/*(DN); done

    local after=$(du -sck $targets 2>/dev/null | tail -1 | cut -f1)
    echo "Freed $(( (before - after) / 1024 )) MB"
}