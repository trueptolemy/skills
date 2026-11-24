#!/usr/bin/env bash
# Example SETUP_HOOK: make untracked dependencies available in a new worktree
# without copying them and without dirtying `git status`.
# Usage (called by new-task.sh): setup-worktree.example.sh <worktree>
set -euo pipefail
wt=$1
main=/path/to/myrepo                       # the main checkout
dep=src/bridge/node_modules                # an untracked, installed tree

ln -s "$main/$dep" "$wt/$dep"
# Worktrees share the main repository's info/exclude. A symlink is not a
# directory, so a `node_modules/` .gitignore rule does not hide it.
exclude=$(cd "$main" && cd "$(git rev-parse --git-common-dir)" && pwd)/info/exclude
grep -qxF "$dep" "$exclude" 2>/dev/null || echo "$dep" >> "$exclude"
