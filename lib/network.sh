#!/usr/bin/env bash
# lib/network.sh
# Functions responsible for gathering raw network facts: local (LAN) IP,
# gateway, public IPv4/IPv6, the router's actual WAN IP (via UPnP only
# -- never fabricated from the local interface), STUN-based public
# address discovery, and basic connectivity/DNS checks.
#
# Every function here prints its result to stdout and returns 0 on
# success, non-zero on failure/unknown. Callers should always check
# the return code rather than assuming a non-empty string.

if [[ -n "${CGNAT_NETWORK_LOADED:-}" ]]; then
    return 0
fi
CGNAT_NETWORK_LOADED=1

# List of public IP echo services used for cross-checking, tried in
# order until one succeeds. Using several independent providers avoids
# a single point of failure or a single provider's bias/outage
# producing a false "Unavailable" result.
CGNAT_IPV4_ECHO_SERVICES=(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
    "https://checkip.amazonaws.com"
    "https://ipv4.icanhazip.com"
)

CGNAT_IPV6_ECHO_SERVICES=(
    "https://api6.ipify.org"
    "https://v6.ident.me"
)

CURL_TIMEOUT="${CURL_TIMEOUT:-5}"
CGNAT_IPV4_ECHO_RETRIES="${CGNAT_IPV4_ECHO_RETRIES:-2}"

# STUN magic cookie, fixed by RFC 5389.
readonly STUN_MAGIC_COOKIE="2112a442"

# net_get_local_ip prints the primary LAN-side IPv4 address of this
# machine (the address used for the default route). This is NEVER to
# be reported as, or confused with, the router's WAN address -- see
# net_get_router_wan_ip for that.
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

# net_dns_resolves returns 0 if DNS resolution appears to be working,
# 1 if it is clearly broken. Distinct from net_check_internet: it's
# possible to have raw IP connectivity (ICMP/TCP to a literal address)
# while DNS itself is misconfigured or unreachable, which CGNAT
# Inspector reports as a distinct DNS_FAILURE status/exit code rather
# than lumping it in with "no internet".
net_dns_resolves() {
    local host="cloudflare.com"

    if has_cmd getent; then
        getent hosts "${host}" >/dev/null 2>&1
        return $?
    fi

    if has_cmd dig; then
        local result
        result=$(dig +short +time=2 +tries=1 "${host}" 2>/dev/null)
        [[ -n "${result}" ]]
        return $?
    fi

    if has_cmd curl; then
        # No resolver introspection tool is available; fall back to a
        # full HTTPS request, which requires DNS resolution to succeed.
        curl -s -o /dev/null -m "${CURL_TIMEOUT}" "https://${host}"
        return $?
    fi

    # No way to test DNS at all -- don't report a false failure.
    return 0
}

