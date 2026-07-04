#!/usr/bin/env bash
# lib/detect.sh
# Core detection logic: address classification, the evidence-based
# scoring engine, and final status/exit-code/recommendation
# determination. This file contains no I/O of its own (no network
# calls, no printing) -- it is pure logic operating on facts gathered
# by lib/network.sh and lib/traceroute.sh. This separation keeps the
# detection rules easy to unit test independently of "Reporting"
# (lib/output.sh, lib/json.sh), which only renders whatever this file
# produces.
#
# Design notes (why evidence-based, not a single yes/no check):
#   A single signal (e.g. "WAN looks private") is not proof of CGNAT --
#   it could also mean the router simply hasn't obtained a lease yet,
#   or UPnP is misreporting. Instead, several independent signals are
#   each given a weight, summed into a 0-100 confidence score, and only
#   mapped to a strong conclusion ("CGNAT Detected") once several of
#   them agree. See docs/how-it-works.md for the full rationale and
#   docs/api.md for the JSON evidence schema.

if [[ -n "${CGNAT_DETECT_LOADED:-}" ]]; then
    return 0
fi
CGNAT_DETECT_LOADED=1

# ---------------------------------------------------------------------------
# Address classification
# ---------------------------------------------------------------------------

# RFC 6598 shared address space, used by ISPs for Carrier Grade NAT.
readonly CGNAT_RANGE="100.64.0.0/10"

# RFC 1918 private address ranges.
readonly PRIVATE_RANGE_10="10.0.0.0/8"
readonly PRIVATE_RANGE_172="172.16.0.0/12"
readonly PRIVATE_RANGE_192="192.168.0.0/16"

# detect_is_cgnat_range <ip> -> 0 if ip is within 100.64.0.0/10.
detect_is_cgnat_range() {
    ip_in_cidr "$1" "${CGNAT_RANGE}"
}

# detect_is_private_ipv4 <ip> -> 0 if ip is within any RFC1918 range.
detect_is_private_ipv4() {
    local ip="$1"
    ip_in_cidr "${ip}" "${PRIVATE_RANGE_10}" && return 0
    ip_in_cidr "${ip}" "${PRIVATE_RANGE_172}" && return 0
    ip_in_cidr "${ip}" "${PRIVATE_RANGE_192}" && return 0
    return 1
}

# detect_is_loopback_or_linklocal <ip> -> 0 if ip is loopback (127/8) or
# link-local (169.254/16). Useful as a sanity guard.
detect_is_loopback_or_linklocal() {
    local ip="$1"
    ip_in_cidr "${ip}" "127.0.0.0/8" && return 0
    ip_in_cidr "${ip}" "169.254.0.0/16" && return 0
    return 1
}

# detect_is_non_public_ipv4 <ip> -> 0 if ip is RFC1918 private OR in the
# RFC6598 CGNAT range. This is the combined "not a real public address"
# check used when classifying a router's WAN address or a traceroute
# hop -- for those purposes, RFC1918 and CGNAT space are both signs of
# an extra NAT layer, so they're treated as one category.
detect_is_non_public_ipv4() {
    local ip="$1"
    detect_is_private_ipv4 "${ip}" && return 0
    detect_is_cgnat_range "${ip}" && return 0
    return 1
}

# detect_addresses_match <a> <b> -> 0 if both are non-empty and equal.
detect_addresses_match() {
    [[ -n "$1" && -n "$2" && "$1" == "$2" ]]
}

# ---------------------------------------------------------------------------
# Scoring engine
# ---------------------------------------------------------------------------
# Each named signal contributes points only when it is both KNOWN and
# TRUE (an absent/unknown signal never scores as if it were positive
# evidence of CGNAT -- it scores its own smaller "uncertainty" weight
# instead, so missing data nudges the result toward "Inconclusive"
# rather than toward "CGNAT Detected").

