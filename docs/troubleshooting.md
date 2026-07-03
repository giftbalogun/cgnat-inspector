# Troubleshooting

## "Missing required dependency" / exit code 4

CGNAT Inspector requires `bash`, `curl`, `ip`, `awk`, `grep`, and `sed`.
On minimal or embedded systems, `ip` (from `iproute2`) or `curl` may not be
preinstalled.

**Debian/Ubuntu:**
```bash
sudo apt-get update && sudo apt-get install -y curl iproute2 gawk grep sed
```

**Alpine:**
```bash
apk add bash curl iproute2 gawk grep sed
```

**OpenWrt:**
```bash
opkg update
opkg install bash curl ip-full
```

## "Internet unreachable" but I definitely have internet

This can happen if:

- **ICMP (ping) is blocked** by your firewall or ISP. CGNAT Inspector
  falls back to an HTTPS check via `curl`, but if outbound HTTPS is also
  blocked or a captive portal is intercepting it, this will still fail.
  Try: `curl -v https://cloudflare.com` manually to see what's happening.
- **DNS resolution is broken.** The public-IP echo services and ping
  targets used are IP-literal or well-known, but if your resolver is down
  more generally, some checks can still be affected. Try:
  `getent hosts api.ipify.org` or `dig api.ipify.org`.
- **You're behind a restrictive VPN split-tunnel** that only routes
  specific traffic. Try running with `--verbose` to see exactly which
  probe is failing.

## "Router unreachable" but my WiFi works fine

The detected gateway address might be wrong on multi-homed systems (e.g.
machines with both WiFi and Ethernet active, or VPNs that install their own
default route). Check what CGNAT Inspector detected:

```bash
cgnat-inspector --verbose 2>&1 | grep -i gateway
```

Compare against:

```bash
ip route show default
```

If they don't match your expectation, a VPN or secondary interface is
likely taking over the default route.

## UPnP detection isn't working / `wan_source` always falls back

- Confirm `upnpc` is installed: `which upnpc` (from the `miniupnpc`
  package).
- Confirm UPnP/IGD is actually enabled on your router's admin page --
  many routers ship with it disabled by default for security reasons.
- Some routers only expose UPnP on specific VLANs/interfaces; if you're on
  a guest network or VLAN, UPnP requests may not reach the router's IGD
  service.
- Run `upnpc -s` manually to see the raw output and confirm connectivity
  to the router's UPnP service independent of CGNAT Inspector.

## Traceroute produces no hops / all hops show `*`

- Confirm `traceroute` is installed (`which traceroute`).
- Some networks/firewalls block the UDP or ICMP probes traceroute uses by
  default. This isn't fatal to CGNAT Inspector -- the traceroute signal is
  only worth 10 points out of 100, and every other test still runs
  normally.
- Root/administrator privileges are occasionally required for certain
  traceroute probe types on some systems; if you see permission errors,
  try running with `sudo`.

## JSON output looks malformed / fails to parse

CGNAT Inspector hand-assembles JSON without requiring `jq` to be
installed, with escaping tested against embedded quotes, backslashes, and
newlines. If you still hit a parsing issue:

1. Run `cgnat-inspector --json 2>/dev/null | jq .` to isolate whether it's
   a real JSON problem or just stderr output getting mixed into stdout by
   your shell/redirection.
2. File a bug report (see `.github/ISSUE_TEMPLATE/bug_report.md`) with the
   raw output attached.

## ShellCheck failures after modifying the code

Run the same check CI runs:

```bash
shellcheck -x cgnat-inspector install.sh uninstall.sh lib/*.sh tests/*.sh
```

The `-x` flag is required so ShellCheck follows the `source` statements
between `cgnat-inspector` and the files under `lib/`.

## Tests fail in a sandboxed/offline CI environment

`tests/test-network.sh` is designed to skip (not fail) live-network checks
such as public IP lookups when no internet access is available, but local
checks (`ip route`, IP arithmetic, JSON encoding, detection logic) always
run and must pass regardless of network conditions. If you see unexpected
failures in `test-private.sh`, `test-json.sh`, or `test-ipcalc.sh`, those
indicate a real logic bug, not an environment limitation.

## Still stuck?

Open an issue using the bug report template in
`.github/ISSUE_TEMPLATE/bug_report.md`, including the output of:

```bash
cgnat-inspector --json --verbose 2>&1
```
