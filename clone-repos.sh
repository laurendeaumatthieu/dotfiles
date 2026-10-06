#!/bin/bash
# Browse GitHub repositories in fzf (owner -> team -> repos) and clone them into $WORKSPACE.
# Archived repos are not listed; repos already cloned in $WORKSPACE or $HOME (matched by origin) are shown
# in yellow with their folders and can be cloned again under another folder name.
# F2 renames the target folder of the current repo (and selects it); the name is then added to the
# vault project's aliases.

DEST="${WORKSPACE:-$HOME}"
ALL="* all"
VAULT="$HOME/claude-vault"
# Renames (owner/repo <TAB> folder) and the fzf helper, shared with fzf child processes
# Fall back to /tmp when $TMPDIR is missing (purged scratch disk)
TMP=$(mktemp -d 2> /dev/null || mktemp -d -p /tmp) || exit 1
trap 'rm -rf "$TMP"' EXIT
RENAMES="$TMP/renames"; HELPER="$TMP/helper.sh"; CLONED="$TMP/cloned"; touch "$RENAMES"
cat > "$HELPER" << 'HELPER_EOF'
# helper.sh rename|preview <owner/repo> <dest> <renames file>
repo=$2; dest=$3; renames=$4; name=${repo#*/}
current=$(awk -F'\t' -v r="$repo" '$1 == r {print $2}' "$renames")
if [ "$1" = rename ]; then
    while true; do
        read -rp "Folder name for $repo [${current:-$name}]: " dir < /dev/tty
        dir=${dir:-${current:-$name}}
        [ -e "$dest/$dir" ] && echo "$dest/$dir already exists." || break
    done
    awk -F'\t' -v r="$repo" '$1 != r' "$renames" > "$renames.tmp" && mv "$renames.tmp" "$renames"
    [ "$dir" != "$name" ] && printf '%s\t%s\n' "$repo" "$dir" >> "$renames"
else
    target="$dest/${current:-$name}"
    [ -e "$target" ] && echo "-> $target (exists: F2 to choose another name)" || echo "-> $target"
fi
HELPER_EOF

if ! gh auth status &> /dev/null; then
    echo "GitHub login (choose SSH to also generate/upload an SSH key)..."
    gh auth login || exit 1
fi

echo "Fetching repositories..."
me=$(gh api user --jq .login)
# Already cloned repos: lowercase owner/name of the origin <TAB> local folder
for d in "$DEST"/*/ "$HOME"/*/; do
    url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
    printf '%s\t%s\n' "$(sed -E 's#(\.git)?/?$##; s#.*[:/]([^/]+/[^/]+)$#\1#' <<< "$url" | tr 'A-Z' 'a-z')" "$(basename "$d")"
done > "$CLONED"
# Every reachable, non-archived repo (owned, collaborator, organization member): full_name <TAB> description
repos=$(gh api --paginate "user/repos?affiliation=owner,collaborator,organization_member&per_page=100" \
    --jq '.[] | select(.archived | not) | [.full_name, (.description // "")] | @tsv' | sort)
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

# fzf lines: raw full_name (hidden, used by {1}) <TAB> displayed full_name <TAB> description;
# cloned repos in yellow with their folders
decorate() {
    awk -F'\t' 'NR==FNR {d[$1] = ($1 in d ? d[$1] ", " : "") $2; next}
        $1 != "" {k = tolower($1)
            if (k in d) printf "%s\t\033[33m%s\033[0m\t%s \033[2m[cloned: %s]\033[0m\n", $1, $1, $2, d[k]
            else printf "%s\t%s\t%s\n", $1, $1, $2}' "$CLONED" - 
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
    selected=$(decorate <<< "$list" \
        | SHELL=bash fzf --multi --ansi --delimiter='\t' --with-nth=2.. --prompt="Clone into $DEST > " \
              --header="TAB: select   F2: select + rename folder   ENTER: clone selection   ESC: back" \
              --preview="bash '$HELPER' preview {1} '$DEST' '$RENAMES'" --preview-window=down,1 \
              --bind="f2:execute(bash '$HELPER' rename {1} '$DEST' '$RENAMES')+select+refresh-preview" \
        | cut -f1)
    for repo in $selected; do
        name="${repo#*/}"
        dir=$(awk -F'\t' -v r="$repo" '$1 == r {print $2}' "$RENAMES"); dir="${dir:-$name}"
        while [ -e "$DEST/$dir" ]; do
            read -rp "$DEST/$dir exists. Folder name for $repo (empty = skip): " dir < /dev/tty
            [ -z "$dir" ] && continue 2
        done
        gh repo clone "$repo" "$DEST/$dir" < /dev/null || continue
        printf '%s\t%s\n' "${repo,,}" "$dir" >> "$CLONED"
        [ "$dir" != "$name" ] && add_vault_alias "$name" "$dir"
    done
done
