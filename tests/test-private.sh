#!/usr/bin/env bash
# tests/test-private.sh
# Unit tests for lib/detect.sh: address classification, the
# evidence-based scoring engine, status determination, exit codes, and
# recommendations/conclusions.

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

test_detect_is_non_public_ipv4() {
    assert_true 'detect_is_non_public_ipv4 "192.168.1.1"' "RFC1918 counts as non-public"
    assert_true 'detect_is_non_public_ipv4 "100.91.11.5"' "CGNAT range counts as non-public"
    assert_false 'detect_is_non_public_ipv4 "102.89.44.10"' "genuine public address is not non-public"
}

test_addresses_match() {
    assert_true 'detect_addresses_match "1.2.3.4" "1.2.3.4"' "identical IPs match"
    assert_false 'detect_addresses_match "1.2.3.4" "1.2.3.5"' "different IPs do not match"
    assert_false 'detect_addresses_match "" "1.2.3.5"' "empty address never matches"
}

# ---------------------------------------------------------------------------
# Scoring engine: true positives, false positives, and edge cases
# ---------------------------------------------------------------------------

test_score_true_positive_cgnat() {
    # Router WAN confirmed private/CGNAT, public IP differs, traceroute
    # backbone private, STUN mismatches, no IPv6: every strong signal
    # agrees -- this should land solidly in CGNAT_DETECTED territory.
    local score
    score=$(detect_compute_score "true" "true" "true" "true" "true" "true" "true" "false")
    # 35 (private WAN) + 20 (public differs) + 20 (traceroute) + 15 (stun)
    # + 5 (no ipv6) + 10 (multiple indicators bonus, capped at 100)
    assert_equals "100" "${score}" "all strong signals true scores at or above 80 (capped at 100)"

    local status
    status=$(detect_status_from_score "${score}")
    assert_equals "CGNAT_DETECTED" "${status}" "full evidence maps to CGNAT_DETECTED"
}

test_score_true_negative_public() {
    # Router WAN known and public, matches public IP, traceroute clean,
    # STUN agrees, IPv6 available: no evidence of CGNAT anywhere.
    local score
    score=$(detect_compute_score "true" "false" "true" "false" "false" "true" "false" "true")
    assert_equals "0" "${score}" "no negative signals scores 0"

    local status
    status=$(detect_status_from_score "${score}")
    assert_equals "INCONCLUSIVE" "${status}" "a raw score of 0 falls in the lowest band (main script overrides to PUBLIC via definitive_public)"
}

test_score_false_positive_guard_missing_data() {
    # This is the key "avoid false positives" case: we simply don't
    # know the router WAN or the public IP (e.g. UPnP disabled, ISP
    # blocking lookup services) but there is NO actual evidence of
    # CGNAT. This must NOT score high enough to claim CGNAT_DETECTED --
    # missing data should produce uncertainty (Inconclusive), not a
    # false accusation.
    local score
    score=$(detect_compute_score "false" "false" "false" "false" "false" "false" "false" "true")
    # 15 (WAN unknown) + 10 (public unavailable) = 25
    assert_equals "25" "${score}" "missing data alone scores only uncertainty weight"

    local status
    status=$(detect_status_from_score "${score}")
    assert_equals "INCONCLUSIVE" "${status}" "missing data alone must never reach Possible/Detected"
}

test_score_single_weak_signal_is_not_detected() {
    # A single traceroute-only signal (the old tool's biggest false
    # positive risk) must not, by itself, reach CGNAT_DETECTED.
    local score
    score=$(detect_compute_score "false" "false" "false" "false" "true" "false" "false" "true")
    # 15 (WAN unknown) + 10 (public unavailable) + 20 (traceroute) = 45
    assert_equals "45" "${score}" "traceroute plus missing data alone scores in the Possible band, not Detected"

    local status
    status=$(detect_status_from_score "${score}")
    assert_equals "POSSIBLE_CGNAT" "${status}" "a single strong signal plus uncertainty is Possible, not Detected"
}

test_score_private_wan_alone() {
    local score
    score=$(detect_compute_score "true" "true" "false" "false" "false" "false" "false" "true")
    # 35 (private WAN) + 10 (public unavailable) = 45
    assert_equals "45" "${score}" "confirmed private WAN alone (with public IP unavailable) scores 45"
}

test_score_public_wan_known_edge_case() {
    # Router WAN is known and public, but public IP lookup failed.
    # Should not accumulate the "WAN unknown" uncertainty weight since
    # WAN actually IS known.
    local score
    score=$(detect_compute_score "true" "false" "false" "false" "false" "false" "false" "true")
    assert_equals "10" "${score}" "known-public WAN with unavailable public IP scores only the public-unavailable weight"
}

test_score_multiple_indicators_bonus_requires_two() {
    local score
    # Exactly one strong signal (traceroute) -- no bonus.
    score=$(detect_compute_score "false" "false" "false" "false" "true" "false" "false" "true")
    assert_equals "45" "${score}" "one strong signal: no multiple-indicators bonus (15+10+20)"

    # Two strong signals: private WAN + traceroute -- bonus applies.
    score=$(detect_compute_score "true" "true" "false" "false" "true" "false" "false" "true")
    # 35 + 10 (public unavailable) + 20 (traceroute) + 10 (bonus) = 75
    assert_equals "75" "${score}" "two strong signals trigger the +10 multiple-indicators bonus"
}

test_score_caps_at_100() {
    local score
    score=$(detect_compute_score "true" "true" "true" "true" "true" "true" "true" "false")
    assert_true '(( '"${score}"' <= 100 ))' "score never exceeds 100"
}

