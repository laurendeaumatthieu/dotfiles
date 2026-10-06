#!/usr/bin/env python3
"""Merge the shared Claude Code settings (dotfiles) into ~/.claude/settings.json.

The local file is not symlinked: herdr, rtk and Claude Code itself write machine-specific
content into it. Shared keys win; lists are unioned. The previously merged shared file is
kept so that entries removed or changed in the dotfiles are also removed locally (3-way).
Prints nothing when nothing changes.
"""
import json
import sys
from pathlib import Path

SHARED = Path(__file__).with_name("settings.json")
LOCAL = Path.home() / ".claude" / "settings.json"
LAST = Path.home() / ".cache" / "dotfiles" / "claude-settings.last.json"


def merge(local, shared, last):
    for key, value in shared.items():
        prev = last.get(key) if isinstance(last, dict) else None
        if isinstance(value, dict) and isinstance(local.get(key), dict):
            merge(local[key], value, prev if isinstance(prev, dict) else {})
        elif isinstance(value, list) and isinstance(local.get(key), list):
            dropped = [x for x in (prev or []) if x not in value]
            local[key] = [x for x in local[key] if x not in dropped] + [x for x in value if x not in local[key]]
        else:
            local[key] = value
    # Keys removed from the shared file since the last merge
    for key in (last or {}):
        if key not in shared and key in local and local[key] == last[key]:
            del local[key]
    return local


def main():
    shared = json.loads(SHARED.read_text())
    local = json.loads(LOCAL.read_text()) if LOCAL.exists() else {}
    last = json.loads(LAST.read_text()) if LAST.exists() else {}
    merged = merge(json.loads(json.dumps(local)), shared, last)
    if merged != local:
        LOCAL.parent.mkdir(parents=True, exist_ok=True)
        LOCAL.write_text(json.dumps(merged, indent=2) + "\n")
        print(f"Claude settings updated from {SHARED}", file=sys.stderr)
    LAST.parent.mkdir(parents=True, exist_ok=True)
    LAST.write_text(json.dumps(shared, indent=2) + "\n")


if __name__ == "__main__":
    main()
