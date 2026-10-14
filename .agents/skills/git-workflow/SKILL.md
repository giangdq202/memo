---
name: git-workflow
description: Git branch naming, commit format, PR workflow, and stash usage for the MeMo project. Activate when creating a branch, committing code, or merging a feature.
---

# Skill: Git Workflow

## Branch Naming

```
feat/<feature-name>      New feature
fix/<bug-description>    Bug fix
refactor/<scope>         Refactor — no behavior change
docs/<what>              Docs or comments only
```

Real examples:
```
feat/custom-color-thresholds
feat/compact-display-mode
fix/network-bytes-overflow
refactor/color-utility-functions
docs/update-agents-md
```

---

## Creating A Branch

Always branch from `main`:
```bash
git checkout main
git pull origin main
git checkout -b feat/<name>
```

[WARN] If `main` has uncommitted changes, commit or stash first.

---

## Conventional Commits

Format: `<type>: <short description>`

```
feat     New feature
fix      Bug fix
refactor Refactor — no new feature, no bug fix
docs     Documentation, comments
style    Formatting, whitespace — no logic change
chore    Build process, tooling
```

Examples:
```bash
git commit -m "feat: add discrete color thresholds for CPU/RAM"
git commit -m "fix: prevent crash when SMC returns nil temperature"
git commit -m "refactor: extract colorForThreshold() to StatusBarView"
git commit -m "docs: add git-workflow skill"
git commit -m "chore: fix SDK path in build.sh for Swift 6.2.4"
```

Rules:
* One logical unit per commit.
* Build must pass before committing.
* Never commit broken code.
* Never commit `.app`, `*_arm64`, `*_x86_64`, `Version.swift`.

---

## Merge Strategy (Branch Protection)

[CRITICAL] Repository has Branch Protection on `main`. Direct push and local merge are blocked.

```bash
# 1. Push feature branch
git push -u origin feat/<name>

# 2. Open Pull Request
gh pr create --title "feat: ..." --body "..."

# 3. Squash Merge
gh pr merge --squash --delete-branch

# 4. Update local main
git checkout main
git pull origin main
```

---

## View History

```bash
git log --oneline -10        # Last 10 commits
git log --oneline --graph    # With branch graph
git diff main                # Compare to main
git status                   # Modified files
```

---

## Stash (Save Work In Progress)

```bash
git stash              # Save uncommitted changes
git stash pop          # Restore changes
git stash list         # List saved stashes
```
