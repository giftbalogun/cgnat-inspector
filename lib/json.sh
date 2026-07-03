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

# json_string <value|null> -> prints either "value" or the bare literal
# null when the input is empty or the literal string "null".
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

# json_build_report constructs the full JSON report object.
# All arguments are named via a simple positional contract documented
# in docs/api.md. Prints the final JSON document to stdout (single line,
# no trailing newline formatting requirements -- valid JSON either way).
#
# The optional 13th argument (traceroute_hops) is a newline-separated
# list of "hop ip" pairs (as produced by tr_run_traceroute). When
# non-empty, a "traceroute" array field is included in the report,
# e.g. [{"hop":1,"ip":"192.168.1.1"}, ...]. When empty, the field is
# omitted entirely so JSON consumers can distinguish "not run" from
# "no hops".
json_build_report() {
    local status="$1"
    local confidence="$2"
    local local_ip="$3"
    local gateway="$4"
    local wan_ip="$5"
    local public_ip="$6"
    local ipv6="$7"
    local private_wan="$8"
    local cgnat="$9"
    local double_nat="${10}"
    local traceroute_private="${11}"
    local recommendations_list="${12}" # newline-separated
    local traceroute_hops="${13:-}"    # optional, newline-separated "hop ip"

    printf '{'
    printf '"status":%s,'              "$(json_string_or_null "${status}")"
    printf '"confidence":%s,'          "${confidence}"
    printf '"local_ip":%s,'            "$(json_string_or_null "${local_ip}")"
    printf '"gateway":%s,'             "$(json_string_or_null "${gateway}")"
    printf '"wan_ip":%s,'              "$(json_string_or_null "${wan_ip}")"
    printf '"public_ip":%s,'           "$(json_string_or_null "${public_ip}")"
    printf '"ipv6":%s,'                "$(json_string_or_null "${ipv6}")"
    printf '"private_wan":%s,'         "$(json_bool "${private_wan}")"
    printf '"cgnat":%s,'               "$(json_bool "${cgnat}")"
    printf '"double_nat":%s,'          "$(json_bool "${double_nat}")"
    printf '"traceroute_private":%s,'  "$(json_bool "${traceroute_private}")"
    if [[ -n "${traceroute_hops}" ]]; then
        printf '"traceroute":%s,' "$(json_array_of_hops "${traceroute_hops}")"
    fi
    printf '"recommendations":%s'      "$(printf '%s' "${recommendations_list}" | json_array_of_strings)"
    printf '}\n'
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

# json_pretty_print reads a JSON document from stdin and pretty-prints
# it using `jq` if available; otherwise passes it through unchanged.
json_pretty_print() {
    if has_cmd jq; then
        jq '.'
    else
        cat
    fi
}