readonly SCORE_PRIVATE_ROUTER_WAN=35     # Router WAN confirmed private/CGNAT
readonly SCORE_ROUTER_WAN_UNKNOWN=15     # Router WAN could not be determined
readonly SCORE_PUBLIC_DIFFERS=20         # Public IP != Router WAN (both known)
readonly SCORE_PUBLIC_UNAVAILABLE=10     # Public IPv4 could not be determined
readonly SCORE_TRACEROUTE_BACKBONE=20    # Multiple private/CGNAT hops on path
readonly SCORE_STUN_MISMATCH=15          # STUN-observed IP != HTTP-observed IP
readonly SCORE_NO_IPV6=5                 # No public IPv6 available
readonly SCORE_MULTIPLE_INDICATORS=10    # Bonus: >=2 strong signals agree

# Status thresholds (percentage of the 0-100 confidence score).
readonly STATUS_THRESHOLD_POSSIBLE=40
readonly STATUS_THRESHOLD_DETECTED=80

# detect_compute_score sums weighted signals into a 0-100 confidence
# score. All boolean arguments are the literal strings "true"/"false".
#
# Args:
#   1  router_wan_known           -- was a router WAN address obtained?
#   2  router_wan_nonpublic       -- (only meaningful if #1 is true) is it private/CGNAT?
#   3  public_ip_known            -- was a public IPv4 obtained?
#   4  public_differs             -- (only meaningful if #1 and #3 are true) does it differ from router WAN?
#   5  traceroute_backbone_private -- did traceroute show >=2 private/CGNAT hops beyond the gateway?
#   6  stun_known                 -- was a STUN-observed address obtained?
#   7  stun_mismatch              -- (only meaningful if #6 is true) does it differ from the HTTP-observed public IP?
#   8  ipv6_available             -- is public IPv6 available?
#
# Prints the integer score (0-100) to stdout.
detect_compute_score() {
    local router_wan_known="$1"
    local router_wan_nonpublic="$2"
    local public_ip_known="$3"
    local public_differs="$4"
    local traceroute_backbone_private="$5"
    local stun_known="$6"
    local stun_mismatch="$7"
    local ipv6_available="$8"

    local score=0
    local strong_signals=0

    if [[ "${router_wan_known}" == "true" ]]; then
        if [[ "${router_wan_nonpublic}" == "true" ]]; then
            score=$(( score + SCORE_PRIVATE_ROUTER_WAN ))
            strong_signals=$(( strong_signals + 1 ))
        fi
    else
        score=$(( score + SCORE_ROUTER_WAN_UNKNOWN ))
    fi

    if [[ "${public_ip_known}" == "true" ]]; then
        if [[ "${router_wan_known}" == "true" && "${public_differs}" == "true" ]]; then
            score=$(( score + SCORE_PUBLIC_DIFFERS ))
            strong_signals=$(( strong_signals + 1 ))
        fi
    else
        score=$(( score + SCORE_PUBLIC_UNAVAILABLE ))
    fi

    if [[ "${traceroute_backbone_private}" == "true" ]]; then
        score=$(( score + SCORE_TRACEROUTE_BACKBONE ))
        strong_signals=$(( strong_signals + 1 ))
    fi

    if [[ "${stun_known}" == "true" && "${stun_mismatch}" == "true" ]]; then
        score=$(( score + SCORE_STUN_MISMATCH ))
        strong_signals=$(( strong_signals + 1 ))
    fi

    if [[ "${ipv6_available}" != "true" ]]; then
        score=$(( score + SCORE_NO_IPV6 ))
    fi

    if (( strong_signals >= 2 )); then
        score=$(( score + SCORE_MULTIPLE_INDICATORS ))
    fi

    if (( score > 100 )); then
        score=100
    fi

    printf '%d' "${score}"
}

# detect_status_from_score <score> -> prints INCONCLUSIVE, POSSIBLE_CGNAT,
# or CGNAT_DETECTED based on the documented thresholds.
detect_status_from_score() {
    local score="$1"
    if (( score >= STATUS_THRESHOLD_DETECTED )); then
        printf 'CGNAT_DETECTED'
    elif (( score >= STATUS_THRESHOLD_POSSIBLE )); then
        printf 'POSSIBLE_CGNAT'
    else
        printf 'INCONCLUSIVE'
    fi
}

