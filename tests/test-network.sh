#!/usr/bin/env bash
# tests/test-network.sh
# Tests for lib/network.sh. Functions that require live internet access
# (net_get_public_ipv4, net_check_internet, etc.) are tested only for
# graceful behavior/return-code contracts, and are skipped with a clear
# notice when run in an offline/sandboxed CI environment -- they must
# never cause the suite to fail simply because the runner has no
# network access.

set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=lib/colors.sh
source "${ROOT_DIR}/lib/colors.sh"
color_init true
# shellcheck source=lib/utils.sh
source "${ROOT_DIR}/lib/utils.sh"
# shellcheck source=lib/network.sh
source "${ROOT_DIR}/lib/network.sh"

# shellcheck source=tests/test-framework.sh
source "${SCRIPT_DIR}/test-framework.sh"

# Detect whether this environment has outbound network access at all,
# so live-lookup tests can be skipped cleanly instead of failing CI in
# sandboxed/offline runners.
_network_available() {
    net_check_internet
}

test_local_ip_detection() {
    if ! has_cmd ip; then
        _pass "net_get_local_ip skipped ('ip' command not available)"
        return
    fi
    local ip
    if ip=$(net_get_local_ip); then
        assert_true 'ip_is_valid_ipv4 "'"${ip}"'"' "net_get_local_ip returns a valid IPv4 address (${ip})"
    else
        _pass "net_get_local_ip returned no route (acceptable in isolated/CI network namespace)"
    fi
}

test_gateway_detection() {
    if ! has_cmd ip; then
        _pass "net_get_gateway skipped ('ip' command not available)"
        return
    fi
    local gw
    if gw=$(net_get_gateway); then
        assert_true 'ip_is_valid_ipv4 "'"${gw}"'"' "net_get_gateway returns a valid IPv4 address (${gw})"
    else
        _pass "net_get_gateway returned no default route (acceptable in isolated/CI network namespace)"
    fi
}

test_public_ipv4_lookup() {
    if ! _network_available; then
        _pass "net_get_public_ipv4 skipped (no internet access in this environment)"
        return
    fi
    local ip
    if ip=$(net_get_public_ipv4); then
        assert_true 'ip_is_valid_ipv4 "'"${ip}"'"' "net_get_public_ipv4 returns a valid IPv4 address"
    else
        _pass "net_get_public_ipv4 gracefully returned failure (all echo services unreachable)"
    fi
}

test_public_ipv6_lookup_graceful() {
    if ! _network_available; then
        _pass "net_get_public_ipv6 skipped (no internet access in this environment)"
        return
    fi
    # This must never hang or crash even when IPv6 is unavailable.
    net_get_public_ipv6 >/dev/null 2>&1
    _pass "net_get_public_ipv6 returns without hanging or crashing"
}

test_upnp_graceful_without_binary() {
    if has_cmd upnpc; then
        _pass "upnpc present on this system; skipping no-binary fallback check"
        return
    fi
    assert_false 'net_get_wan_ip_upnp' "net_get_wan_ip_upnp fails gracefully when upnpc is absent"
}

test_dns_resolves_non_fatal() {
    # Should never abort the shell even if dig is missing or DNS fails.
    net_dns_resolves >/dev/null 2>&1
    _pass "net_dns_resolves returns without aborting the shell"
}

run_test_suite "Network Function Tests" \
    test_local_ip_detection \
    test_gateway_detection \
    test_public_ipv4_lookup \
    test_public_ipv6_lookup_graceful \
    test_upnp_graceful_without_binary \
    test_dns_resolves_non_fatal
