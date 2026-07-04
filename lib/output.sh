#!/usr/bin/env bash
# lib/output.sh
# Human-readable console output formatting: banner, sections, the
# evidence checklist, and the final Assessment block. Kept separate
# from lib/detect.sh so presentation can change without touching
# detection/scoring logic -- this file only renders whatever it is
# given; it makes no decisions of its own.

if [[ -n "${CGNAT_OUTPUT_LOADED:-}" ]]; then
    return 0
fi
CGNAT_OUTPUT_LOADED=1

readonly OUTPUT_WIDTH=32

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

# out_evidence_checklist reads "description<TAB>true|false" lines from
# stdin (as produced by detect_build_evidence) and prints a ✔/✖
# checklist. ✔ means the stated condition is true, ✖ means it is
# false -- this is a literal boolean rendering, not a "good/bad"
# judgment call, so each description is phrased to read naturally
# either way (see lib/detect.sh for the exact wording).
out_evidence_checklist() {
    local desc present
    while IFS=$'\t' read -r desc present || [[ -n "${desc}${present}" ]]; do
        [[ -z "${desc}" ]] && continue
        if [[ "${present}" == "true" ]]; then
            printf '%s✔%s %s\n' "${C_GREEN}" "${C_RESET}" "${desc}"
        else
            printf '%s✖%s %s\n' "${C_RED}" "${C_RESET}" "${desc}"
        fi
    done
}

# out_status_line prints the colored status label for the Assessment
# block.
out_status_line() {
    local status="$1"
    local color label

    case "${status}" in
        PUBLIC)
            color="${C_GREEN}"
            label="Public IPv4 Confirmed"
            ;;
        CGNAT_DETECTED)
            color="${C_RED}"
            label="CGNAT Detected"
            ;;
        POSSIBLE_CGNAT)
            color="${C_YELLOW}"
            label="Possible CGNAT"
            ;;
        INCONCLUSIVE)
            color="${C_YELLOW}"
            label="Inconclusive"
            ;;
        NO_INTERNET)
            color="${C_RED}"
            label="Internet Unreachable"
            ;;
        DNS_FAILURE)
            color="${C_RED}"
            label="DNS Failure"
            ;;
        *)
            color="${C_RED}"
            label="Internal Error"
            ;;
    esac

    printf '%s%s%s\n' "${color}" "${label}" "${C_RESET}"
}

# out_confidence_line <score> prints just the percentage, colored by
# severity band. The status line above already conveys the label
# (Possible/Detected/etc.), so this stays a plain, uncluttered number.
out_confidence_line() {
    local score="$1"
    local color

    if (( score >= STATUS_THRESHOLD_DETECTED )); then
        color="${C_RED}"
    elif (( score >= STATUS_THRESHOLD_POSSIBLE )); then
        color="${C_YELLOW}"
    else
        color="${C_GREEN}"
    fi

    printf '%s%s%%%s\n' "${color}" "${score}" "${C_RESET}"
}

# out_recommendations <newline-separated list on stdin>
out_recommendations() {
    local rec
    while IFS= read -r rec || [[ -n "${rec}" ]]; do
        [[ -z "${rec}" ]] && continue
        printf '• %s\n' "${rec}"
    done
}
