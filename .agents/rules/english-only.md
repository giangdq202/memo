---
name: english-only
description: All Swift source files, shell scripts, and repository-level markdown documents must be written in English. The .agents/ configuration folder may use Vietnamese.
trigger: always_on
---

# Language Policy — MeMo

## Scope: English Required

All of the following **must** be written in English:
* Swift source files (`.swift`) — code, comments, docstrings
* Shell scripts (`build.sh`, `install.sh`, `uninstall.sh`, hooks)
* Root-level markdown files (`README.md`, `AGENTS.md`, `GEMINI.md`)
* Git commit messages
* GitHub Actions workflow files (`.github/`)

No emojis, emoticons, or non-ASCII characters in any of the above.

## Scope: Vietnamese Permitted

The `.agents/` configuration folder (rules, skills, memory, hooks) may be written in Vietnamese since it is a personal learning reference used by the developer, not distributed code.

## Commit Messages

Conventional Commits format, English only:
```
feat: add compact display toggle
fix: correct network bytes overflow on reconnect
refactor: extract threshold color logic
docs: update AGENTS.md key files table
```
