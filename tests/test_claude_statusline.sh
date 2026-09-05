#!/bin/bash
# tests/test_claude_statusline.sh — the status line carries its own self-check
# (thresholds, the gauge ramp, a quiet session, narrow-terminal truncation, the
# Touch Bar hand-off, empty and invalid stdin). This is what puts it on CI's
# path; the assertions live next to the code they check.
set -uo pipefail
cd "$(dirname "$0")/.."

if out=$(bash agents/claude-statusline.sh --test 2>&1); then
    echo "PASS test_claude_statusline"
else
    echo "$out"
    exit 1
fi
