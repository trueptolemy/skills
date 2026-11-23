# Claude Code skills

Each top-level directory is one skill. It holds the `SKILL.md` that Claude
loads, plus its own scripts, references, tests and README. The repository
root has only what every skill shares: this index, the installer and the
test runner.

| skill | what it does | details |
|---|---|---|
| [codex-delegation](codex-delegation/) | Claude plans and accepts; the OpenAI Codex CLI implements in isolated git worktrees, with independent gates, round-numbered feedback and circuit breakers | [codex-delegation/README.md](codex-delegation/README.md) |
| [tma-breakdown](tma-breakdown/) | Breaks a virtual-machine-vs-bare-metal (or any two-configuration) throughput score gap into Intel TMA / top-down nodes from EMON summaries. Checks whether the method applies first, then cross-validates the large gaps with other EMON metrics and writes a Markdown report | [tma-breakdown/README.md](tma-breakdown/README.md) |

## Layout

```
README.md            this index
install.sh           install one or all skills into Claude Code (user or project level)
selftest.sh          run every <skill>/tests/selftest.sh, then test install.sh
codex-delegation/    SKILL.md, README.md, scripts/, templates/, reference/, tests/
tma-breakdown/       SKILL.md, README.md, scripts/, reference/, tests/
```

## Install

```bash
git clone <this-repo> ~/skill && cd ~/skill
./selftest.sh                              # optional: offline tests of every skill and the installer
./install.sh                               # every skill, user level: ~/.claude/skills/<skill>
./install.sh --skill tma-breakdown         # one skill
./install.sh --project /path/repo          # project level: /path/repo/.claude/skills/<skill>
./install.sh --link                        # symlink to this checkout while editing a skill
./install.sh --force                       # replace installed copies
./install.sh --uninstall [--skill <name>]  # remove
./install.sh --dry-run                     # validate and print the actions only
```

The installer validates each `SKILL.md`: the frontmatter name must equal the
directory name, and a description is required (at most 1024 characters).
Tests are not copied into the installation. Start a new Claude Code session
to load newly installed skills.

## Adding a skill

1. Create `<name>/SKILL.md` with `name: <name>` and a `description:` in its frontmatter.
2. Keep everything the skill needs inside `<name>/`, and document it in `<name>/README.md`.
3. Add an offline `<name>/tests/selftest.sh` (exit 0 on success); `./selftest.sh` picks it up.
4. If the skill needs an external tool, add a check for it to the summary at the end of `install.sh`.
