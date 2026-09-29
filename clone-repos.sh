#!/bin/bash
# Pick GitHub repositories in fzf (multi-select) and clone them into $WORKSPACE.
# Repos already present in $WORKSPACE or $HOME are not listed.

DEST="${WORKSPACE:-$HOME}"

if ! gh auth status &> /dev/null; then
    echo "GitHub login (choose SSH to also generate/upload an SSH key)..."
    gh auth login || exit 1
fi

# Every reachable repo: owned, collaborator, organization member
gh api --paginate "user/repos?affiliation=owner,collaborator,organization_member&per_page=100" \
    --jq '.[] | [.full_name, (.description // "")] | @tsv' \
    | sort \
    | while IFS=$'\t' read -r repo desc; do
        name="${repo#*/}"
        [ -e "$DEST/$name" ] || [ -e "$HOME/$name" ] || printf '%s\t%s\n' "$repo" "$desc"
    done \
    | fzf --multi --delimiter='\t' --prompt="Clone into $DEST > " \
          --header="TAB: select   ENTER: clone selection   ESC: skip" \
    | cut -f1 \
    | while read -r repo; do
        gh repo clone "$repo" "$DEST/${repo#*/}" < /dev/null
    done
