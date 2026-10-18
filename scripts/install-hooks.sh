#!/bin/bash
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chmod +x .githooks/pre-commit scripts/policy-check.sh
git config core.hooksPath .githooks
echo "[OK] git hooks enabled (core.hooksPath=.githooks)"