# net_get_public_ipv4 queries external echo services to determine this
# network's public-facing IPv4 address. Tries each provider up to
# CGNAT_IPV4_ECHO_RETRIES times before moving to the next, and returns
# the first valid response. Returns 1 (caller should report
# "Unavailable", not "Unknown") if every provider fails.
net_get_public_ipv4() {
    local service ip attempt

    for service in "${CGNAT_IPV4_ECHO_SERVICES[@]}"; do
        for (( attempt = 1; attempt <= CGNAT_IPV4_ECHO_RETRIES; attempt++ )); do
            ip=$(curl -s -4 -m "${CURL_TIMEOUT}" "${service}" 2>/dev/null | trim)
            if ip_is_valid_ipv4 "${ip}"; then
                printf '%s' "${ip}"
                return 0
            fi
        done
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

# net_get_router_wan_ip attempts to discover the router's real
# external (WAN-facing) IP address using UPnP/IGD, via miniupnpc's
# `upnpc` binary. This is the ONLY source CGNAT Inspector trusts for
# "Router WAN" -- unlike earlier versions, it never falls back to
# reporting the local LAN interface address as if it were the WAN
# address. If UPnP is unavailable or doesn't respond, callers must
# display "Unknown", not a guessed value.
net_get_router_wan_ip() {
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

# net_dns_myip_sanity_check is a light DNS sanity check using `dig`
# (if available). Retained as an optional supplementary probe; not
# required for net_dns_resolves to function.
net_dns_myip_sanity_check() {
    if has_cmd dig; then
        dig +short +time=2 +tries=1 myip.opendns.com @resolver1.opendns.com >/dev/null 2>&1
        return $?
    fi
    return 0
}

# ---------------------------------------------------------------------------
# STUN (RFC 5389) public-address discovery
# ---------------------------------------------------------------------------
# STUN gives a second, independent method of learning your public
# address, obtained via a raw UDP round-trip to a public STUN server
# rather than an HTTPS request. Comparing it against the HTTP-based
# public IP is useful supporting evidence: if they disagree, traffic is
# very likely taking different paths/NAT bindings depending on
# protocol, which is common on some CGNAT deployments. This is
# implemented in pure Bash (using bash's /dev/udp/ redirection plus
# `od`, both essentially universal) so no additional required
# dependency is introduced -- it is always attempted, and always
# treated as optional, best-effort evidence: any failure (blocked UDP,
# no /dev/udp support, malformed response) simply means this piece of
# evidence is omitted, never a hard error.

# stun_hex_byte_to_dec <2-hex-char string> -> decimal string
stun_hex_byte_to_dec() {
    printf '%d' "$((16#$1))"
}

# stun_xor_addr <8-hex-char address> -> dotted-quad IPv4, XORed against
# the fixed STUN magic cookie (used for XOR-MAPPED-ADDRESS, attribute
# type 0x0020).
stun_xor_addr() {
    local addr_hex="$1"
    local cookie="${STUN_MAGIC_COOKIE}"
    local result="" i b1 b2 x

    for (( i = 0; i < 8; i += 2 )); do
        b1=$((16#${addr_hex:i:2}))
        b2=$((16#${cookie:i:2}))
        x=$(( b1 ^ b2 ))
        result+="${x}."
    done

    printf '%s' "${result%.}"
}

# stun_plain_addr <8-hex-char address> -> dotted-quad IPv4, no XOR
# (used for the legacy MAPPED-ADDRESS attribute, type 0x0001).
stun_plain_addr() {
    local addr_hex="$1"
    local result="" i b

    for (( i = 0; i < 8; i += 2 )); do
        b=$((16#${addr_hex:i:2}))
        result+="${b}."
    done

    printf '%s' "${result%.}"
}

# stun_parse_response <hex-encoded raw STUN message> -> prints the
# IPv4 address found in the first XOR-MAPPED-ADDRESS attribute
# (preferred) or MAPPED-ADDRESS attribute (fallback). Returns 1 if the
# message isn't a valid STUN Binding Success Response or contains
# neither attribute. Pure string/arithmetic parsing -- no network I/O
# -- so it is fully unit-testable with a crafted fixture.
stun_parse_response() {
    local hex="$1"
    local hexlen="${#hex}"

    (( hexlen >= 40 )) || return 1

    local msg_type="${hex:0:4}"
    [[ "${msg_type}" == "0101" ]] || return 1  # 0x0101 = Binding Success Response

    local msg_len_hex="${hex:4:4}"
    local msg_len=$((16#${msg_len_hex}))
    local pos=40  # header is 20 bytes = 40 hex chars
    local end=$(( 40 + msg_len * 2 ))
    (( end <= hexlen )) || end="${hexlen}"

    local xor_addr="" mapped_addr=""

    while (( pos + 8 <= end )); do
        local attr_type="${hex:pos:4}"
        local attr_len_hex="${hex:$((pos+4)):4}"
        local attr_len=$((16#${attr_len_hex}))
        local vstart=$((pos + 8))

        (( vstart + attr_len * 2 <= hexlen )) || break

        local vhex="${hex:vstart:$((attr_len*2))}"

        if [[ "${attr_type}" == "0020" && "${attr_len}" -ge 8 ]]; then
            local family="${vhex:2:2}"
            if [[ "${family}" == "01" ]]; then
                xor_addr=$(stun_xor_addr "${vhex:8:8}")
            fi
        elif [[ "${attr_type}" == "0001" && "${attr_len}" -ge 8 ]]; then
            local family2="${vhex:2:2}"
            if [[ "${family2}" == "01" ]]; then
                mapped_addr=$(stun_plain_addr "${vhex:8:8}")
            fi
        fi

        local padded_len=$(( ( (attr_len + 3) / 4 ) * 4 ))
        pos=$(( vstart + padded_len * 2 ))
    done

    if [[ -n "${xor_addr}" ]] && ip_is_valid_ipv4 "${xor_addr}"; then
        printf '%s' "${xor_addr}"
        return 0
    fi

    if [[ -n "${mapped_addr}" ]] && ip_is_valid_ipv4 "${mapped_addr}"; then
        printf '%s' "${mapped_addr}"
        return 0
    fi

    return 1
}

# stun_query <host> <port> -> performs a live STUN Binding Request over
# UDP and prints the raw hex-encoded response. Returns 1 on any
# failure (no /dev/udp support, blocked UDP, timeout, empty response).
# Both arguments are optional (default to a public Google STUN
# server); callers may override them for testing against a different
# server.
# shellcheck disable=SC2120  # intentionally callable with zero args (uses defaults)
stun_query() {
    local host="${1:-stun.l.google.com}"
    local port="${2:-19302}"

    has_cmd od || return 1

    local txn
    txn=$(head -c 12 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n')
    [[ "${#txn}" -eq 24 ]] || return 1

    local request_hex="00010000${STUN_MAGIC_COOKIE}${txn}"
    # Binding Request (type 0x0001), length 0x0000 (no attributes),
    # magic cookie, transaction ID -- 20 bytes total.

    local request_bytes
    request_bytes=$(printf '%s' "${request_hex}" | sed 's/../\\x&/g')

    local response_hex=""
    {
        exec 3<>"/dev/udp/${host}/${port}" || return 1
        printf '%b' "${request_bytes}" >&3
        response_hex=$(timeout_cmd 3 dd bs=512 count=1 <&3 2>/dev/null | od -An -tx1 | tr -d ' \n')
        exec 3<&- 3>&-
    } 2>/dev/null

    if [[ -z "${response_hex}" ]]; then
        return 1
    fi

    printf '%s' "${response_hex}"
}

# net_stun_get_public_ip performs a full STUN round trip and prints
# the discovered public IPv4 address. Best-effort: any failure at any
# stage (network, parsing) simply returns 1.
net_stun_get_public_ip() {
    local hex
    hex=$(stun_query) || return 1
    stun_parse_response "${hex}"
}
