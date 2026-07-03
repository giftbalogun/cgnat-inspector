#!/usr/bin/env bash
# tests/run-tests.sh
# Runs every test-*.sh file in this directory and prints an overall
# summary. Exits non-zero if any suite failed, so it is CI-friendly.
#
# Usage:
#   ./tests/run-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

printf '\033[1m=== CGNAT Inspector Test Suite ===\033[0m\n'

suite_files=()
while IFS= read -r -d '' f; do
    suite_files+=("${f}")
done < <(find "${SCRIPT_DIR}" -maxdepth 1 -name 'test-*.sh' -print0 | sort -z)

if [[ "${#suite_files[@]}" -eq 0 ]]; then
    printf 'No test files found matching tests/test-*.sh\n' >&2
    exit 1
fi

overall_status=0
total_suites=0
failed_suites=0

for suite in "${suite_files[@]}"; do
    total_suites=$((total_suites + 1))
    if bash "${suite}"; then
        :
    else
        failed_suites=$((failed_suites + 1))
        overall_status=1
    fi
done

printf '\n\033[1m=== Summary ===\033[0m\n'
printf 'Suites run: %d\n' "${total_suites}"
if [[ "${failed_suites}" -eq 0 ]]; then
    printf '\033[32mAll suites passed.\033[0m\n'
else
    printf '\033[31m%d suite(s) failed.\033[0m\n' "${failed_suites}"
fi

exit "${overall_status}"
