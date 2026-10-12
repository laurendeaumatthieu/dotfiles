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
# Removes FortiClient IPsec leftovers (VPN IP, DNS, routes) that an abrupt disconnect
# leaves in the active wifi/ethernet profiles; they make the next VPN connect hang.
# Also releases ethernet ports without carrier: FortiClient keeps binding IKE to their
# stale address. Refuses to run while the VPN works (its live settings use the same fields).
forti-reset() {
    local uuid dev name found=0
    timeout 2 bash -c '</dev/tcp/10.33.35.35/445' 2>/dev/null \
        && { echo "VPN is up (10.33.35.35 reachable): nothing to reset."; return 1; }
    for dev in /sys/class/net/en*(N); do
        [[ "$(cat $dev/carrier 2>/dev/null)" == 1 ]] && continue
        ip -4 -br addr show ${dev:t} | grep -q '[0-9]\.' || continue
        nmcli dev disconnect ${dev:t} >/dev/null && echo "Released ${dev:t} (no link)" && found=1
    done
    while IFS=: read -r uuid dev; do
        name=$(nmcli -g connection.id con show "$uuid")
        [[ "$(nmcli -g ipv4.addresses,ipv4.dns con show "$uuid")" == *10.33.* ]] || continue
        found=1
        nmcli con mod "$uuid" ipv4.addresses '' ipv4.dns '' ipv4.ignore-auto-dns no \
            ipv4.routes '' ipv4.ignore-auto-routes no ipv6.ignore-auto-routes no \
            && nmcli dev reapply "$dev" >/dev/null && echo "Cleaned $name ($dev)"
    done < <(nmcli -t -f UUID,TYPE,DEVICE con show --active | awk -F: '$2 ~ /wireless|ethernet/ {print $1":"$3}')
    (( found )) || echo "No FortiClient leftovers found."
}
