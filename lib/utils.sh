#!/usr/bin/env bash
# lib/utils.sh
# Shared utility functions: logging, dependency checks, and generic
# helpers used across the rest of the codebase (including pure-bash
# IP arithmetic so the tool has no hard dependency on `ipcalc`).

if [[ -n "${CGNAT_UTILS_LOADED:-}" ]]; then
    return 0
fi
CGNAT_UTILS_LOADED=1

# Verbosity flags. These are set by the main entrypoint after parsing CLI
# options, but default to sane values so the library can be sourced and
# used independently (e.g. by the test suite).
VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"
QUIET="${QUIET:-false}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# All log_* functions write to stderr so stdout remains clean for the
# tool's actual (human or JSON) output.

log_info() {
    [[ "${QUIET}" == "true" ]] && return 0
    printf '%s[INFO]%s %s\n' "${C_BLUE:-}" "${C_RESET:-}" "$*" >&2
}

log_verbose() {
    [[ "${VERBOSE}" == "true" || "${DEBUG}" == "true" ]] || return 0
    [[ "${QUIET}" == "true" ]] && return 0
    printf '%s[VERBOSE]%s %s\n' "${C_CYAN:-}" "${C_RESET:-}" "$*" >&2
}

log_debug() {
    [[ "${DEBUG}" == "true" ]] || return 0
    printf '%s[DEBUG]%s %s\n' "${C_MAGENTA:-}" "${C_RESET:-}" "$*" >&2
}

log_warn() {
    [[ "${QUIET}" == "true" ]] && return 0
    printf '%s[WARN]%s %s\n' "${C_YELLOW:-}" "${C_RESET:-}" "$*" >&2
}

log_error() {
    printf '%s[ERROR]%s %s\n' "${C_RED:-}" "${C_RESET:-}" "$*" >&2
}

# ---------------------------------------------------------------------------
# Dependency checking
# ---------------------------------------------------------------------------

# require_cmd checks that a required command exists. If it is missing,
# prints an error and returns 1 (caller decides whether that is fatal).
require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        log_error "Required dependency '${cmd}' not found. Please install it."
        return 1
    fi
    return 0
}

# has_cmd checks for an optional command without emitting an error.
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# check_required_deps verifies all hard dependencies are present.
# Exits with CGNAT_EXIT_INTERNAL_ERROR (6) if any are missing -- the
# current exit code table has no separate "missing dependency" code,
# so this is treated as an internal/environment error.
check_required_deps() {
    local missing=0
    local deps=(bash curl ip awk grep sed)
    local dep

    for dep in "${deps[@]}"; do
        if ! has_cmd "${dep}"; then
            log_error "Missing required dependency: ${dep}"
            missing=1
        fi
    done

    if [[ "${missing}" -eq 1 ]]; then
        log_error "One or more required dependencies are missing. Aborting."
        exit "${CGNAT_EXIT_INTERNAL_ERROR:-6}"
    fi
}

# check_optional_deps logs (verbose only) which optional tools are
# available, without ever failing.
check_optional_deps() {
    local deps=(traceroute ipcalc miniupnpc jq dig)
    local dep
    for dep in "${deps[@]}"; do
        if has_cmd "${dep}"; then
            log_verbose "Optional dependency available: ${dep}"
        else
            log_verbose "Optional dependency not found (will use fallback): ${dep}"
        fi
    done
}

# ---------------------------------------------------------------------------
# Pure-bash IP arithmetic (no dependency on ipcalc)
# ---------------------------------------------------------------------------

# ip_is_valid_ipv4 <ip> -> returns 0 if the string looks like a valid
# dotted-quad IPv4 address.
ip_is_valid_ipv4() {
    local ip="$1"
    local IFS=.
    local -a octets
    # shellcheck disable=SC2206
    octets=($ip)

    [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
    [[ "${#octets[@]}" -eq 4 ]] || return 1

    local octet
    for octet in "${octets[@]}"; do
        if (( octet < 0 || octet > 255 )); then
            return 1
        fi
    done
    return 0
}

# ip_to_int <ip> -> prints the 32-bit unsigned integer representation of
# an IPv4 address on stdout.
ip_to_int() {
    local ip="$1"
    local IFS=.
    local -a o
    # shellcheck disable=SC2206
    o=($ip)
    echo $(( (o[0] << 24) + (o[1] << 16) + (o[2] << 8) + o[3] ))
}

# ip_in_cidr <ip> <cidr> -> returns 0 if <ip> falls inside <cidr>
# (e.g. ip_in_cidr "100.91.0.5" "100.64.0.0/10").
ip_in_cidr() {
    local ip="$1"
    local cidr="$2"
    local net="${cidr%/*}"
    local bits="${cidr#*/}"

    ip_is_valid_ipv4 "${ip}" || return 1
    ip_is_valid_ipv4 "${net}" || return 1

    local ip_int net_int mask
    ip_int=$(ip_to_int "${ip}")
    net_int=$(ip_to_int "${net}")

    if [[ "${bits}" -eq 0 ]]; then
        mask=0
    else
        mask=$(( 0xFFFFFFFF << (32 - bits) & 0xFFFFFFFF ))
    fi

    if [[ $(( ip_int & mask )) -eq $(( net_int & mask )) ]]; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

# trim removes leading/trailing whitespace from a string (stdin or arg).
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "${var}"
}

# is_number returns 0 if the argument is an integer.
is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# timeout_cmd wraps a command with `timeout` if available, otherwise runs
# it directly (best effort, since not all minimal systems ship `timeout`).
timeout_cmd() {
    local seconds="$1"
    shift
    if has_cmd timeout; then
        timeout "${seconds}" "$@"
    else
        "$@"
    fi
}
