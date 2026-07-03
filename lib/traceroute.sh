#!/usr/bin/env bash
# lib/traceroute.sh
# Traceroute execution and hop analysis. Used to detect whether early
# hops beyond the local gateway are still on private/CGNAT address
# space, which is a strong secondary signal of carrier-grade NAT.

if [[ -n "${CGNAT_TRACEROUTE_LOADED:-}" ]]; then
    return 0
fi
CGNAT_TRACEROUTE_LOADED=1

# tr_run_traceroute <target> [max_hops]
# Runs traceroute (if available) and prints raw hop lines to stdout, one
# per line, in the form: "<hop_number> <ip_or_*>"
# Returns 1 if traceroute is not installed.
tr_run_traceroute() {
    local target="${1:-1.1.1.1}"
    local max_hops="${2:-8}"

    has_cmd traceroute || return 1

    # -n : numeric output only (no reverse DNS, faster & more reliable)
    # -w : wait time per probe
    # -q : queries per hop
    timeout_cmd 15 traceroute -n -w 1 -q 1 -m "${max_hops}" "${target}" 2>/dev/null |
        tail -n +2 |
        awk '{
            hop=$1
            ip=$2
            # Match a dotted-quad IPv4 address; otherwise mark as unresolved.
            if (ip ~ /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/) {
                print hop, ip
            } else {
                print hop, "*"
            }
        }'
}

# tr_first_public_hop <traceroute_output>
# Reads traceroute output (as produced by tr_run_traceroute, one hop per
# line via stdin) and prints the first hop IP that is NOT private and
# NOT CGNAT space -- i.e. the first genuinely public hop on the path.
tr_first_public_hop() {
    local hop ip
    while read -r hop ip || [[ -n "${hop}${ip}" ]]; do
        [[ "${ip}" == "*" ]] && continue
        if ! detect_is_private_ipv4 "${ip}" && ! detect_is_cgnat_range "${ip}"; then
            printf '%s' "${ip}"
            return 0
        fi
    done
    return 1
}

# tr_has_private_hop_beyond_gateway <gateway_ip>
# Reads traceroute output from stdin and returns 0 if any hop beyond
# the local gateway is still private or CGNAT space. This indicates the
# path traverses ISP-internal NAT infrastructure before reaching the
# public internet -- a classic CGNAT fingerprint.
#
# The gateway's own address is explicitly excluded (by IP match, not
# just position) since a private gateway is expected and not itself a
# signal of anything. Matching by value rather than "first line" also
# keeps this correct if the first traceroute probe times out ("*").
tr_has_private_hop_beyond_gateway() {
    local gateway="$1"
    local hop ip first_hop_seen=false

    while read -r hop ip || [[ -n "${hop}${ip}" ]]; do
        [[ "${ip}" == "*" ]] && continue

        # Skip the hop that matches the known gateway address. If the
        # gateway is unknown, fall back to skipping positionally-first
        # hop only, so a normal private home gateway isn't mistaken for
        # a CGNAT signal.
        if [[ -n "${gateway}" ]]; then
            [[ "${ip}" == "${gateway}" ]] && continue
        elif [[ "${first_hop_seen}" == "false" ]]; then
            first_hop_seen=true
            continue
        fi
        first_hop_seen=true

        if detect_is_cgnat_range "${ip}" || detect_is_private_ipv4 "${ip}"; then
            return 0
        fi
    done

    return 1
}

# tr_format_for_display formats raw "<hop> <ip>" lines (from stdin) into
# a display-friendly "  N   ip" block, printed to stdout.
tr_format_for_display() {
    awk '{ printf "  %-4s%s\n", $1, $2 }'
}
