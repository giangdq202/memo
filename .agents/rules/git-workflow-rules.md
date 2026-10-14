---
name: git-workflow-rules
description: Git branch naming, commit format, and merge strategy rules for the MeMo project.
trigger: always_on
---

# Git Workflow Rules — MeMo

## 1. Branch Naming

```
feat/<feature-name>      New feature
fix/<bug-description>    Bug fix
refactor/<scope>         Refactor without behavior change
docs/<what>              Docs or comments only
```

Examples: `feat/compact-display-mode`, `fix/network-bytes-overflow`, `refactor/color-utility`

## 2. Branch Creation

Always branch from `main`:
```bash
git checkout main
git pull origin main
git checkout -b feat/<name>
```

**[CRITICAL]** Never commit directly to `main`. Never `git merge` into `main` locally.

## 3. Conventional Commits

Format: `<type>: <short description>`

```
feat     New feature
fix      Bug fix
refactor Refactor — no behavior change, no new feature
docs     Documentation or comments
style    Formatting, whitespace — no logic change
chore    Build process, tooling
```

One logical change per commit. Build must pass before committing.

## 4. Merge Strategy

Repository has Branch Protection on `main`. Only Squash Merge via Pull Request is allowed.

```bash
git push -u origin feat/<name>
gh pr create --title "feat: ..." --body "..."
gh pr merge --squash --delete-branch
git checkout main && git pull origin main
```

## 5. What Must Never Be Committed

* `MeMo.app/`, `MeMo_bin`, `*_arm64`, `*_x86_64`, `Version.swift`
* Files listed in `.gitignore`
* Actual passwords, tokens, or keys
