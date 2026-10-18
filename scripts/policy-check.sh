#!/bin/bash
# Machine-enforced repo policies. Usage: scripts/policy-check.sh [--staged]
#   (no flag)  check the whole tracked tree (CI, pre-build)
#   --staged   pre-commit mode: also blocks SMC.swift edits unless ALLOW_SMC=1
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-all}"
FAIL=0
err()  { echo "[ERR] $*"; FAIL=1; }

if [ "$MODE" = "--staged" ]; then
    CHANGED=$(git diff --cached --name-only --diff-filter=ACM)
else
    CHANGED=$(git ls-files)
fi
TRACKED=$(git ls-files)

# 1. No pictographic emoji in text sources.
TEXT_FILES=$(printf '%s\n' "$CHANGED" | grep -E '\.(swift|sh|md|yml|yaml|plist|py)$' || true)
if [ -n "$TEXT_FILES" ]; then
    printf '%s\n' "$TEXT_FILES" | python3 -c '
import sys
pat = __import__("re").compile("[\U0001F000-\U0001FAFF\u2600-\u2712\u2714-\u2716\u2718-\u27BF\u2B50-\u2B55\uFE0F\u200D]")
bad = 0
for p in sys.stdin.read().split():
    try:
        lines = open(p, encoding="utf-8").read().splitlines()
    except Exception:
        continue
    for n, l in enumerate(lines, 1):
        m = pat.search(l)
        if m:
            print("[ERR] emoji U+%04X at %s:%d" % (ord(m.group()), p, n))
            bad = 1
sys.exit(bad)
' || FAIL=1
fi

# 2. SMC.swift is protected at commit time.
if [ "$MODE" = "--staged" ] && printf '%s\n' "$CHANGED" | grep -qx 'SMC.swift' && [ "${ALLOW_SMC:-0}" != "1" ]; then
    err "SMC.swift is staged. It is protected (IOKit). If intentional: ALLOW_SMC=1 git commit ..."
fi

# 3. Info.plist must keep LSUIElement = true.
if ! grep -A1 '<key>LSUIElement</key>' Info.plist | grep -q '<true/>'; then
    err "Info.plist: LSUIElement must stay true."
fi

# 4. Every UserDefaults key in code is documented in AGENTS.md.
for k in $(grep -ho 'forKey: "[A-Za-z0-9_]*"' ./*.swift 2>/dev/null | sed 's/.*"\(.*\)"/\1/' | sort -u); do
    grep -q "\`$k\`" AGENTS.md || err "UserDefaults key '$k' is not documented in AGENTS.md."
done

# 5. Build artifacts must not be tracked.
if printf '%s\n' "$TRACKED" | grep -E '^(Version\.swift|MeMo_bin)$|\.app/|_arm64$|_x86_64$|build_history\.log$' >/dev/null; then
    err "Build artifact is tracked by git (Version.swift, MeMo_bin, .app, *_arm64, build_history.log)."
fi

# 6. CLAUDE.md / GEMINI.md must stay thin pointers to AGENTS.md.
for f in CLAUDE.md GEMINI.md; do
    if [ -f "$f" ]; then
        [ "$(wc -l < "$f")" -le 5 ] || err "$f must be a short pointer to AGENTS.md (<= 5 lines)."
        grep -q '@AGENTS.md' "$f" || err "$f must reference @AGENTS.md."
    fi
done

if [ "$FAIL" -ne 0 ]; then
    echo "[ERR] policy-check failed."
    exit 1
fi
echo "[OK] policy-check passed."
