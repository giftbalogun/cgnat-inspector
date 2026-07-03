#!/usr/bin/env bash
# tests/test-json.sh
# Unit tests for lib/json.sh: escaping, string/bool/array encoding, and
# full report assembly. Where available, `jq` is used to validate that
# output is actually well-formed JSON, not just visually plausible.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=lib/colors.sh
source "${ROOT_DIR}/lib/colors.sh"
color_init true
# shellcheck source=lib/utils.sh
source "${ROOT_DIR}/lib/utils.sh"
# shellcheck source=lib/json.sh
source "${ROOT_DIR}/lib/json.sh"

# shellcheck source=tests/test-framework.sh
source "${SCRIPT_DIR}/test-framework.sh"

test_json_escape() {
    assert_equals 'hello' "$(json_escape "hello")" "plain string unchanged"
    assert_equals 'a\"b' "$(json_escape 'a"b')" "double quote escaped"
    assert_equals 'a\\b' "$(json_escape 'a\b')" "backslash escaped"
}

test_json_string_or_null() {
    assert_equals '"1.2.3.4"' "$(json_string_or_null "1.2.3.4")" "non-empty string quoted"
    assert_equals 'null' "$(json_string_or_null "")" "empty string becomes null"
    assert_equals 'null' "$(json_string_or_null "null")" "literal null string stays null"
}

test_json_bool() {
    assert_equals 'true' "$(json_bool "true")" "true stays true"
    assert_equals 'false' "$(json_bool "false")" "false stays false"
    assert_equals 'false' "$(json_bool "anything-else")" "non-true defaults to false"
}

test_json_array_of_strings() {
    local result
    result=$(printf 'a\nb\nc\n' | json_array_of_strings)
    assert_equals '["a","b","c"]' "${result}" "three-item array"

    result=$(printf '' | json_array_of_strings)
    assert_equals '[]' "${result}" "empty input produces empty array"

    result=$(printf 'only\n' | json_array_of_strings)
    assert_equals '["only"]' "${result}" "single-item array"
}

test_json_build_report_is_valid() {
    local recs
    recs=$(printf 'Request Public IPv4\nUse IPv6\n')

    local output
    output=$(json_build_report "CGNAT" 95 "192.168.1.15" "192.168.1.1" \
        "100.91.0.22" "102.1.2.3" "" "true" "true" "false" "true" "${recs}")

    assert_not_empty "${output}" "report is non-empty"

    if has_cmd jq; then
        assert_true "printf '%s' '${output}' | jq -e . >/dev/null 2>&1" "report is valid JSON (validated via jq)"
        local status
        status=$(printf '%s' "${output}" | jq -r '.status')
        assert_equals "CGNAT" "${status}" "jq extracts correct status field"
    else
        # Fallback structural check without jq: braces balance and key
        # fields are present. These assertions intentionally pass a
        # single-quoted expression string to assert_true for later eval,
        # so the variables below expand at eval-time, not here.
        # shellcheck disable=SC2016
        assert_true '[[ "${output}" == \{*\} ]]' "report starts/ends with braces"
        # shellcheck disable=SC2016
        assert_true 'printf "%s" "${output}" | grep -q "\"status\":\"CGNAT\""' "status field present"
    fi
}

test_json_build_report_null_fields() {
    local output
    output=$(json_build_report "PUBLIC" 0 "" "" "" "" "" "false" "false" "false" "false" "")

    if has_cmd jq; then
        assert_true "printf '%s' '${output}' | jq -e . >/dev/null 2>&1" "report with empty fields is still valid JSON"
        local ipv6
        ipv6=$(printf '%s' "${output}" | jq -r '.ipv6')
        assert_equals "null" "${ipv6}" "empty ipv6 becomes JSON null"
    else
        # shellcheck disable=SC2016
        assert_true 'printf "%s" "${output}" | grep -q "\"ipv6\":null"' "empty ipv6 becomes JSON null (no jq)"
    fi
}

run_test_suite "JSON Encoding Tests" \
    test_json_escape \
    test_json_string_or_null \
    test_json_bool \
    test_json_array_of_strings \
    test_json_build_report_is_valid \
    test_json_build_report_null_fields
