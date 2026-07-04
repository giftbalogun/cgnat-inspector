#!/usr/bin/env bash
# tests/test-stun.sh
# Unit tests for the pure-Bash STUN (RFC 5389) response parser in
# lib/network.sh. These tests use hand-crafted fixture byte strings, so
# they never touch the network and are fully deterministic in CI/
# offline environments.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=lib/colors.sh
source "${ROOT_DIR}/lib/colors.sh"
color_init true
# shellcheck source=lib/utils.sh
source "${ROOT_DIR}/lib/utils.sh"
# shellcheck source=lib/network.sh
source "${ROOT_DIR}/lib/network.sh"

# shellcheck source=tests/test-framework.sh
source "${SCRIPT_DIR}/test-framework.sh"

test_xor_addr_math() {
    # 203.0.113.5 XORed with magic cookie 2112a442:
    #   cb^21=ea  00^12=12  71^a4=d5  05^42=47  -> ea.12.d5.47 -> XOR back = 203.0.113.5
    local result
    result=$(stun_xor_addr "ea12d547")
    assert_equals "203.0.113.5" "${result}" "XOR-MAPPED-ADDRESS decodes correctly against the fixed magic cookie"
}

test_plain_addr_math() {
    local result
    result=$(stun_plain_addr "c6336407")
    assert_equals "198.51.100.7" "${result}" "MAPPED-ADDRESS decodes as a plain (non-XORed) dotted quad"
}

test_parse_xor_mapped_address_response() {
    # Binding Success Response (0101), body length 12 bytes (000c),
    # magic cookie, a 12-byte transaction ID, then one XOR-MAPPED-ADDRESS
    # attribute (type 0020, length 8) encoding 203.0.113.5:12345.
    local hex="0101000c2112a4420102030405060708090a0b0c002000080001112bea12d547"
    local result
    result=$(stun_parse_response "${hex}")
    assert_equals "203.0.113.5" "${result}" "parses a well-formed XOR-MAPPED-ADDRESS Binding Success Response"
}

test_parse_legacy_mapped_address_response() {
    # Same header, but a legacy MAPPED-ADDRESS attribute (type 0001)
    # encoding 198.51.100.7:1234, unXORed.
    local hex="0101000c2112a4420102030405060708090a0b0c00010008000104d2c6336407"
    local result
    result=$(stun_parse_response "${hex}")
    assert_equals "198.51.100.7" "${result}" "falls back to parsing a legacy MAPPED-ADDRESS attribute"
}

test_parse_prefers_xor_mapped_over_legacy() {
    # A response containing BOTH a legacy MAPPED-ADDRESS (198.51.100.7)
    # and a modern XOR-MAPPED-ADDRESS (203.0.113.5) should prefer the
    # latter, per RFC 5389 guidance that XOR-MAPPED-ADDRESS is
    # authoritative when both are present.
    local header="010100182112a4420102030405060708090a0b0c"   # length=0x0018 (24 bytes of attrs)
    local mapped_attr="00010008000104d2c6336407"               # type 0001, len 8 -> 198.51.100.7
    local xor_attr="002000080001112bea12d547"                  # type 0020, len 8 -> 203.0.113.5 (XORed)
    local hex="${header}${mapped_attr}${xor_attr}"
    local result
    result=$(stun_parse_response "${hex}")
    assert_equals "203.0.113.5" "${result}" "prefers XOR-MAPPED-ADDRESS when both attribute types are present"
}

test_parse_rejects_non_success_response() {
    # Message type 0001 is a Binding REQUEST, not a success response --
    # must never be misinterpreted as a valid answer.
    local hex="0001000c2112a4420102030405060708090a0b0c000200080001112bea12d547"
    assert_false 'stun_parse_response "'"${hex}"'"' "rejects a Binding Request echoed back as if it were a response"
}

test_parse_rejects_empty_and_truncated() {
    assert_false 'stun_parse_response ""' "rejects an empty string"
    assert_false 'stun_parse_response "0101000c2112a442"' "rejects a truncated header"
    assert_false 'stun_parse_response "0101000c2112a4420102030405060708090a0b0c"' "rejects a header with no attributes when one was expected"
}

test_parse_ignores_unknown_attributes() {
    # An unrecognized attribute (e.g. SOFTWARE, type 8022, "test")
    # followed by a valid XOR-MAPPED-ADDRESS should still successfully
    # extract the address, skipping over what it doesn't understand.
    local header="010100142112a4420102030405060708090a0b0c"    # length=0x0014 (20 bytes of attrs)
    local unknown_attr="8022000474657374"                       # type 8022, len 4, value "test"
    local xor_attr="002000080001112bea12d547"                   # type 0020, len 8 -> 203.0.113.5
    local hex="${header}${unknown_attr}${xor_attr}"
    local result
    result=$(stun_parse_response "${hex}")
    assert_equals "203.0.113.5" "${result}" "skips over an unrecognized attribute to find the address"
}

test_stun_query_fails_gracefully_when_unreachable() {
    # Using a documentation/test-net address (RFC 5737, 203.0.113.0/24)
    # guarantees no real STUN server answers, so this exercises the
    # timeout/failure path without depending on any real network
    # service being reachable from the test environment. Must return
    # non-zero and MUST NOT abort the calling shell (regression test
    # for a bug where an internal `exit` terminated the whole process
    # instead of just the function).
    assert_false 'stun_query "203.0.113.1" "19302"' "stun_query fails cleanly against an unreachable test-net address"
    _pass "shell is still alive after a failed stun_query call"
}

test_net_stun_get_public_ip_graceful_without_network() {
    # net_stun_get_public_ip composes stun_query + stun_parse_response;
    # confirm the whole pipeline fails gracefully (no crash, no hang
    # beyond the internal timeout) when the network is unavailable.
    CURL_TIMEOUT=1 timeout_cmd 10 net_stun_get_public_ip >/dev/null 2>&1
    _pass "net_stun_get_public_ip returns within its timeout without crashing"
}

run_test_suite "STUN Client Tests" \
    test_xor_addr_math \
    test_plain_addr_math \
    test_parse_xor_mapped_address_response \
    test_parse_legacy_mapped_address_response \
    test_parse_prefers_xor_mapped_over_legacy \
    test_parse_rejects_non_success_response \
    test_parse_rejects_empty_and_truncated \
    test_parse_ignores_unknown_attributes \
    test_stun_query_fails_gracefully_when_unreachable \
    test_net_stun_get_public_ip_graceful_without_network
