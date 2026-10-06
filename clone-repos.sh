#!/bin/bash
# Browse GitHub repositories in fzf (owner -> team -> repos) and clone them into $WORKSPACE.
# Archived repos and repos already cloned in $WORKSPACE or $HOME (by folder name or origin) are not listed.
# Each clone can get a custom folder name; it is then added to the vault project's aliases.

DEST="${WORKSPACE:-$HOME}"
ALL="* all"
VAULT="$HOME/claude-vault"

if ! gh auth status &> /dev/null; then
    echo "GitHub login (choose SSH to also generate/upload an SSH key)..."
    gh auth login || exit 1
fi

echo "Fetching repositories..."
me=$(gh api user --jq .login)
# owner/name of the origin of every repo already cloned (catches renamed folders)
cloned=$(for d in "$DEST"/*/ "$HOME"/*/; do git -C "$d" remote get-url origin 2>/dev/null; done \
    | sed -E 's#(\.git)?/?$##; s#.*[:/]([^/]+/[^/]+)$#\1#' | tr 'A-Z' 'a-z')
# Every reachable, non-archived repo (owned, collaborator, organization member): full_name <TAB> description
repos=$(gh api --paginate "user/repos?affiliation=owner,collaborator,organization_member&per_page=100" \
    --jq '.[] | select(.archived | not) | [.full_name, (.description // "")] | @tsv' \
    | sort \
    | while IFS=$'\t' read -r repo desc; do
        name="${repo#*/}"
        [ -e "$DEST/$name" ] || [ -e "$HOME/$name" ] || grep -qxi "$repo" <<< "$cloned" \
            || printf '%s\t%s\n' "$repo" "$desc"
    done)
# Teams of the user: org <TAB> team slug
teams=$(gh api --paginate user/teams --jq '.[] | [.organization.login, .slug] | @tsv' 2>/dev/null)

# Add folder $2 to the aliases of the vault project named $1 (if any), so the vault hook resolves it
add_vault_alias() {
    local log
    log=$(ls "$VAULT"/projects/{,*/}"${1,,}"/logbook.md 2>/dev/null | head -1)
    [ -n "$log" ] || return 0
    if grep -q '^aliases:' "$log"; then
        sed -i "s/^aliases: *\[\(.*\)\]/aliases: [\1, $2]/; s/\[, /[/" "$log"
    elif head -1 "$log" | grep -qx -- '---'; then
        sed -i "1a aliases: [$2]" "$log"
    else
        sed -i "1i ---\naliases: [$2]\n---" "$log"
    fi
    git -C "$VAULT" add "$log" && git -C "$VAULT" commit -qm "docs(${1,,}): add folder alias $2" \
        && git -C "$VAULT" push -q 2>/dev/null
    echo "Vault: alias '$2' added to ${log#$VAULT/}"
}

# Keep only the lines of $2 whose first field is listed in $1
keep() { awk -F'\t' 'NR==FNR {k[$1]; next} $1 in k' <(printf '%s\n' "$1") <(printf '%s\n' "$2"); }

while true; do
    # Level 1: owner (user first, then organizations)
    owner=$( {
        echo "$ALL"
        cut -f1 <<< "$repos" | cut -d/ -f1 | sort | uniq -c \
            | awk -v me="$me" '{print ($2 == me ? 0 : 1) "\t" $2 "\t" $1 " repos" ($2 == me ? " (you)" : "")}' \
            | sort -k1,1n -k2,2 | cut -f2-
    } | fzf --delimiter='\t' --prompt="Owner > " --header="ENTER: open   ESC: quit" | cut -f1)
    [ -z "$owner" ] && break

    list="$repos"
    if [ "$owner" != "$ALL" ]; then
        list=$(awk -F'\t' -v o="$owner/" 'index($1, o) == 1' <<< "$repos")

        # Level 2: team, when the user belongs to teams of this organization
        owner_teams=$(awk -F'\t' -v o="$owner" '$1 == o {print $2}' <<< "$teams")
        if [ -n "$owner_teams" ]; then
            team=$(printf '%s\n%s\n' "$ALL" "$owner_teams" \
                | fzf --prompt="$owner / team > " --header="ENTER: open   ESC: back")
            [ -z "$team" ] && continue
            if [ "$team" != "$ALL" ]; then
                team_repos=$(gh api --paginate "orgs/$owner/teams/$team/repos?per_page=100" --jq '.[].full_name')
                list=$(keep "$team_repos" "$list")
            fi
        fi
    fi

    # Level 3: repositories (multi-select, keyword search on name and description)
    selected=$(grep -v '^$' <<< "$list" \
        | fzf --multi --delimiter='\t' --prompt="Clone into $DEST > " \
              --header="TAB: select   ENTER: clone selection   ESC: back" \
        | cut -f1)
    for repo in $selected; do
        name="${repo#*/}"
        while true; do
            read -rp "Folder name for $repo [$name]: " dir < /dev/tty
            dir="${dir:-$name}"
            [ -e "$DEST/$dir" ] && echo "$DEST/$dir already exists." || break
        done
        gh repo clone "$repo" "$DEST/$dir" < /dev/null || continue
        repos=$(awk -F'\t' -v r="$repo" '$1 != r' <<< "$repos")
        [ "$dir" != "$name" ] && add_vault_alias "$name" "$dir"
    done
done
