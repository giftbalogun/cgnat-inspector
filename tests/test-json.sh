#!/usr/bin/env bash
# tests/test-json.sh
# Unit tests for lib/json.sh: escaping, string/bool/array/evidence
# encoding, and full report assembly. Where available, `jq` is used to
# validate that output is actually well-formed JSON, not just visually
# plausible.

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

test_json_array_of_hops() {
    local input
    input=$(printf '1 192.168.1.1\n2 100.91.0.1\n')
    local result
    result=$(json_array_of_hops "${input}")
    assert_equals '[{"hop":1,"ip":"192.168.1.1"},{"hop":2,"ip":"100.91.0.1"}]' "${result}" \
        "two-hop traceroute array"

    result=$(json_array_of_hops "")
    assert_equals '[]' "${result}" "empty traceroute input produces empty array"
}

test_json_array_of_evidence() {
    local input
    input=$(printf 'Internet connectivity confirmed\ttrue\nRouter WAN address obtained\tfalse\n')
    local result
    result=$(json_array_of_evidence "${input}")
    assert_equals '[{"description":"Internet connectivity confirmed","present":true},{"description":"Router WAN address obtained","present":false}]' \
        "${result}" "two-item evidence array with mixed booleans"

    result=$(json_array_of_evidence "")
    assert_equals '[]' "${result}" "empty evidence input produces empty array"
}

test_json_build_report_is_valid() {
    local recs
    recs=$(printf 'Request a Public IPv4 address from your ISP\nEnable IPv6 if available\n')
    local evidence
    evidence=$(printf 'Internet connectivity confirmed\ttrue\nRouter WAN address obtained\tfalse\n')

    local output
    output=$(json_build_report "POSSIBLE_CGNAT" 55 "192.168.1.15" "192.168.1.1" \
        "" "" "" "${evidence}" "The evidence suggests possible CGNAT." "${recs}")

    assert_not_empty "${output}" "report is non-empty"

    if has_cmd jq; then
        assert_true "printf '%s' '${output}' | jq -e . >/dev/null 2>&1" "report is valid JSON (validated via jq)"
        local status
        status=$(printf '%s' "${output}" | jq -r '.status')
        assert_equals "POSSIBLE_CGNAT" "${status}" "jq extracts correct status field"
        local router_wan
        router_wan=$(printf '%s' "${output}" | jq -r '.router_wan')
        assert_equals "null" "${router_wan}" "unknown router_wan becomes JSON null"
        local evidence_count
        evidence_count=$(printf '%s' "${output}" | jq '.evidence | length')
        assert_equals "2" "${evidence_count}" "evidence array has the expected item count"
    else
        # shellcheck disable=SC2016
        assert_true '[[ "${output}" == \{*\} ]]' "report starts/ends with braces"
        # shellcheck disable=SC2016
        assert_true 'printf "%s" "${output}" | grep -q "\"status\":\"POSSIBLE_CGNAT\""' "status field present"
        # shellcheck disable=SC2016
        assert_true 'printf "%s" "${output}" | grep -q "\"router_wan\":null"' "router_wan is null when unknown (no jq)"
    fi
}

test_json_build_report_with_traceroute() {
    local hops
    hops=$(printf '1 192.168.1.1\n2 8.8.8.8\n')
    local output
    output=$(json_build_report "PUBLIC" 0 "192.168.1.15" "192.168.1.1" \
        "8.8.8.8" "8.8.8.8" "" "" "Public IPv4 confirmed." "" "${hops}")

    if has_cmd jq; then
        assert_true "printf '%s' '${output}' | jq -e . >/dev/null 2>&1" "report with traceroute is valid JSON"
        local trace_count
        trace_count=$(printf '%s' "${output}" | jq '.traceroute | length')
        assert_equals "2" "${trace_count}" "traceroute field has the expected hop count when provided"
    else
        # shellcheck disable=SC2016
        assert_true 'printf "%s" "${output}" | grep -q "\"traceroute\":\["' "traceroute field present when hops are provided (no jq)"
    fi
}

test_json_build_report_omits_traceroute_when_absent() {
    local output
    output=$(json_build_report "INCONCLUSIVE" 20 "" "" "" "" "" "" "Not enough evidence." "" "")

    if has_cmd jq; then
        local has_field
        has_field=$(printf '%s' "${output}" | jq 'has("traceroute")')
        assert_equals "false" "${has_field}" "traceroute field is entirely absent when no hops were provided"
    else
        # shellcheck disable=SC2016
        assert_false 'printf "%s" "${output}" | grep -q "\"traceroute\""' "no traceroute field present (no jq)"
    fi
}

run_test_suite "JSON Encoding Tests" \
    test_json_escape \
    test_json_string_or_null \
    test_json_bool \
    test_json_array_of_strings \
    test_json_array_of_hops \
    test_json_array_of_evidence \
    test_json_build_report_is_valid \
    test_json_build_report_with_traceroute \
    test_json_build_report_omits_traceroute_when_absent
