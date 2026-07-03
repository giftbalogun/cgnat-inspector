#!/usr/bin/env bash
# lib/colors.sh
# ANSI color definitions for CGNAT Inspector.
#
# Colors are automatically disabled when:
#   - stdout is not a terminal (e.g. output is piped/redirected)
#   - --json mode is active
#   - NO_COLOR environment variable is set (https://no-color.org/)
#
# This file must be sourced, not executed.

# Guard against double-sourcing.
if [[ -n "${CGNAT_COLORS_LOADED:-}" ]]; then
    return 0
fi
CGNAT_COLORS_LOADED=1

# color_init decides whether ANSI escape codes should be used and exports
# the appropriate variables. It should be called once, after CLI options
# (such as --json) have been parsed.
#
# Globals set:
#   COLOR_ENABLED, C_RESET, C_BOLD, C_DIM,
#   C_RED, C_GREEN, C_YELLOW, C_BLUE, C_CYAN, C_MAGENTA
color_init() {
    local force_disable="${1:-false}"

    if [[ "${force_disable}" == "true" ]]; then
        COLOR_ENABLED=false
    elif [[ -n "${NO_COLOR:-}" ]]; then
        COLOR_ENABLED=false
    elif [[ ! -t 1 ]]; then
        # stdout is not a terminal (redirected/piped) -> disable colors
        COLOR_ENABLED=false
    else
        COLOR_ENABLED=true
    fi

    if [[ "${COLOR_ENABLED}" == "true" ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m'
        C_CYAN=$'\033[36m'
        C_MAGENTA=$'\033[35m'
    else
        C_RESET=""
        C_BOLD=""
        C_DIM=""
        C_RED=""
        C_GREEN=""
        C_YELLOW=""
        C_BLUE=""
        C_CYAN=""
        C_MAGENTA=""
    fi

    export COLOR_ENABLED C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_CYAN C_MAGENTA
}

# Convenience wrappers -------------------------------------------------------

color_red()     { printf '%s%s%s' "${C_RED}"     "$1" "${C_RESET}"; }
color_green()   { printf '%s%s%s' "${C_GREEN}"   "$1" "${C_RESET}"; }
color_yellow()  { printf '%s%s%s' "${C_YELLOW}"  "$1" "${C_RESET}"; }
color_blue()    { printf '%s%s%s' "${C_BLUE}"    "$1" "${C_RESET}"; }
color_bold()    { printf '%s%s%s' "${C_BOLD}"    "$1" "${C_RESET}"; }
