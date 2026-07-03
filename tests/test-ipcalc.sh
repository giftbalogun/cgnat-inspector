#!/usr/bin/env bash
# tests/test-ipcalc.sh
# Unit tests for the pure-bash IP arithmetic helpers in lib/utils.sh
# (ip_is_valid_ipv4, ip_to_int, ip_in_cidr).

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=lib/colors.sh
source "${ROOT_DIR}/lib/colors.sh"
color_init true
# shellcheck source=lib/utils.sh
source "${ROOT_DIR}/lib/utils.sh"

# shellcheck source=tests/test-framework.sh
source "${SCRIPT_DIR}/test-framework.sh"

test_valid_ipv4() {
    assert_true 'ip_is_valid_ipv4 "192.168.1.1"' "192.168.1.1 should be valid"
    assert_true 'ip_is_valid_ipv4 "0.0.0.0"' "0.0.0.0 should be valid"
    assert_true 'ip_is_valid_ipv4 "255.255.255.255"' "255.255.255.255 should be valid"
}

test_invalid_ipv4() {
    assert_false 'ip_is_valid_ipv4 "256.1.1.1"' "256.1.1.1 should be invalid (octet > 255)"
    assert_false 'ip_is_valid_ipv4 "1.1.1"' "1.1.1 should be invalid (too few octets)"
    assert_false 'ip_is_valid_ipv4 "not.an.ip.addr"' "non-numeric should be invalid"
    assert_false 'ip_is_valid_ipv4 ""' "empty string should be invalid"
}

test_ip_to_int_roundtrip() {
    local val
    val=$(ip_to_int "0.0.0.1")
    assert_equals "1" "${val}" "0.0.0.1 should equal integer 1"

    val=$(ip_to_int "255.255.255.255")
    assert_equals "4294967295" "${val}" "255.255.255.255 should equal max uint32"

    val=$(ip_to_int "192.168.1.1")
    assert_equals "3232235777" "${val}" "192.168.1.1 integer conversion"
}

test_cidr_membership_rfc1918() {
    assert_true 'ip_in_cidr "192.168.1.50" "192.168.0.0/16"' "192.168.1.50 in 192.168.0.0/16"
    assert_true 'ip_in_cidr "10.5.5.5" "10.0.0.0/8"' "10.5.5.5 in 10.0.0.0/8"
    assert_true 'ip_in_cidr "172.20.0.1" "172.16.0.0/12"' "172.20.0.1 in 172.16.0.0/12"
    assert_false 'ip_in_cidr "172.32.0.1" "172.16.0.0/12"' "172.32.0.1 NOT in 172.16.0.0/12"
    assert_false 'ip_in_cidr "192.169.0.1" "192.168.0.0/16"' "192.169.0.1 NOT in 192.168.0.0/16"
}

test_cidr_membership_cgnat() {
    assert_true 'ip_in_cidr "100.64.0.1" "100.64.0.0/10"' "100.64.0.1 in CGNAT range"
    assert_true 'ip_in_cidr "100.100.0.1" "100.64.0.0/10"' "100.100.0.1 in CGNAT range"
    assert_true 'ip_in_cidr "100.127.255.254" "100.64.0.0/10"' "top of CGNAT range"
    assert_false 'ip_in_cidr "100.63.255.255" "100.64.0.0/10"' "just below CGNAT range"
    assert_false 'ip_in_cidr "100.128.0.0" "100.64.0.0/10"' "just above CGNAT range"
    assert_false 'ip_in_cidr "8.8.8.8" "100.64.0.0/10"' "public IP not in CGNAT range"
}

test_cidr_edge_bits() {
    assert_true 'ip_in_cidr "1.2.3.4" "0.0.0.0/0"' "any IP matches /0"
    assert_true 'ip_in_cidr "10.0.0.5" "10.0.0.5/32"' "exact /32 match"
    assert_false 'ip_in_cidr "10.0.0.6" "10.0.0.5/32"' "/32 mismatch"
}

run_test_suite "IP Calculation Tests" \
    test_valid_ipv4 \
    test_invalid_ipv4 \
    test_ip_to_int_roundtrip \
    test_cidr_membership_rfc1918 \
    test_cidr_membership_cgnat \
    test_cidr_edge_bits
