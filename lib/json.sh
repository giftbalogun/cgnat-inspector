#!/usr/bin/env bash
# lib/json.sh
# Minimal, dependency-free JSON encoding helpers. `jq` is treated as an
# optional dependency for pretty-printing only -- the tool must be able
# to emit valid JSON without it.

if [[ -n "${CGNAT_JSON_LOADED:-}" ]]; then
    return 0
fi
CGNAT_JSON_LOADED=1

# json_escape <string> -> prints the string with JSON special characters
# escaped, suitable for placing inside double quotes.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"   # backslash
    s="${s//\"/\\\"}"   # double quote
    s="${s//$'\n'/\\n}" # newline
    s="${s//$'\r'/}"    # strip carriage returns
    s="${s//$'\t'/\\t}" # tab
    printf '%s' "${s}"
}

# json_string_or_null <value|null> -> prints either "value" or the bare
# literal null when the input is empty or the literal string "null".
json_string_or_null() {
    local v="$1"
    if [[ -z "${v}" || "${v}" == "null" ]]; then
        printf 'null'
    else
        printf '"%s"' "$(json_escape "${v}")"
    fi
}

# json_bool <true|false> -> prints the bare literal.
json_bool() {
    if [[ "$1" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

# json_array_of_strings <newline-separated list on stdin> -> prints a
# JSON array of strings, e.g. ["a","b","c"]. Prints [] for empty input.
json_array_of_strings() {
    local items=()
    local line
    # The `|| [[ -n "${line}" ]]` clause ensures the final line is not
    # silently dropped when the input does not end in a trailing
    # newline (a classic `read` pitfall when consuming command
    # substitution output, which strips trailing newlines).
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" ]] && continue
        items+=("$(json_string_or_null "${line}")")
    done

    if [[ "${#items[@]}" -eq 0 ]]; then
        printf '[]'
        return
    fi

    local IFS=,
    printf '[%s]' "${items[*]}"
}

# json_array_of_hops <newline-separated "hop ip" pairs> -> prints a
# JSON array of {"hop":N,"ip":"..."} objects.
json_array_of_hops() {
    local input="$1"
    local hop ip items=()

    while read -r hop ip || [[ -n "${hop}${ip}" ]]; do
        [[ -z "${hop}" ]] && continue
        items+=("{\"hop\":${hop},\"ip\":$(json_string_or_null "${ip}")}")
    done <<< "${input}"

    if [[ "${#items[@]}" -eq 0 ]]; then
        printf '[]'
        return
    fi

    local IFS=,
    printf '[%s]' "${items[*]}"
}

# json_array_of_evidence <newline-separated "description<TAB>true|false"
# lines> -> prints a JSON array of {"description":"...","present":bool}
# objects. This consumes exactly the format produced by
# lib/detect.sh's detect_build_evidence, so the JSON "evidence" field
# and the human-readable checklist can never drift out of sync.
json_array_of_evidence() {
    local input="$1"
    local desc present items=()

    while IFS=$'\t' read -r desc present || [[ -n "${desc}${present}" ]]; do
        [[ -z "${desc}" ]] && continue
        items+=("{\"description\":$(json_string_or_null "${desc}"),\"present\":$(json_bool "${present}")}")
    done <<< "${input}"

    if [[ "${#items[@]}" -eq 0 ]]; then
        printf '[]'
        return
    fi

    local IFS=,
    printf '[%s]' "${items[*]}"
}

# json_build_report constructs the full JSON report object. All
# arguments are named via a simple positional contract documented in
# docs/api.md.
#
# Args:
#   1  status              -- PUBLIC | CGNAT_DETECTED | POSSIBLE_CGNAT |
#                              INCONCLUSIVE | NO_INTERNET | DNS_FAILURE |
#                              INTERNAL_ERROR
#   2  confidence           -- integer 0-100
#   3  local_ip             -- LAN IPv4 address, or empty for null
#   4  gateway              -- default gateway IPv4, or empty for null
#   5  router_wan           -- router's real WAN IPv4 (UPnP-derived only),
#                               or empty for null (i.e. "Unknown")
#   6  public_ip            -- HTTP-observed public IPv4, or empty for
#                               null (i.e. "Unavailable")
#   7  ipv6                 -- public IPv6, or empty for null
#   8  evidence_lines        -- newline-separated "description<TAB>bool"
#                               (from detect_build_evidence)
#   9  conclusion            -- explanatory sentence (from detect_conclusion)
#   10 recommendations_list  -- newline-separated recommendation strings
#   11 traceroute_hops       -- optional, newline-separated "hop ip" pairs;
#                               when non-empty, adds a "traceroute" field
json_build_report() {
    local status="$1"
    local confidence="$2"
    local local_ip="$3"
    local gateway="$4"
    local router_wan="$5"
    local public_ip="$6"
    local ipv6="$7"
    local evidence_lines="$8"
    local conclusion="$9"
    local recommendations_list="${10}"
    local traceroute_hops="${11:-}"

    printf '{'
    printf '"status":%s,'              "$(json_string_or_null "${status}")"
    printf '"confidence":%s,'          "${confidence}"
    printf '"local_ip":%s,'            "$(json_string_or_null "${local_ip}")"
    printf '"gateway":%s,'             "$(json_string_or_null "${gateway}")"
    printf '"router_wan":%s,'          "$(json_string_or_null "${router_wan}")"
    printf '"public_ip":%s,'           "$(json_string_or_null "${public_ip}")"
    printf '"ipv6":%s,'                "$(json_string_or_null "${ipv6}")"
    printf '"evidence":%s,'            "$(json_array_of_evidence "${evidence_lines}")"
    if [[ -n "${traceroute_hops}" ]]; then
        printf '"traceroute":%s,' "$(json_array_of_hops "${traceroute_hops}")"
    fi
    printf '"conclusion":%s,'          "$(json_string_or_null "${conclusion}")"
    printf '"recommendations":%s'      "$(printf '%s' "${recommendations_list}" | json_array_of_strings)"
    printf '}\n'
}

# json_pretty_print reads a JSON document from stdin and pretty-prints
# it using `jq` if available; otherwise passes it through unchanged.
json_pretty_print() {
    if has_cmd jq; then
        jq '.'
    else
        cat
    fi
}
