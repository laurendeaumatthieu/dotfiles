# dotfiles

Personal shell, terminal, editor and Claude Code configuration, deployed by a single
**non-root**, **idempotent** installer. Designed for shared Linux servers (HPC, lab
machines) where `sudo` is unavailable, port 22 may be blocked, and `$HOME` quotas are small.

```bash
git clone git@github.com:laurendeaumatthieu/dotfiles.git ~/dotfiles   # or https://github.com/...
cd ~/dotfiles
./install.sh
# then restart the terminal
```

Re-running `./install.sh` at any time is safe: every step checks whether it is already done.

---

## Table of contents

1. [Repository layout](#repository-layout)
2. [What `install.sh` does, step by step](#what-installsh-does-step-by-step)
3. [Files written outside the repository](#files-written-outside-the-repository)
4. [Zsh](#zsh)
5. [Tmux](#tmux)
6. [VS Code](#vs-code)
7. [Claude Code](#claude-code)
8. [Repository cloner (`clone-repos.sh`)](#repository-cloner-clone-repossh)
9. [Common tasks](#common-tasks)
10. [Troubleshooting](#troubleshooting)

---

## Repository layout

```
dotfiles/
├── install.sh            # Main entry point: installs tools, links configs, sets the shell
├── backup/
│   ├── backup-home       # Daily restic snapshot of $HOME (desktop profile, symlinked to ~/.local/bin)
│   ├── backup-home.{service,timer}  # systemd user units (symlinked)
│   └── excludes          # restic exclude patterns
├── clone-repos.sh        # Interactive fzf browser to clone GitHub repos into $WORKSPACE
├── claude/
│   └── settings.json     # Shared Claude Code settings (merged, not symlinked)
├── desktop/
│   └── user-places.xbel  # Dolphin places template (copied once, @HOME@ substituted)
├── tmux/
│   └── tmux.conf         # Tmux config (symlinked)
├── vscode/
│   ├── install.sh        # Links VS Code configs, installs the font and extensions
│   ├── settings.json     # VS Code user settings (symlinked)
│   ├── keybindings.json  # VS Code keybindings (symlinked)
│   ├── extensions.txt    # One extension ID per line
│   └── snippets/         # VS Code user snippets (symlinked, currently empty)
└── zsh/
    ├── .zshrc            # Zsh config (symlinked to ~/.zshrc)
    └── aliases.zsh       # Extra functions/aliases (symlinked into Oh My Zsh custom dir)
```

**Symlinked vs. merged:** most configs are symlinks into this repo, so editing
`~/.zshrc` edits `~/dotfiles/zsh/.zshrc` directly (commit the change afterwards).
The only exception is `claude/settings.json`, which is *merged* into the local file
(see [Claude Code](#claude-code)).

---

## What `install.sh` does, step by step

The script runs in this exact order. Each step is skipped if already done.

### 0. Preconditions

- `$PATH` is extended with `~/.local/bin` and `~/.pixi/bin` for the duration of the script.
- `curl` must exist; otherwise the script aborts (it downloads everything else).

### 1. Profile and workspace (asked once per machine)

On first run, three questions are asked:

| Prompt | Default | Effect |
|---|---|---|
| `Profile: desktop or server` | `desktop` in a local graphical session, else `server` | Exported as `$DOTFILES_PROFILE`. `desktop` enables [step 10](#10-desktop-profile); `server` installs the CLI setup only. |
| `Workspace directory (git repos)` | `$HOME/work` | Exported as `$WORKSPACE`. Repos are cloned there. |
| `Directory for tmp/cache/state of all applications` | empty | If set, creates `<dir>/{tmp,cache,state}` (mode `700`) and exports `TMPDIR`, `XDG_CACHE_HOME`, `XDG_STATE_HOME` pointing there. If empty, standard Linux locations are kept (`/tmp`, `~/.cache`, `~/.local/state`). |

Answers are written to **`~/.config/dotfiles/env.zsh`** (machine-specific, *not*
versioned). It is sourced at the very top of `.zshrc`. The point of the scratch
directory is to move heavy caches (pip, uv, pixi, HuggingFace, torch...) off a small
`$HOME` quota onto a large work disk — they all honour `XDG_CACHE_HOME`.

To reconfigure: `rm ~/.config/dotfiles/env.zsh && ./install.sh`.

Network data disks go in **`~/share`**: every autofs/cifs/nfs mount under `/mnt` gets a
symlink `~/share/<name>` (refreshed on each run; nothing is created when there is none).
Backup scripts that follow symlinks (`rsync -L`) must exclude `~/share`.

### 2. CLI tools (no root)

Checks for `zsh git tmux tree btop fzf zoxide gh`. Any missing tool is installed with
[pixi](https://pixi.sh) from conda-forge (`pixi global install ...`) into `~/.pixi/bin`.
Pixi itself is installed first if needed (without touching shell rc files).

### 3. Claude Code and herdr

- **Claude Code** installed via `https://claude.ai/install.sh` into `~/.local/bin`.
- **herdr** installed via `https://herdr.dev/install.sh`, then
  `herdr integration install claude` registers its hooks in Claude Code.

### 4. Oh My Zsh, theme and plugins

- Oh My Zsh installed unattended into `~/.oh-my-zsh` (keeps the existing `.zshrc`,
  does not change the shell, does not start zsh).
- Cloned into `$ZSH_CUSTOM` (`~/.oh-my-zsh/custom`):
  - theme **powerlevel10k**
  - plugin **zsh-autosuggestions**
  - plugin **zsh-syntax-highlighting**
- Appends `killall xclip 2>/dev/null` to `~/.zlogout`: lingering `xclip` processes
  (used by tmux copy) otherwise keep SSH sessions from closing.

### 5. Claude Code settings merge

`claude/settings.json` is deep-merged into `~/.claude/settings.json` by an inline
Python script:

- nested objects are merged recursively,
- lists are **unioned** (shared items appended if missing),
- scalar values from the repo **overwrite** local ones,
- local-only keys are kept.

Why not a symlink: herdr writes hooks with machine-specific absolute paths into that
file, which must not end up in git.

### 6. GitHub access (SSH over port 443)

- Appends to `~/.ssh/config`:
  ```
  Host github.com
      Hostname ssh.github.com
      Port 443
      User git
  ```
  so `git@github.com:...` works on networks that block port 22.
- Fetches GitHub's official host keys from `https://api.github.com/meta` and adds them
  to `~/.ssh/known_hosts` as `[ssh.github.com]:443`, so non-interactive git (scripts,
  Claude Code) never stops on a "trust this host?" prompt.

### 7. Clone repositories

Runs [`clone-repos.sh`](#repository-cloner-clone-repossh): logs into GitHub with `gh`
if needed, then opens an fzf browser to pick repos to clone into `$WORKSPACE`.
Asked first (`[y/N]`, default no); run `./clone-repos.sh` any time later.

### 8. Claude vault

- Clones `git@github.com:laurendeaumatthieu/claude-vault.git` into `~/claude-vault`
  (prints a warning instead of failing if the SSH key is not registered yet).
- If `~/claude-vault/CLAUDE.md` exists, symlinks it to `~/.claude/CLAUDE.md`: the global
  Claude instructions live in the vault, so they are shared across machines.

> Note: an existing real `~/.claude/CLAUDE.md` is overwritten by the symlink without backup.

### 9. Symlinks

| Link | Target |
|---|---|
| `~/.zshrc` | `zsh/.zshrc` (an existing real file is moved to `~/.zshrc.backup`) |
| `~/.oh-my-zsh/custom/aliases.zsh` | `zsh/aliases.zsh` (auto-loaded by Oh My Zsh) |
| `~/.config/tmux/tmux.conf` (tmux ≥ 3.1) or `~/.tmux.conf` (older) | `tmux/tmux.conf` |

If the `code` CLI is available, [`vscode/install.sh`](#vs-code) runs too.

### 10. Desktop profile

Only when `DOTFILES_PROFILE=desktop`:

- Creates `~/{desktop,downloads,images,screenshots,apps}` and points the XDG dirs at them
  (`xdg-user-dirs-update --set DESKTOP|DOWNLOAD|PICTURES`). `~/images/Screenshots` is a
  symlink to `~/screenshots`, since GNOME saves captures into `<pictures>/Screenshots`.
- Dolphin places: `desktop/user-places.xbel` is copied only if `~/.local/share/user-places.xbel`
  does not exist (the live file also stores per-machine devices; never overwritten).
- restic backup: asks once for the repository path (empty = no backup), stored in
  `~/.config/restic/env`. The password is read (hidden) into `~/.config/restic/password`
  (mode `600`, **never versioned**: keep it in the password manager). The repository is
  initialized if new; several machines can share it (snapshots are grouped by host).
  `backup/backup-home` is linked into `~/.local/bin` and `backup-home.timer` enabled: daily at
  13:00 (`Persistent=true` catches up after downtime), retention 7 daily / 4 weekly / 6 monthly,
  weekly prune + 5% data check. Each run appends a line to `backup-history.log` next to the
  repository; failures also raise a desktop notification.

Useful commands (after `set -a; source ~/.config/restic/env; set +a; export RESTIC_PASSWORD_FILE=~/.config/restic/password`):
`restic snapshots`, `restic restore <id> --include <path> --target /tmp/r`, `restic mount ~/mnt-backup`,
`journalctl --user -u backup-home -f`.

### 11. Default shell

- If `zsh` is listed in `/etc/shells`, `chsh -s $(command -v zsh)` is tried.
- Otherwise (typical when zsh comes from pixi and `/etc/shells` is root-owned), a guarded
  block is appended to `~/.bashrc`:
  ```bash
  # >>> dotfiles zsh >>>
  ... interactive bash execs `zsh -l` ...
  # <<< dotfiles zsh <<<
  ```
  so every interactive login still lands in zsh. Remove that block to undo it.

---

## Files written outside the repository

Everything the installer creates or modifies, for easy auditing or uninstall:

| Path | Kind | Created by |
|---|---|---|
| `~/.config/dotfiles/env.zsh` | generated file | step 1 |
| `<scratch>/{tmp,cache,state}` | directories | step 1 (optional) |
| `~/share/<mount>` | symlinks to `/mnt/*` network mounts | step 1 |
| `~/.pixi/` | tool install | step 2 |
| `~/.local/bin/claude`, `~/.local/bin/herdr` | binaries | step 3 |
| `~/.oh-my-zsh/` (+ theme and plugins) | tool install | step 4 |
| `~/.zlogout` | appended line | step 4 |
| `~/.claude/settings.json` | merged file | step 5 |
| `~/.ssh/config`, `~/.ssh/known_hosts` | appended entries | step 6 |
| `$WORKSPACE/<repo>` | cloned repos | step 7 |
| `~/claude-vault/`, `~/.claude/CLAUDE.md` | clone + symlink | step 8 |
| `~/.zshrc`, `~/.zshrc.backup`, `~/.oh-my-zsh/custom/aliases.zsh`, tmux config | symlinks / backup | step 9 |
| `~/.config/Code/User/{settings.json,keybindings.json,snippets}` (+ `.backup`) | symlinks | VS Code step |
| `~/.local/share/fonts/MesloLGS NF *.ttf` | fonts | VS Code step |
| `~/{desktop,downloads,images,screenshots,apps}`, `~/.config/user-dirs.dirs`, `~/.local/share/user-places.xbel` | folders / XDG dirs / Dolphin places | step 10 (desktop) |
| `~/.config/restic/{env,password}`, `~/.local/bin/backup-home`, `~/.config/systemd/user/backup-home.*` | backup config / symlinks | step 10 (desktop) |
| `~/.bashrc` | appended block | step 11 (fallback only) |

---

## Zsh

File: `zsh/.zshrc` → `~/.zshrc`. Load order:

1. Source `~/.config/dotfiles/env.zsh` (must come first so the p10k instant prompt
   reads the relocated cache).
2. Powerlevel10k **instant prompt** (from `${XDG_CACHE_HOME:-~/.cache}`).
3. `PATH` += `~/bin`, `~/.local/bin`, `~/.pixi/bin`, `/usr/local/bin`, `/opt/nvim-linux-x86_64/bin`.
4. Oh My Zsh with theme `powerlevel10k`, hyphen-insensitive completion, history
   timestamps `yyyy-mm-dd`, `PYTHON_AUTO_VRUN=true` (auto-activate venvs on `cd`).
5. `~/.p10k.zsh` if present (generated by `p10k configure`; not versioned).
6. Custom function `add_venv_kernel`.
7. zoxide init, replacing `cd` (must remain last).

### Oh My Zsh plugins

| Plugin | Gives |
|---|---|
| `zoxide` | smart `cd` that learns frequent dirs (`cd proj` jumps to the best match) |
| `fzf`, `zsh-interactive-cd` | `Ctrl+R` fuzzy history, `Ctrl+T` fuzzy file picker, fzf on `cd <TAB>` |
| `zsh-autosuggestions` | grey inline suggestion from history; `→` accepts it |
| `zsh-syntax-highlighting` | colours valid/invalid commands while typing |
| `python` | python aliases + venv auto-activation (`PYTHON_AUTO_VRUN`) |
| `git` | git aliases (`gst`, `gco`, `gl`, `gp`, ...) |
| `docker` | docker completion and aliases |
| `dirhistory` | `Alt+←/→` previous/next dir, `Alt+↑` parent dir |
| `extract` | `extract <archive>` for any archive format |
| `command-not-found` | suggests the package providing a missing command |
| `web-search` | `google <terms>` etc. from the terminal |

### Custom commands

| Command | Defined in | Does |
|---|---|---|
| `add_venv_kernel <name>` | `.zshrc` | installs `ipykernel` in the **active** venv and registers it as a Jupyter kernel named `<name>` |
| `sv` (`find_and_source_venv`) | `aliases.zsh` | walks up from `$PWD` to find `venv/bin/activate` and sources it |
| `cd` | zoxide | zoxide-powered `cd` (`cdi` for interactive pick) |

`_ZO_DOCTOR=0` silences zoxide's warning in non-interactive shells (e.g. Claude Code
shell snapshots).

---

## Tmux

File: `tmux/tmux.conf`. Prefix is the default **`Ctrl+b`**.

### Settings

- 256 colours; OSC 52 clipboard passthrough (`set-clipboard on`).
- Mouse enabled; windows and panes numbered from 1; windows renumbered on close.
- 50 000 lines of scrollback; status bar at the **top**; vi keys in copy mode.

### Key bindings (after `Ctrl+b`)

| Key | Action | Replaces default |
|---|---|---|
| `h` | split left/right, in current dir | `%` |
| `v` | split top/bottom, in current dir | `"` |
| `t` | new window (tab), in current dir | `c` |
| `Tab` / `Shift+Tab` | next / previous window | — |
| `X` | kill window | `&` |
| `r` | rename window | — |

### Mouse

| Action | Effect |
|---|---|
| double-click on a tab | rename it |
| drag a tab | reorder windows |
| drag in a pane | select text and copy to clipboard via `xclip` (selection stays highlighted) |
| right-click in copy mode | cancel selection / exit copy mode |

Copying requires `xclip` and a forwarded X display (`ssh -X`/`-Y`) on remote machines.

---

## VS Code

Script: `vscode/install.sh` (called by `install.sh` only if `code` is on `PATH`; can be
run alone).

- **Local session** (`$SSH_CONNECTION` empty):
  - symlinks `settings.json`, `keybindings.json`, `snippets/` into
    `~/.config/Code/User/` (Linux) or `~/Library/Application Support/Code/User/` (macOS);
    existing real files are backed up once as `*.backup`;
  - installs the **MesloLGS NF** font (needed by Powerlevel10k in the integrated terminal).
- **Over SSH** (Remote-SSH terminal): settings come from the client, so only extensions
  are installed.
- Installs every extension listed in `extensions.txt` (blank lines and `#` comments ignored).

### Notable settings (`vscode/settings.json`)

- Word wrap on, minimap off, ligatures off, terminal font `MesloLGS NF`, GPU acceleration off.
- Git auto-fetch, no sync confirmation.
- Pylance basic type checking.
- LaTeX Workshop: single `latexmk` recipe (`-pdf --shell-escape -synctex=1`), output in
  `<dir>/build`, SyncTeX after build.
- Minimal UI: sidebar on the right, status bar hidden, layout/navigation controls hidden.
- Claude Code panel location: `panel`.
- cSpell extra words: `DICOM`, `SEGMENTATIONS`, `serie`.

### Keybindings (`vscode/keybindings.json`)

| Key | Action |
|---|---|
| `Ctrl+J` (in LaTeX) | SyncTeX jump from source to PDF (moved from `Ctrl+Alt+J`) |
| `Shift+Enter` (in terminal) | sends `ESC + Enter`: newline inside Claude Code's prompt |

### Extensions (`vscode/extensions.txt`)

Python/Jupyter suite, Remote (SSH, Containers), Claude Code, GitLens, LaTeX Workshop,
LanguageTool, Code Spell Checker, Rainbow CSV, Data Wrangler, SVG, Vue (Volar), Word Count.
Add a line to the file and re-run `vscode/install.sh` to add one.

---

## Claude Code

Shared settings in `claude/settings.json`, merged into `~/.claude/settings.json`:

| Key | Value | Meaning |
|---|---|---|
| `permissions.defaultMode` | `auto` | auto permission mode by default |
| `permissions.allow` | `Bash(git reset --soft:*)` | allows squashing local commits without a prompt |
| `theme` | `dark` | |
| `attribution.commit` / `attribution.pr` | `""` | **no** `Co-Authored-By: Claude` trailer in commits, no Claude footer in PR bodies |

Related pieces set up by the installer:

- **herdr** integration hooks (machine-specific, live only in the local settings file).
- **Global instructions** `~/.claude/CLAUDE.md` → symlink to `~/claude-vault/CLAUDE.md`.
- **claude-vault** (`~/claude-vault`): separate git repo used as Claude's persistent
  project memory (architecture / todo / logbook per project, reusable skills), also
  usable as an Obsidian vault.

---

## Repository cloner (`clone-repos.sh`)

Interactive three-level fzf browser over every repository reachable by the GitHub
account (owned, collaborator, organisation member). Can be run any time:
`bash ~/dotfiles/clone-repos.sh`.

1. **Login**: runs `gh auth login` if not authenticated (choosing SSH lets `gh`
   generate and upload an SSH key).
   Every level is sorted by most recent push (`pushed_at`): the most recently active
   owner, team and repo sit under the starting cursor; `* all` comes last.
2. **Owner** level: accounts and organisations with a repo count (`(you)` marks the
   user's own account), then `* all`.
3. **Team** level (only for organisations where the user belongs to teams):
   a team (filtering to that team's repos) or `* all`.
4. **Repos** level: multi-select with `TAB`, fuzzy search on name **and description**,
   `F2` selects the current repo and asks its folder name (default: the repo name; the
   preview line shows the target path), `ENTER` clones the selection into `$WORKSPACE`.
   When a folder name differs and the vault has a project named after the repo, it is appended to `aliases:` in that project's `logbook.md`
   (committed and pushed), so the claude-vault hook still resolves it.

Details:

- Archived repos are hidden. Repos already cloned in `$WORKSPACE` or `$HOME` (matched by
  `origin` remote, so renamed clones count) stay listed in yellow with `[cloned: <folders>]`;
  they can be cloned again under another folder name (`F2`, or asked at clone time when the
  target exists; empty answer skips).
- `ESC` goes back one level; `ESC` at the owner level quits.

---

## Common tasks

| Goal | Command |
|---|---|
| Install / repair on a new machine | `./install.sh` |
| Change profile, workspace or scratch dir | `rm ~/.config/dotfiles/env.zsh && ./install.sh` |
| Clone more repos | `bash clone-repos.sh` |
| Re-apply VS Code config / extensions | `bash vscode/install.sh` |
| Reconfigure the prompt | `p10k configure` |
| Reload zsh config | `exec zsh` |
| Reload tmux config | `tmux source ~/.config/tmux/tmux.conf` (or `~/.tmux.conf`) |
| Change shared Claude settings | edit `claude/settings.json`, re-run `./install.sh` |

---

## Troubleshooting

- **`curl is required`**: install curl (or ask an admin); everything else is downloaded with it.
- **Vault clone failed**: the SSH key is not on GitHub. Run `gh auth login` choosing SSH
  (or `gh ssh-key add ~/.ssh/id_ed25519.pub`), then re-run `./install.sh`.
- **`ssh: connect to host github.com port 22`**: the `~/.ssh/config` block from step 6
  is missing; re-run the installer.
- **Prompt shows broken glyphs**: the terminal font is not a Nerd Font; install
  MesloLGS NF (done automatically for VS Code) and select it in the terminal emulator.
- **Login shell is still bash**: expected when `chsh` is unavailable; the `~/.bashrc`
  block execs zsh for interactive sessions. Check that the block exists.
- **tmux copy does nothing**: `xclip` missing or no X forwarding (`echo $DISPLAY` is empty).