# detect_final_status determines the overall status keyword, in
# priority order: connectivity problems first (they make everything
# else unknowable), then a definitive positive confirmation, then the
# evidence-based score.
#
# Args:
#   1  internet_ok      -- true/false
#   2  gateway_ok        -- true/false
#   3  dns_ok             -- true/false
#   4  definitive_public  -- true/false (router WAN known + public + matches public IP)
#   5  score              -- integer 0-100 (only consulted if none of the above short-circuit)
#
# Prints one of: PUBLIC, CGNAT_DETECTED, POSSIBLE_CGNAT, INCONCLUSIVE,
# NO_INTERNET, DNS_FAILURE
detect_final_status() {
    local internet_ok="$1"
    local gateway_ok="$2"
    local dns_ok="$3"
    local definitive_public="$4"
    local score="$5"

    if [[ "${internet_ok}" != "true" || "${gateway_ok}" != "true" ]]; then
        printf 'NO_INTERNET'
        return
    fi

    if [[ "${dns_ok}" != "true" ]]; then
        printf 'DNS_FAILURE'
        return
    fi

    if [[ "${definitive_public}" == "true" ]]; then
        printf 'PUBLIC'
        return
    fi

    detect_status_from_score "${score}"
}

# detect_status_exit_code maps a status keyword to the documented exit
# code table:
#   0 Public IPv4 confirmed (No CGNAT)   4 Internet unreachable
#   1 CGNAT Detected                      5 DNS failure
#   2 Possible CGNAT                      6 Internal error
#   3 Inconclusive
detect_status_exit_code() {
    case "$1" in
        PUBLIC)            printf '0' ;;
        CGNAT_DETECTED)    printf '1' ;;
        POSSIBLE_CGNAT)    printf '2' ;;
        INCONCLUSIVE)      printf '3' ;;
        NO_INTERNET)       printf '4' ;;
        DNS_FAILURE)       printf '5' ;;
        *)                 printf '6' ;; # INTERNAL_ERROR and any unknown status
    esac
}

# detect_conclusion <status> -> prints a single explanatory sentence
# for the given status, used in the "Conclusion" section of both the
# human-readable report and the JSON output.
detect_conclusion() {
    case "$1" in
        PUBLIC)
            printf 'Public IPv4 connectivity has been confirmed: the router WAN address matches the publicly observed address, and no evidence of Carrier-Grade NAT was found.'
            ;;
        CGNAT_DETECTED)
            printf 'The available evidence strongly indicates this connection is behind Carrier-Grade NAT.'
            ;;
        POSSIBLE_CGNAT)
            printf 'The available evidence suggests the connection may be behind Carrier-Grade NAT. Additional information (such as the router WAN address or a confirmed public IPv4) is required before making a definitive determination.'
            ;;
        INCONCLUSIVE)
            printf 'There is not enough evidence to determine whether this connection is behind Carrier-Grade NAT. Enabling UPnP on your router, installing traceroute, or checking connectivity to public IP lookup services may allow a more confident result.'
            ;;
        NO_INTERNET)
            printf 'No internet connectivity was detected (or the default gateway is unreachable), so CGNAT status cannot be determined.'
            ;;
        DNS_FAILURE)
            printf 'The network appears reachable, but DNS resolution is failing, so CGNAT status cannot be determined.'
            ;;
        *)
            printf 'An internal error prevented CGNAT Inspector from completing its checks.'
            ;;
    esac
}

