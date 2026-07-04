#!/usr/bin/env bash
# lib/traceroute.sh
# Traceroute execution and hop analysis. Used to detect whether early
# hops beyond the local gateway are still on private/CGNAT address
# space, which is supporting (never sole) evidence of carrier-grade
# NAT in the scoring engine (see lib/detect.sh).
#
# Requires lib/detect.sh to be sourced first (tr_analyze calls
# detect_is_non_public_ipv4).

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

# tr_format_for_display formats raw "<hop> <ip>" lines (from stdin) into
# a display-friendly "  N   ip" block, printed to stdout.
tr_format_for_display() {
    awk '{ printf "  %-4s%s\n", $1, $2 }'
}

# tr_analyze <gateway_ip>
# Reads raw "<hop> <ip>" lines from stdin (as produced by
# tr_run_traceroute) and prints a structured summary as "key=value"
# lines, one per line, for easy parsing by the caller:
#
#   private_hops=N              -- count of private/CGNAT hops beyond the gateway
#   public_hops=N                -- count of genuinely public hops beyond the gateway
#   backbone_private=true|false  -- true if >=2 private/CGNAT hops were seen
#                                    (a single private hop is treated as noise,
#                                    not evidence -- see docs/how-it-works.md)
#   transition_pub_to_priv=true|false -- a public hop was immediately
#                                    followed by a private/CGNAT hop
#   transition_priv_to_pub=true|false -- the reverse transition
#
# The hop matching the known gateway address (or, if the gateway is
# unknown, the positionally-first hop) is excluded from all counts,
# since a private gateway is expected and uninformative on its own.
# This function requires lib/detect.sh to be sourced first (uses
# detect_is_non_public_ipv4). Traceroute is deliberately used only as
# supporting evidence in the scoring engine -- see SCORE_TRACEROUTE_BACKBONE
# in lib/detect.sh -- never as the sole basis for a CGNAT conclusion.
tr_analyze() {
    local gateway="$1"
    local hop ip
    local private_hops=0 public_hops=0
    local prev_class="" this_class=""
    local trans_pub_priv=false trans_priv_pub=false
    local first_hop_seen=false

    while read -r hop ip || [[ -n "${hop}${ip}" ]]; do
        [[ -z "${hop}" ]] && continue
        [[ "${ip}" == "*" ]] && continue

        if [[ -n "${gateway}" ]]; then
            if [[ "${ip}" == "${gateway}" ]]; then
                prev_class=""
                continue
            fi
        elif [[ "${first_hop_seen}" == "false" ]]; then
            first_hop_seen=true
            prev_class=""
            continue
        fi
        first_hop_seen=true

        if detect_is_non_public_ipv4 "${ip}"; then
            this_class="private"
            private_hops=$(( private_hops + 1 ))
        else
            this_class="public"
            public_hops=$(( public_hops + 1 ))
        fi

        if [[ -n "${prev_class}" ]]; then
            if [[ "${prev_class}" == "public" && "${this_class}" == "private" ]]; then
                trans_pub_priv=true
            elif [[ "${prev_class}" == "private" && "${this_class}" == "public" ]]; then
                trans_priv_pub=true
            fi
        fi
        prev_class="${this_class}"
    done

    local backbone_private=false
    if (( private_hops >= 2 )); then
        backbone_private=true
    fi

    printf 'private_hops=%d\n' "${private_hops}"
    printf 'public_hops=%d\n' "${public_hops}"
    printf 'backbone_private=%s\n' "${backbone_private}"
    printf 'transition_pub_to_priv=%s\n' "${trans_pub_priv}"
    printf 'transition_priv_to_pub=%s\n' "${trans_priv_pub}"
}