test_status_thresholds() {
    assert_equals "INCONCLUSIVE" "$(detect_status_from_score 0)" "score 0 -> Inconclusive"
    assert_equals "INCONCLUSIVE" "$(detect_status_from_score 39)" "score 39 -> Inconclusive"
    assert_equals "POSSIBLE_CGNAT" "$(detect_status_from_score 40)" "score 40 -> Possible CGNAT"
    assert_equals "POSSIBLE_CGNAT" "$(detect_status_from_score 79)" "score 79 -> Possible CGNAT"
    assert_equals "CGNAT_DETECTED" "$(detect_status_from_score 80)" "score 80 -> CGNAT Detected"
    assert_equals "CGNAT_DETECTED" "$(detect_status_from_score 100)" "score 100 -> CGNAT Detected"
}

# ---------------------------------------------------------------------------
# Final status determination (connectivity precedence + definitive PUBLIC)
# ---------------------------------------------------------------------------

test_final_status_connectivity_precedence() {
    local status
    status=$(detect_final_status "false" "false" "false" "false" "90")
    assert_equals "NO_INTERNET" "${status}" "no internet overrides even a high score"

    status=$(detect_final_status "true" "false" "false" "false" "90")
    assert_equals "NO_INTERNET" "${status}" "unreachable gateway also maps to NO_INTERNET"

    status=$(detect_final_status "true" "true" "false" "false" "10")
    assert_equals "DNS_FAILURE" "${status}" "broken DNS with working connectivity is a distinct status"
}

test_final_status_definitive_public() {
    local status
    status=$(detect_final_status "true" "true" "true" "true" "25")
    assert_equals "PUBLIC" "${status}" "definitive_public short-circuits straight to PUBLIC regardless of leftover score"
}

test_final_status_score_based() {
    local status
    status=$(detect_final_status "true" "true" "true" "false" "10")
    assert_equals "INCONCLUSIVE" "${status}" "low score with no definitive public confirmation is Inconclusive"

    status=$(detect_final_status "true" "true" "true" "false" "55")
    assert_equals "POSSIBLE_CGNAT" "${status}" "mid score maps to Possible CGNAT"

    status=$(detect_final_status "true" "true" "true" "false" "85")
    assert_equals "CGNAT_DETECTED" "${status}" "high score maps to CGNAT Detected"
}

test_status_exit_codes() {
    assert_equals "0" "$(detect_status_exit_code "PUBLIC")" "PUBLIC -> 0"
    assert_equals "1" "$(detect_status_exit_code "CGNAT_DETECTED")" "CGNAT_DETECTED -> 1"
    assert_equals "2" "$(detect_status_exit_code "POSSIBLE_CGNAT")" "POSSIBLE_CGNAT -> 2"
    assert_equals "3" "$(detect_status_exit_code "INCONCLUSIVE")" "INCONCLUSIVE -> 3"
    assert_equals "4" "$(detect_status_exit_code "NO_INTERNET")" "NO_INTERNET -> 4"
    assert_equals "5" "$(detect_status_exit_code "DNS_FAILURE")" "DNS_FAILURE -> 5"
    assert_equals "6" "$(detect_status_exit_code "INTERNAL_ERROR")" "INTERNAL_ERROR -> 6"
    assert_equals "6" "$(detect_status_exit_code "SOMETHING_UNEXPECTED")" "unknown status also -> 6 (fail safe)"
}

# ---------------------------------------------------------------------------
# Evidence checklist construction
# ---------------------------------------------------------------------------

test_build_evidence_omits_unknown_comparisons() {
    local lines
    lines=$(detect_build_evidence "true" "true" "true" "false" "false" "false" "false" "false" "false" "false" "false" "false" "true" "false")
    assert_false 'printf "%s" "'"${lines}"'" | grep -q "Router WAN address is private"' \
        "evidence omits the private/CGNAT sub-line entirely when router WAN is unknown"
    assert_false 'printf "%s" "'"${lines}"'" | grep -q "differs from Router WAN"' \
        "evidence omits the WAN-vs-public comparison line when comparison was not possible"
    assert_true 'printf "%s" "'"${lines}"'" | grep -q "Router WAN address obtained"' \
        "evidence always includes whether the router WAN was obtained"
}

test_build_evidence_includes_known_comparisons() {
    local lines
    lines=$(detect_build_evidence "true" "true" "true" "true" "true" "true" "true" "true" "true" "true" "true" "true" "false" "true")
    assert_true 'printf "%s" "'"${lines}"'" | grep -q "Router WAN address is private or CGNAT range"' \
        "evidence includes the private/CGNAT line when router WAN is known"
    assert_true 'printf "%s" "'"${lines}"'" | grep -q "differs from Router WAN"' \
        "evidence includes the WAN-vs-public comparison when both are known"
    assert_true 'printf "%s" "'"${lines}"'" | grep -q "STUN-observed address differs"' \
        "evidence includes the STUN comparison line when STUN succeeded"
}

run_test_suite "Evidence-Based Detection Tests" \
    test_detect_private_ipv4 \
    test_detect_cgnat_range \
    test_detect_is_non_public_ipv4 \
    test_addresses_match \
    test_score_true_positive_cgnat \
    test_score_true_negative_public \
    test_score_false_positive_guard_missing_data \
    test_score_single_weak_signal_is_not_detected \
    test_score_private_wan_alone \
    test_score_public_wan_known_edge_case \
    test_score_multiple_indicators_bonus_requires_two \
    test_score_caps_at_100 \
    test_status_thresholds \
    test_final_status_connectivity_precedence \
    test_final_status_definitive_public \
    test_final_status_score_based \
    test_status_exit_codes \
    test_build_evidence_omits_unknown_comparisons \
    test_build_evidence_includes_known_comparisons
