#!/bin/sh
# Every check, in one command:  sh tests/run_all.sh
# R and node are optional; the tests that need them are skipped with a note if
# they are not installed, and the Python checks still have to pass.
set -e
cd "$(dirname "$0")/.."
fail=0

run() {
  printf '%-34s ' "$2"
  if [ -z "$(command -v "$1")" ]; then printf 'skipped (%s not installed)\n' "$1"; return; fi
  if $1 "$2" > /tmp/ap_load_test_out 2>&1; then printf 'ok\n'
  else printf 'FAILED\n'; cat /tmp/ap_load_test_out; fail=1; fi
}

run python3 tests/test_table5.py
run python3 tests/test_refusals.py
run python3 tests/test_dose_parsing.py
run python3 tests/test_generated.py
run Rscript tests/test_table5.R
run Rscript tests/test_refusals.R
run Rscript tests/test_dose_parsing.R
run python3 tests/test_agreement.py
run node tests/test_web.js

echo
if [ "$fail" -eq 0 ]; then echo "All checks passed."; else echo "Some checks failed."; exit 1; fi
