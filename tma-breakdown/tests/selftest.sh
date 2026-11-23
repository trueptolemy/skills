#!/usr/bin/env bash
# Offline self-test of tma-breakdown on synthetic EMON data (no real data, no network).
# Set TMA_REAL_EMON=<emon.csv> and TMA_REAL_SCORES=<scores.csv> (and TMA_REAL_BASELINE,
# default bm) to also smoke-test the report on real data.
# Usage: tma-breakdown/tests/selftest.sh
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
command -v python3 >/dev/null || { echo "FAIL python3 not found" >&2; exit 1; }
python3 -I "$here/tests/test_tma_breakdown.py" 2>&1 | tail -n 3
if [[ -n ${TMA_REAL_EMON:-} ]]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  python3 -I "$here/scripts/tma_breakdown.py" report --emon "$TMA_REAL_EMON" --scores "${TMA_REAL_SCORES:?}" \
    --workload real-data-smoke --baseline "${TMA_REAL_BASELINE:-bm}" --force --out "$tmp/r.md" > /dev/null
  grep -q '^## 5. Top-level breakdown' "$tmp/r.md" || { echo "FAIL real-data report" >&2; exit 1; }
  echo "ok   real-data report"
fi
echo "tma-breakdown selftest: passed"
