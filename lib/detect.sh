#!/usr/bin/env bash
# lib/detect.sh
# Core detection logic: address classification, confidence scoring, and
# final status determination. This file contains no I/O of its own
# (no network calls, no printing) -- it is pure logic operating on data
# gathered by lib/network.sh and lib/traceroute.sh. This separation
# keeps the detection rules easy to unit test.

if [[ -n "${CGNAT_DETECT_LOADED:-}" ]]; then
    return 0
fi
CGNAT_DETECT_LOADED=1

# RFC 6598 shared address space, used by ISPs for Carrier Grade NAT.
readonly CGNAT_RANGE="100.64.0.0/10"

# RFC 1918 private address ranges.
readonly PRIVATE_RANGE_10="10.0.0.0/8"
readonly PRIVATE_RANGE_172="172.16.0.0/12"
readonly PRIVATE_RANGE_192="192.168.0.0/16"

# Confidence score weights. Kept as named constants so they are easy to
# tune and to reference from documentation/tests.
readonly SCORE_WAN_IN_CGNAT_RANGE=40
readonly SCORE_PRIVATE_WAN=30
readonly SCORE_WAN_NOT_PUBLIC=20
readonly SCORE_PRIVATE_TRACEROUTE_HOP=10

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

# detect_wan_matches_public <wan_ip> <public_ip> -> 0 if they are equal.
detect_wan_matches_public() {
    [[ -n "$1" && -n "$2" && "$1" == "$2" ]]
}

# detect_double_nat <wan_ip> <router_upnp_wan_ip>
# Double NAT is suspected when the router's own reported external
# (UPnP) IP is itself a private/CGNAT address, meaning there is another
# NAT device between the router and the public internet.
detect_double_nat() {
    local upnp_wan="$1"
    [[ -z "${upnp_wan}" ]] && return 1

    if detect_is_private_ipv4 "${upnp_wan}" || detect_is_cgnat_range "${upnp_wan}"; then
        return 0
    fi
    return 1
}

# detect_compute_confidence sums up weighted signals and prints the
# resulting integer score (0-100, clamped).
#
# Args (each "true"/"false"):
#   1: wan_in_cgnat_range
#   2: wan_is_private
#   3: wan_differs_from_public
#   4: traceroute_has_private_hop
detect_compute_confidence() {
    local wan_in_cgnat="$1"
    local wan_private="$2"
    local wan_differs="$3"
    local traceroute_private="$4"
    local score=0

    [[ "${wan_in_cgnat}" == "true" ]] && score=$(( score + SCORE_WAN_IN_CGNAT_RANGE ))
    [[ "${wan_private}" == "true" ]] && score=$(( score + SCORE_PRIVATE_WAN ))
    [[ "${wan_differs}" == "true" ]] && score=$(( score + SCORE_WAN_NOT_PUBLIC ))
    [[ "${traceroute_private}" == "true" ]] && score=$(( score + SCORE_PRIVATE_TRACEROUTE_HOP ))

    if (( score > 100 )); then
        score=100
    fi

    printf '%d' "${score}"
}

# detect_confidence_label <score> -> prints a human label for the score.
detect_confidence_label() {
    local score="$1"
    if (( score <= 20 )); then
        printf 'Probably Public'
    elif (( score <= 50 )); then
        printf 'Possible CGNAT'
    elif (( score <= 80 )); then
        printf 'Likely CGNAT'
    else
        printf 'Confirmed CGNAT'
    fi
}

# detect_final_status determines the overall status keyword used for
# both human output and JSON, based on gathered facts.
#
# Args:
#   1: internet_reachable   (true/false)
#   2: wan_in_cgnat_range   (true/false)
#   3: wan_is_private       (true/false)
#   4: double_nat           (true/false)
#   5: gateway_reachable    (true/false)
#
# Prints one of: PUBLIC, CGNAT, DOUBLE_NAT, NO_INTERNET, ROUTER_UNREACHABLE
detect_final_status() {
    local internet="$1"
    local cgnat_range="$2"
    local private_wan="$3"
    local double_nat="$4"
    local gateway_reachable="$5"

    if [[ "${internet}" != "true" ]]; then
        printf 'NO_INTERNET'
        return
    fi

    if [[ "${gateway_reachable}" != "true" ]]; then
        printf 'ROUTER_UNREACHABLE'
        return
    fi

    if [[ "${double_nat}" == "true" ]]; then
        printf 'DOUBLE_NAT'
        return
    fi

    if [[ "${cgnat_range}" == "true" || "${private_wan}" == "true" ]]; then
        printf 'CGNAT'
        return
    fi

    printf 'PUBLIC'
}

# detect_status_exit_code maps a status keyword to the documented exit
# code table. Reads the CGNAT_EXIT_* constants defined by the main
# entrypoint when available (single source of truth for the exit-code
# table), falling back to the documented literal values so this
# function also works when lib/detect.sh is sourced standalone (e.g.
# from the test suite).
detect_status_exit_code() {
    case "$1" in
        PUBLIC)              printf '%d' "${CGNAT_EXIT_PUBLIC:-0}" ;;
        CGNAT)                printf '%d' "${CGNAT_EXIT_CGNAT:-1}" ;;
        DOUBLE_NAT)           printf '%d' "${CGNAT_EXIT_DOUBLE_NAT:-2}" ;;
        NO_INTERNET)          printf '%d' "${CGNAT_EXIT_NO_INTERNET:-3}" ;;
        MISSING_DEP)          printf '%d' "${CGNAT_EXIT_MISSING_DEP:-4}" ;;
        ROUTER_UNREACHABLE)   printf '%d' "${CGNAT_EXIT_ROUTER_UNREACHABLE:-5}" ;;
        *)                    printf '%d' "${CGNAT_EXIT_UNKNOWN:-6}" ;;
    esac
}

# detect_recommendations builds a newline-separated list of
# recommendations based on the current findings. Callers can split on
# newline to get an array.
#
# Args:
#   1: status (PUBLIC/CGNAT/DOUBLE_NAT/...)
#   2: ipv6_available (true/false)
detect_recommendations() {
    local status="$1"
    local ipv6_available="$2"
    local recs=()

    case "${status}" in
        CGNAT)
            recs+=("Request a Public IPv4 address from your ISP")
            recs+=("Use Tailscale or another WireGuard-based mesh VPN for inbound access")
            recs+=("Use Cloudflare Tunnel to expose services without port forwarding")
            recs+=("Consider a cheap VPS with a public IP as a reverse-proxy relay")
            ;;
        DOUBLE_NAT)
            recs+=("Set your ISP-provided router to bridge mode if possible")
            recs+=("Ensure only one device on your network performs NAT")
            recs+=("Check that your router's WAN IP is not itself private or CGNAT")
            ;;
        NO_INTERNET)
            recs+=("Check your physical network connection")
            recs+=("Verify your router/modem is powered on and online")
            recs+=("Contact your ISP if the outage persists")
            ;;
        ROUTER_UNREACHABLE)
            recs+=("Verify the default gateway address is correct")
            recs+=("Check cabling/Wi-Fi connection to your router")
            ;;
        PUBLIC)
            recs+=("No action needed: you have a public, routable IPv4 address")
            ;;
    esac

    if [[ "${ipv6_available}" != "true" && "${status}" != "NO_INTERNET" ]]; then
        recs+=("Enable IPv6 if your ISP supports it; IPv6 traffic typically bypasses CGNAT entirely")
    fi

    local rec
    for rec in "${recs[@]}"; do
        printf '%s\n' "${rec}"
    done
}
