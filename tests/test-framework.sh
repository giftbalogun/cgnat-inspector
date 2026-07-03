#!/usr/bin/env bash
# tests/test-framework.sh
# Minimal, dependency-free assertion framework shared by all test files.
# Not listed as a standalone suite; sourced by test-*.sh files and
# orchestrated by run-tests.sh.

if [[ -n "${CGNAT_TEST_FRAMEWORK_LOADED:-}" ]]; then
    return 0
fi
CGNAT_TEST_FRAMEWORK_LOADED=1

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TEST_NAMES=()

_pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf '  \033[32m✔\033[0m %s\n' "$1"
}

_fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TEST_NAMES+=("$1")
    printf '  \033[31m✖\033[0m %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '      %s\n' "$2"
}

# assert_true '<command string>' "<description>"
assert_true() {
    local expr="$1"
    local desc="$2"
    if eval "${expr}" >/dev/null 2>&1; then
        _pass "${desc}"
    else
        _fail "${desc}" "expected true: ${expr}"
    fi
}

# assert_false '<command string>' "<description>"
assert_false() {
    local expr="$1"
    local desc="$2"
    if eval "${expr}" >/dev/null 2>&1; then
        _fail "${desc}" "expected false: ${expr}"
    else
        _pass "${desc}"
    fi
}

# assert_equals <expected> <actual> "<description>"
assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        _pass "${desc}"
    else
        _fail "${desc}" "expected '${expected}', got '${actual}'"
    fi
}

# assert_not_empty <value> "<description>"
assert_not_empty() {
    local value="$1"
    local desc="$2"
    if [[ -n "${value}" ]]; then
        _pass "${desc}"
    else
        _fail "${desc}" "expected non-empty value"
    fi
}

# run_test_suite "<suite name>" test_fn1 test_fn2 ...
# Runs each test function, then prints a summary and exits non-zero if
# any assertion in the suite failed. Intended to be the last line of a
# test-*.sh file so `bash tests/test-X.sh` works standalone too.
run_test_suite() {
    local suite_name="$1"
    shift
    local fn

    printf '\n\033[1m%s\033[0m\n' "${suite_name}"

    for fn in "$@"; do
        "${fn}"
    done

    printf '\n%d run, \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' \
        "${TESTS_RUN}" "${TESTS_PASSED}" "${TESTS_FAILED}"

    if [[ "${TESTS_FAILED}" -gt 0 ]]; then
        return 1
    fi
    return 0
}
