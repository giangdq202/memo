---
name: feature-planning-workflow
description: Mandatory workflow for starting any feature in MeMo. Activate BEFORE writing any code. Steps: Grill → Plan → Branch → Implement → Build → Test → Commit → Memory → PR & Merge.
---

# Skill: Feature Planning Workflow

## Mandatory Order

```
GRILL → PLAN → BRANCH → IMPLEMENT → BUILD → TEST → COMMIT → MEMORY → PR & MERGE
```

---

## Step 1: GRILL — Understand The True Intent

Do not write a single line of code until these 3 questions are answered:

1. **What**: What exactly does this feature do?
2. **Why**: Why is it needed? What problem does it solve?
3. **How**: How does the user interact with it?

Rules:
* Ask one question at a time — never dump multiple questions at once.
* Give a recommendation with reasoning, then wait for confirmation.
* If the answer is vague, grill further. Do not interpret or assume.

---

## Step 2: PLAN — Finalize A Specific Plan

After understanding intent, produce a plan and grill until it is approved:

```markdown
## Plan: <Feature Name>

### Scope
- In scope: <list>
- Out of scope: <list>

### Files to change
- `AppDelegate.swift`: <what to add>
- `StatusBarView.swift`: <what to modify>

### Files NOT to change
- `SMC.swift` [OK]
- `Info.plist` [OK]

### Implementation steps
1. <small step 1>
2. <small step 2>

### Definition of Done
- [ ] Build passes with no new warnings
- [ ] Feature works exactly as planned
- [ ] Settings persist after quit and reopen
```

Only begin coding once the developer confirms the plan.

---

## Step 3: BRANCH — Create Branch Before Any Code

```bash
git checkout main
git pull origin main
git checkout -b feat/<feature-name>
```

[CRITICAL] Never commit directly to `main`.

---

## Step 4: IMPLEMENT — Small Steps, Explain Why First

* Explain the reasoning before writing code.
* Each step: max 50 lines of code.
* Write clean code — no redundant comments.
* After each step, run the build.

---

## Step 5: BUILD — Verify Every Change

```bash
bash build.sh
```

* If build fails: fix it before continuing. Do not skip.
* Report the build result to the developer.

---

## Step 6: TEST — Confirm It Works

```bash
open MeMo.app
```

Checklist:
- [ ] App icon appears on the menu bar
- [ ] New feature works exactly as planned
- [ ] No regressions in existing features
- [ ] Dark mode and Light mode both render correctly
- [ ] Settings persist after quit and reopen

---

## Step 7: COMMIT — Conventional Commits

```bash
git commit -m "feat: add compact display toggle"
git commit -m "fix: correct memory calculation on M4"
git commit -m "refactor: extract threshold logic to helper"
git commit -m "docs: update AGENTS.md with new UserDefaults key"
```

One logical unit per commit. Build must pass before committing.

---

## Step 8: MEMORY — Update After Every Commit

After each commit, update:
* `.agents/memory/project.md` — architectural decisions, roadmap status
* `.agents/memory/swift-learnings.md` — Swift concepts used
* `.agents/memory/bugs.md` — if a bug was found and fixed

---

## Step 9: PR & MERGE

```bash
git push -u origin feat/<name>
gh pr create --title "feat: <name>" --body "<description>"
gh pr merge --squash --delete-branch
git checkout main && git pull origin main
```

[CRITICAL] Do not `git merge` into `main` locally. Repository has Branch Protection — only Squash Merge via Pull Request is allowed.
