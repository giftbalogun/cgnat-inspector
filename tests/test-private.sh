#!/usr/bin/env bash
# tests/test-private.sh
# Unit tests for lib/detect.sh classification functions: private IPv4
# detection, CGNAT range detection, double-NAT detection, confidence
# scoring, and final status determination.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=lib/colors.sh
source "${ROOT_DIR}/lib/colors.sh"
color_init true
# shellcheck source=lib/utils.sh
source "${ROOT_DIR}/lib/utils.sh"
# shellcheck source=lib/detect.sh
source "${ROOT_DIR}/lib/detect.sh"

# shellcheck source=tests/test-framework.sh
source "${SCRIPT_DIR}/test-framework.sh"

test_detect_private_ipv4() {
    assert_true 'detect_is_private_ipv4 "192.168.1.1"' "192.168.1.1 is RFC1918 private"
    assert_true 'detect_is_private_ipv4 "10.0.0.1"' "10.0.0.1 is RFC1918 private"
    assert_true 'detect_is_private_ipv4 "172.31.255.255"' "172.31.255.255 is RFC1918 private"
    assert_false 'detect_is_private_ipv4 "8.8.8.8"' "8.8.8.8 is not private"
    assert_false 'detect_is_private_ipv4 "100.91.11.5"' "CGNAT address is not RFC1918 private"
}

test_detect_cgnat_range() {
    assert_true 'detect_is_cgnat_range "100.64.0.1"' "100.64.0.1 is CGNAT range"
    assert_true 'detect_is_cgnat_range "100.91.11.5"' "100.91.11.5 is CGNAT range"
    assert_false 'detect_is_cgnat_range "192.168.1.1"' "RFC1918 address is not CGNAT range"
    assert_false 'detect_is_cgnat_range "102.89.44.10"' "public address is not CGNAT range"
}

test_wan_matches_public() {
    assert_true 'detect_wan_matches_public "1.2.3.4" "1.2.3.4"' "identical IPs match"
    assert_false 'detect_wan_matches_public "1.2.3.4" "1.2.3.5"' "different IPs do not match"
    assert_false 'detect_wan_matches_public "" "1.2.3.5"' "empty WAN never matches"
}

test_double_nat() {
    assert_true 'detect_double_nat "192.168.1.1"' "private UPnP WAN implies double NAT"
    assert_true 'detect_double_nat "100.64.1.1"' "CGNAT UPnP WAN implies double NAT"
    assert_false 'detect_double_nat "102.89.44.10"' "public UPnP WAN implies no double NAT"
    assert_false 'detect_double_nat ""' "empty UPnP WAN cannot confirm double NAT"
}

test_confidence_scoring() {
    local score
    score=$(detect_compute_confidence "true" "true" "true" "true")
    assert_equals "100" "${score}" "all signals true sums to 100 (40+30+20+10)"

    score=$(detect_compute_confidence "false" "false" "false" "false")
    assert_equals "0" "${score}" "no signals sums to 0"

    score=$(detect_compute_confidence "true" "false" "false" "false")
    assert_equals "40" "${score}" "CGNAT range alone scores 40"

    score=$(detect_compute_confidence "false" "true" "false" "false")
    assert_equals "30" "${score}" "private WAN alone scores 30"
}

test_confidence_labels() {
    assert_equals "Probably Public" "$(detect_confidence_label 0)" "score 0 label"
    assert_equals "Probably Public" "$(detect_confidence_label 20)" "score 20 label"
    assert_equals "Possible CGNAT" "$(detect_confidence_label 21)" "score 21 label"
    assert_equals "Possible CGNAT" "$(detect_confidence_label 50)" "score 50 label"
    assert_equals "Likely CGNAT" "$(detect_confidence_label 51)" "score 51 label"
    assert_equals "Likely CGNAT" "$(detect_confidence_label 80)" "score 80 label"
    assert_equals "Confirmed CGNAT" "$(detect_confidence_label 81)" "score 81 label"
    assert_equals "Confirmed CGNAT" "$(detect_confidence_label 100)" "score 100 label"
}

test_final_status() {
    local status
    status=$(detect_final_status "false" "false" "false" "false" "true")
    assert_equals "NO_INTERNET" "${status}" "no internet overrides everything"

    status=$(detect_final_status "true" "false" "false" "false" "false")
    assert_equals "ROUTER_UNREACHABLE" "${status}" "unreachable gateway"

    status=$(detect_final_status "true" "true" "false" "false" "true")
    assert_equals "CGNAT" "${status}" "CGNAT range triggers CGNAT status"

    status=$(detect_final_status "true" "false" "true" "false" "true")
    assert_equals "CGNAT" "${status}" "private WAN triggers CGNAT status"

    status=$(detect_final_status "true" "true" "false" "true" "true")
    assert_equals "DOUBLE_NAT" "${status}" "double NAT takes priority over plain CGNAT"

    status=$(detect_final_status "true" "false" "false" "false" "true")
    assert_equals "PUBLIC" "${status}" "no negative signals means PUBLIC"
}

test_status_exit_codes() {
    assert_equals "0" "$(detect_status_exit_code "PUBLIC")" "PUBLIC -> 0"
    assert_equals "1" "$(detect_status_exit_code "CGNAT")" "CGNAT -> 1"
    assert_equals "2" "$(detect_status_exit_code "DOUBLE_NAT")" "DOUBLE_NAT -> 2"
    assert_equals "3" "$(detect_status_exit_code "NO_INTERNET")" "NO_INTERNET -> 3"
    assert_equals "4" "$(detect_status_exit_code "MISSING_DEP")" "MISSING_DEP -> 4"
    assert_equals "5" "$(detect_status_exit_code "ROUTER_UNREACHABLE")" "ROUTER_UNREACHABLE -> 5"
    assert_equals "6" "$(detect_status_exit_code "SOMETHING_ELSE")" "unknown status -> 6"
}

run_test_suite "Private / CGNAT Detection Tests" \
    test_detect_private_ipv4 \
    test_detect_cgnat_range \
    test_wan_matches_public \
    test_double_nat \
    test_confidence_scoring \
    test_confidence_labels \
    test_final_status \
    test_status_exit_codes