# detect_recommendations builds a newline-separated list of
# recommendations based on the current status. Callers can split on
# newline to get an array.
#
# Args:
#   1: status
#   2: ipv6_available (true/false)
detect_recommendations() {
    local status="$1"
    local ipv6_available="$2"
    local recs=()

    case "${status}" in
        CGNAT_DETECTED|POSSIBLE_CGNAT)
            recs+=("Request a Public IPv4 address from your ISP")
            recs+=("Use Tailscale or another WireGuard-based mesh VPN for inbound access")
            recs+=("Use Cloudflare Tunnel to expose services without port forwarding")
            recs+=("Use a VPS reverse proxy as a relay for inbound connections")
            ;;
        INCONCLUSIVE)
            recs+=("Install miniupnpc (upnpc) and enable UPnP on your router so the WAN address can be determined")
            recs+=("Install traceroute for additional path-based evidence")
            recs+=("Re-run with --verbose to see which individual checks failed")
            ;;
        NO_INTERNET)
            recs+=("Check your physical network connection")
            recs+=("Verify your router/modem is powered on and online")
            recs+=("Contact your ISP if the outage persists")
            ;;
        DNS_FAILURE)
            recs+=("Check your configured DNS servers (e.g. /etc/resolv.conf)")
            recs+=("Try a public resolver such as 1.1.1.1 or 8.8.8.8")
            recs+=("Confirm your router itself can resolve domain names")
            ;;
        PUBLIC)
            recs+=("No action needed: you have a confirmed public, routable IPv4 address")
            ;;
        *)
            recs+=("Re-run with --debug and check that required dependencies (bash, curl, ip, awk, grep, sed) are installed")
            ;;
    esac

    if [[ "${ipv6_available}" != "true" && "${status}" != "NO_INTERNET" && "${status}" != "DNS_FAILURE" ]]; then
        recs+=("Enable IPv6 if your ISP supports it; IPv6 traffic typically bypasses CGNAT entirely")
    fi

    local rec
    for rec in "${recs[@]}"; do
        printf '%s\n' "${rec}"
    done
}

# detect_build_evidence prints the human-readable evidence checklist,
# one line per item as "description<TAB>true|false", to stdout. Lines
# are only included when the underlying check was actually performed
# (e.g. "Public IPv4 differs from Router WAN" is omitted entirely if
# either address is unknown, rather than being shown as a misleading
# "false"). This is the single source of truth consumed by both
# lib/output.sh (human report) and lib/json.sh ("evidence" array), so
# the two presentations can never drift out of sync.
#
# Args (all booleans as literal "true"/"false" strings unless noted):
#   1  internet_ok
#   2  gateway_ok
#   3  dns_ok
#   4  router_wan_known
#   5  router_wan_nonpublic       (ignored unless #4 is true)
#   6  public_ip_known
#   7  comparison_possible        (true only if #4 and #6 are both true)
#   8  public_differs             (ignored unless #7 is true)
#   9  traceroute_ran             (true if traceroute produced any hops at all)
#   10 traceroute_backbone_private (ignored unless #9 is true)
#   11 stun_known
#   12 stun_mismatch              (ignored unless #11 is true)
#   13 ipv6_available
#   14 multiple_indicators
detect_build_evidence() {
    local internet_ok="$1"
    local gateway_ok="$2"
    local dns_ok="$3"
    local router_wan_known="$4"
    local router_wan_nonpublic="$5"
    local public_ip_known="$6"
    local comparison_possible="$7"
    local public_differs="$8"
    local traceroute_ran="$9"
    local traceroute_backbone_private="${10}"
    local stun_known="${11}"
    local stun_mismatch="${12}"
    local ipv6_available="${13}"
    local multiple_indicators="${14}"

    printf 'Internet connectivity confirmed\t%s\n' "${internet_ok}"
    printf 'Default gateway reachable\t%s\n' "${gateway_ok}"
    printf 'DNS resolution working\t%s\n' "${dns_ok}"
    printf 'Router WAN address obtained\t%s\n' "${router_wan_known}"

    if [[ "${router_wan_known}" == "true" ]]; then
        printf 'Router WAN address is private or CGNAT range\t%s\n' "${router_wan_nonpublic}"
    fi

    printf 'Public IPv4 address obtained\t%s\n' "${public_ip_known}"

    if [[ "${comparison_possible}" == "true" ]]; then
        printf 'Public IPv4 differs from Router WAN\t%s\n' "${public_differs}"
    fi

    if [[ "${traceroute_ran}" == "true" ]]; then
        printf 'Traceroute shows a private/CGNAT backbone\t%s\n' "${traceroute_backbone_private}"
    fi

    if [[ "${stun_known}" == "true" ]]; then
        printf 'STUN-observed address differs from HTTP-observed address\t%s\n' "${stun_mismatch}"
    fi

    printf 'Public IPv6 available\t%s\n' "${ipv6_available}"
    printf 'Multiple independent indicators corroborate\t%s\n' "${multiple_indicators}"
}
