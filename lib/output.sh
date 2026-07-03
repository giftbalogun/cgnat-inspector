#!/usr/bin/env bash
# lib/output.sh
# Human-readable console output formatting: banner, sections, check
# marks, and the final result block. Kept separate from detect.sh so
# presentation can change without touching detection logic.

if [[ -n "${CGNAT_OUTPUT_LOADED:-}" ]]; then
    return 0
fi
CGNAT_OUTPUT_LOADED=1

readonly OUTPUT_WIDTH=40

out_rule() {
    printf '%s\n' "$(printf '━%.0s' $(seq 1 "${OUTPUT_WIDTH}"))"
}

out_thin_rule() {
    printf '%s\n' "$(printf -- '-%.0s' $(seq 1 "${OUTPUT_WIDTH}"))"
}

out_banner() {
    out_rule
    printf '\n      %s%s v%s%s\n\n' "${C_BOLD}" "${CGNAT_NAME}" "${CGNAT_VERSION}" "${C_RESET}"
    out_rule
    printf '\n'
}

out_section_title() {
    printf '%s%s%s\n\n' "${C_BOLD}" "$1" "${C_RESET}"
}

# out_kv <label> <value> prints a label on one line and the value on the
# next, matching the requested output style.
out_kv() {
    local label="$1"
    local value="$2"
    printf '%s:\n%s\n\n' "${label}" "${value:-Unknown}"
}

# out_check <passed:true/false> <description>
out_check() {
    local passed="$1"
    local desc="$2"
    if [[ "${passed}" == "true" ]]; then
        printf '%s✔%s %s\n' "${C_GREEN}" "${C_RESET}" "${desc}"
    else
        printf '%s✖%s %s\n' "${C_RED}" "${C_RESET}" "${desc}"
    fi
}

# out_status_block <status> prints the big colored status line.
out_status_block() {
    local status="$1"
    local color label

    case "${status}" in
        PUBLIC)
            color="${C_GREEN}"
            label="PUBLIC IP DETECTED"
            ;;
        CGNAT)
            color="${C_RED}"
            label="CGNAT DETECTED"
            ;;
        DOUBLE_NAT)
            color="${C_RED}"
            label="DOUBLE NAT DETECTED"
            ;;
        NO_INTERNET)
            color="${C_RED}"
            label="INTERNET UNREACHABLE"
            ;;
        ROUTER_UNREACHABLE)
            color="${C_YELLOW}"
            label="ROUTER UNREACHABLE"
            ;;
        *)
            color="${C_YELLOW}"
            label="UNKNOWN"
            ;;
    esac

    printf '%s%s%s\n' "${color}" "${label}" "${C_RESET}"
}

# out_confidence_bar <score> prints a small textual confidence
# indicator alongside the numeric percentage.
out_confidence_bar() {
    local score="$1"
    local label
    label=$(detect_confidence_label "${score}")

    local color
    if (( score <= 20 )); then
        color="${C_GREEN}"
    elif (( score <= 50 )); then
        color="${C_YELLOW}"
    elif (( score <= 80 )); then
        color="${C_YELLOW}"
    else
        color="${C_RED}"
    fi

    printf '%s%s%%%s  (%s)\n' "${color}" "${score}" "${C_RESET}" "${label}"
}

# out_recommendations <newline-separated list on stdin>
out_recommendations() {
    local rec
    while IFS= read -r rec || [[ -n "${rec}" ]]; do
        [[ -z "${rec}" ]] && continue
        printf '• %s\n' "${rec}"
    done
}
