# Troubleshooting

## "Missing required dependency" / exit code 6

CGNAT Inspector requires `bash`, `curl`, `ip`, `awk`, `grep`, and `sed`.
On minimal or embedded systems, `ip` (from `iproute2`) or `curl` may not be
preinstalled. A missing required dependency is reported as an internal
error (exit code 6).

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
- **The default gateway doesn't respond to ping**, even though general
  internet connectivity works. CGNAT Inspector treats an unreachable
  gateway the same as "no internet" (exit code 4), since it indicates a
  local network anomaly that makes every other check unreliable. Check
  `ip route show default` against what you expect.
- **You're behind a restrictive VPN split-tunnel** that only routes
  specific traffic. Try running with `--verbose` to see exactly which
  probe is failing.

## "DNS Failure" (exit code 5) but websites load fine in my browser

CGNAT Inspector checks DNS resolution independently of raw connectivity
(via `getent hosts`, falling back to `dig`, falling back to a full HTTPS
request). If you see this status:

- Confirm the machine you're running the check *on* -- not your browser's
  device -- can resolve names: `getent hosts cloudflare.com` or
  `dig cloudflare.com`.
- Check `/etc/resolv.conf` for a stale or unreachable nameserver.
- If you're in a container or minimal VM, confirm it has its own working
  DNS configuration rather than inheriting the host's.

## UPnP detection isn't working / Router WAN always shows "Unknown"

- Confirm `upnpc` is installed: `which upnpc` (from the `miniupnpc`
  package).
- Confirm UPnP/IGD is actually enabled on your router's admin page --
  many routers ship with it disabled by default for security reasons.
- Some routers only expose UPnP on specific VLANs/interfaces; if you're on
  a guest network or VLAN, UPnP requests may not reach the router's IGD
  service.
- Run `upnpc -s` manually to see the raw output and confirm connectivity
  to the router's UPnP service independent of CGNAT Inspector.
- This is expected, not a bug, if UPnP is genuinely unavailable: CGNAT
  Inspector will never guess or fabricate a Router WAN value, so
  "Unknown" is the honest result. The evidence engine accounts for this
  with a smaller "uncertainty" weight rather than treating it as
  confirmed CGNAT evidence -- see `docs/how-it-works.md`.

## Traceroute produces no hops / all hops show `*`

- Confirm `traceroute` is installed (`which traceroute`).
- Some networks/firewalls block the UDP or ICMP probes traceroute uses by
  default. This isn't fatal to CGNAT Inspector -- the traceroute signal is
  only worth 20 points out of 100, and every other test still runs
  normally.
- Root/administrator privileges are occasionally required for certain
  traceroute probe types on some systems; if you see permission errors,
  try running with `sudo`.

## STUN evidence never appears

STUN discovery is pure best-effort and silently omitted on any failure --
this is by design, not a bug to fix. Common reasons it doesn't succeed:

- Outbound UDP is blocked by your firewall or network policy (STUN uses
  UDP, unlike the HTTP-based public IP lookups).
- Your Bash build lacks `/dev/udp` network redirection support (rare, but
  possible on some minimal/hardened builds).
- The `od` utility (used to encode/decode the raw UDP payload) is
  missing -- check with `which od` (it ships with coreutils and is
  virtually always present on Linux).

None of these affect the rest of CGNAT Inspector's checks.

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
