#!/usr/bin/env bash
# lib/network.sh
# Functions responsible for gathering raw network facts:
# local IP, gateway, public IPv4/IPv6, router WAN IP (via UPnP),
# and basic connectivity checks.
#
# Every function here prints its result to stdout and returns 0 on
# success, non-zero on failure/unknown. Callers should always check
# the return code rather than assuming a non-empty string.

if [[ -n "${CGNAT_NETWORK_LOADED:-}" ]]; then
    return 0
fi
CGNAT_NETWORK_LOADED=1

# List of public IP echo services used for cross-checking. Using several
# independent providers avoids a single point of failure or bias.
CGNAT_IPV4_ECHO_SERVICES=(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
)

CGNAT_IPV6_ECHO_SERVICES=(
    "https://api6.ipify.org"
    "https://v6.ident.me"
)

CURL_TIMEOUT="${CURL_TIMEOUT:-5}"

# net_get_local_ip prints the primary local IPv4 address of this machine
# (the address used for the default route).
net_get_local_ip() {
    local ip=""

    if has_cmd ip; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
    fi

    if [[ -z "${ip}" ]] && has_cmd ip; then
        ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
    fi

    if [[ -z "${ip}" ]]; then
        return 1
    fi

    printf '%s' "${ip}"
    return 0
}

# net_get_gateway prints the default IPv4 gateway.
net_get_gateway() {
    local gw=""

    if has_cmd ip; then
        gw=$(ip -4 route show default 2>/dev/null | awk '/default/{print $3; exit}')
    fi

    if [[ -z "${gw}" ]]; then
        return 1
    fi

    printf '%s' "${gw}"
    return 0
}

# net_check_internet returns 0 if basic internet connectivity is
# available (tries multiple well-known, highly-available hosts).
net_check_internet() {
    local hosts=("1.1.1.1" "8.8.8.8" "9.9.9.9")
    local host

    if has_cmd ping; then
        for host in "${hosts[@]}"; do
            if timeout_cmd 3 ping -c 1 -W 2 "${host}" >/dev/null 2>&1; then
                return 0
            fi
        done
    fi

    # Fallback: try an HTTP HEAD request via curl, in case ICMP is blocked.
    if has_cmd curl; then
        if curl -s -m "${CURL_TIMEOUT}" -o /dev/null -w '%{http_code}' https://cloudflare.com 2>/dev/null | grep -qE '^[23]'; then
            return 0
        fi
    fi

    return 1
}

# net_check_gateway_reachable returns 0 if the default gateway responds
# to ping.
net_check_gateway_reachable() {
    local gw="$1"
    [[ -z "${gw}" ]] && return 1

    if has_cmd ping; then
        timeout_cmd 3 ping -c 1 -W 2 "${gw}" >/dev/null 2>&1
        return $?
    fi

    return 1
}

# net_get_public_ipv4 queries external echo services to determine this
# network's public-facing IPv4 address. Tries multiple providers and
# returns the first valid response.
net_get_public_ipv4() {
    local service ip

    for service in "${CGNAT_IPV4_ECHO_SERVICES[@]}"; do
        ip=$(curl -s -4 -m "${CURL_TIMEOUT}" "${service}" 2>/dev/null | trim)
        if ip_is_valid_ipv4 "${ip}"; then
            printf '%s' "${ip}"
            return 0
        fi
    done

    return 1
}

# net_get_public_ipv6 queries external echo services for a public IPv6
# address. Returns 1 if IPv6 is unavailable.
net_get_public_ipv6() {
    local service ip

    for service in "${CGNAT_IPV6_ECHO_SERVICES[@]}"; do
        ip=$(curl -s -6 -m "${CURL_TIMEOUT}" "${service}" 2>/dev/null | trim)
        if [[ "${ip}" == *:* ]]; then
            printf '%s' "${ip}"
            return 0
        fi
    done

    return 1
}

# net_has_ipv6_route returns 0 if the machine has any usable IPv6 route
# at all (does not guarantee public reachability -- see
# net_get_public_ipv6 for that).
net_has_ipv6_route() {
    if has_cmd ip; then
        ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1
        return $?
    fi
    return 1
}

# net_get_wan_ip_upnp attempts to discover the router's external
# (WAN-facing) IP address using UPnP/IGD, if miniupnpc's `upnpc` binary
# is available. This is the address the router itself believes it has
# been assigned by the ISP -- useful for detecting double NAT.
net_get_wan_ip_upnp() {
    has_cmd upnpc || return 1

    local raw ip
    raw=$(timeout_cmd 5 upnpc -s 2>/dev/null)
    ip=$(printf '%s\n' "${raw}" | awk -F'= ' '/ExternalIPAddress/{print $2}' | trim)

    if ip_is_valid_ipv4 "${ip}"; then
        printf '%s' "${ip}"
        return 0
    fi

    return 1
}

# net_dns_resolves is a light sanity check using `dig` (if available) to
# confirm DNS resolution is functioning, which is a prerequisite for the
# public-IP echo lookups to work at all.
net_dns_resolves() {
    if has_cmd dig; then
        dig +short +time=2 +tries=1 myip.opendns.com @resolver1.opendns.com >/dev/null 2>&1
        return $?
    fi
    # No dig available: not fatal, just unknown.
    return 0
}
