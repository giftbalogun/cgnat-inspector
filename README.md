# CGNAT Inspector

> Detect Carrier Grade NAT (CGNAT) using multiple independent networking tests.

[![ShellCheck](https://github.com/giftbalogun/cgnat-inspector/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/giftbalogun/cgnat-inspector/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)

CGNAT Inspector is a dependency-light Linux CLI tool that answers one
question with confidence, not guesswork: **"Am I behind Carrier Grade
NAT?"** It runs several independent tests -- WAN-vs-public IP comparison,
RFC 6598/RFC 1918 range checks, traceroute hop analysis, and UPnP-based
double-NAT detection -- and combines them into a weighted confidence score,
instead of relying on any single signal.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      CGNAT Inspector v1.0.0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Network Information

Local IP:
192.168.1.10

Gateway:
192.168.1.1

WAN:
100.91.11.5

Public IPv4:
100.77.33.66

IPv6:
Not Available

----------------------------------------

Tests

✔ Internet reachable
✔ Gateway reachable
✖ WAN is private
✖ WAN is CGNAT
✔ Public IPv4 detected
✖ WAN differs from Public IP

----------------------------------------

Result

STATUS

CGNAT DETECTED

Confidence

95%  (Confirmed CGNAT)

Recommendations

• Request a Public IPv4 address from your ISP
• Use Tailscale or another WireGuard-based mesh VPN for inbound access
• Use Cloudflare Tunnel to expose services without port forwarding
• Consider a cheap VPS with a public IP as a reverse-proxy relay
• Enable IPv6 if your ISP supports it; IPv6 traffic typically bypasses CGNAT entirely

Exit Code

1
```

## Table of contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [CLI options](#cli-options)
- [Detection logic](#detection-logic)
- [JSON output](#json-output)
- [Examples](#examples)
- [Exit codes](#exit-codes)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Screenshots](#screenshots)
- [Contributing](#contributing)
- [License](#license)

## Overview

If you self-host anything at home, a game server, Plex, a security
camera NVR, a personal website and inbound connections mysteriously
don't work despite correct port forwarding, there's a good chance your ISP
has put you behind Carrier Grade NAT (CGNAT). CGNAT Inspector diagnoses
this quickly and explains *why*, rather than leaving you to guess based on
a single "what's my IP" website.

It's built as a modular, testable, ShellCheck-clean Bash project (not a
single monolithic script), suitable for public release, packaging, and
long-term maintenance. See [`docs/how-it-works.md`](docs/how-it-works.md)
for a full technical explanation of every test.

## Features

- ✅ Detect Carrier Grade NAT (RFC 6598, `100.64.0.0/10`)
- ✅ Detect Double NAT (via UPnP router WAN IP query)
- ✅ Compare router WAN IP vs. publicly observed IP
- ✅ Detect private WAN address (RFC 1918)
- ✅ Detect RFC 1918 private ranges generally
- ✅ Detect IPv6 availability and public IPv6 address
- ✅ Detect internet connectivity (with non-ICMP fallback)
- ✅ Traceroute analysis for private/CGNAT hops beyond your gateway
- ✅ UPnP WAN detection
- ✅ Gateway detection and reachability check
- ✅ Local network detection
- ✅ Automatic optional-dependency checking (never hard-fails on missing extras)
- ✅ Weighted confidence score (0-100) with labeled bands
- ✅ Actionable recommendations based on your specific result
- ✅ Human-readable colorized output *and* machine-readable `--json` output
- ✅ Documented exit codes for scripting/automation

## Installation

### Quick install

```bash
git clone https://github.com/giftbalogun/cgnat-inspector.git
cd cgnat-inspector
sudo ./install.sh
```

This installs to `/usr/local/bin/cgnat-inspector` (with supporting
libraries under `/usr/local/share/cgnat-inspector/`).

### Custom prefix

```bash
PREFIX=/opt/cgnat-inspector ./install.sh
```

### Uninstall

```bash
sudo ./uninstall.sh
```

### Run without installing

```bash
./cgnat-inspector --help
```

### Dependencies

**Required** (present on virtually every Linux system):

| Tool | Purpose |
|------|---------|
| `bash` | Interpreter |
| `curl` | Public IP lookups, HTTP connectivity fallback |
| `ip` | Local IP / gateway detection (from `iproute2`) |
| `awk`, `grep`, `sed` | Text processing |

**Optional** (missing ones are detected and skipped gracefully -- the tool
never hard-fails because an optional tool is absent):

| Tool | Purpose | Effect if missing |
|------|---------|--------------------|
| `traceroute` | Hop-level path analysis | Traceroute section/signal skipped |
| `ipcalc` | *(not required)* | Tool uses its own pure-Bash IP arithmetic |
| `miniupnpc` (`upnpc`) | Router WAN IP via UPnP, double-NAT detection | Falls back to a local-IP heuristic |
| `jq` | Pretty-printing JSON in tests/tooling | JSON is still emitted validly without it |
| `dig` | DNS sanity check | Skipped (non-fatal) |

## Usage

```bash
cgnat-inspector [OPTIONS]
```

Run with no options for the default formatted report:

```bash
cgnat-inspector
```

## CLI options

| Flag | Description |
|------|-------------|
| `--help` | Show help and exit |
| `--version` | Show version information and exit |
| `--json` | Output machine-readable JSON instead of formatted text |
| `--verbose` | Print additional detail about each test as it runs |
| `--debug` | Print debug-level internal diagnostics (implies `--verbose`) |
| `--quiet` | Suppress informational/log output (results still print) |
| `--ipv4-only` | Skip all IPv6 tests |
| `--ipv6-only` | Skip IPv4 public-address lookup (CGNAT detection itself is inherently IPv4) |
| `--traceroute` | Force traceroute analysis even if it would otherwise be skipped, and include raw hop data in JSON output |
| `--no-upnp` | Skip UPnP router WAN IP / double-NAT detection |

## Detection logic

CGNAT Inspector runs independent tests and combines them -- see
[`docs/how-it-works.md`](docs/how-it-works.md) for the full explanation of
each one. Summary:

1. **CGNAT range check** -- is the router's WAN IP in `100.64.0.0/10`?
2. **RFC 1918 private WAN check** -- is the WAN IP itself private (not just your LAN)?
3. **WAN vs. Public IP** -- does your router's WAN IP match what the internet sees?
4. **Traceroute hop analysis** -- are hops beyond your gateway still private/CGNAT space?
5. **Double NAT check** -- does your router's own UPnP-reported external IP indicate another NAT layer upstream?
6. **IPv6 availability** -- informational; often a workaround regardless of your CGNAT status.

### Confidence scoring

| Signal | Weight |
|--------|--------|
| WAN in CGNAT range | +40 |
| Private WAN | +30 |
| WAN differs from public IP | +20 |
| Private traceroute hop | +10 |

| Score | Label |
|-------|-------|
| 0-20 | Probably Public |
| 21-50 | Possible CGNAT |
| 51-80 | Likely CGNAT |
| 81-100 | Confirmed CGNAT |

## JSON output

```bash
cgnat-inspector --json
```

```json
{
  "status": "CGNAT",
  "confidence": 95,
  "local_ip": "192.168.1.15",
  "gateway": "192.168.1.1",
  "wan_ip": "100.91.0.22",
  "public_ip": "102.89.44.10",
  "ipv6": null,
  "private_wan": true,
  "cgnat": true,
  "double_nat": false,
  "traceroute_private": true,
  "recommendations": [
    "Request a Public IPv4 address from your ISP",
    "Use Tailscale or another WireGuard-based mesh VPN for inbound access",
    "Use Cloudflare Tunnel to expose services without port forwarding"
  ]
}
```

Full field reference, including the optional `--traceroute` hop array,
lives in [`docs/api.md`](docs/api.md).

## Examples

```bash
# Standard formatted report
cgnat-inspector

# Machine-readable, for scripts / monitoring
cgnat-inspector --json 2>/dev/null | jq .

# Only check IPv4 (skip IPv6 lookups)
cgnat-inspector --ipv4-only

# Skip UPnP (e.g. router has it disabled, or you don't trust it)
cgnat-inspector --no-upnp

# Verbose, human-readable, with every intermediate value shown
cgnat-inspector --verbose

# Use in a script based on exit code
if cgnat-inspector --quiet; then
    echo "You have a public IP."
else
    echo "Some form of NAT/CGNAT detected (exit code $?)."
fi
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Public IP |
| 1 | CGNAT |
| 2 | Double NAT |
| 3 | Internet unreachable |
| 4 | Missing dependency |
| 5 | Router unreachable |
| 6 | Unknown error |

## Troubleshooting

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for solutions to
common issues (missing dependencies, blocked ICMP, UPnP not responding,
empty traceroute, etc.).

## FAQ

See [`docs/faq.md`](docs/faq.md) for answers to common questions about
what CGNAT is, whether it can be fixed on your end, and what data this
tool sends (and doesn't send) over the network.

## Screenshots

See the [`screenshots/`](screenshots/) directory. Contributions of
real-world screenshots (with IPs redacted or replaced with documentation
ranges) are welcome via PR.

## Contributing

Contributions are welcome! Please read
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the project layout, code style,
and how to add a new detection signal, CLI flag, or test. Every change
should keep the project ShellCheck-clean and pass `./tests/run-tests.sh`.

## License

Released under the [MIT License](LICENSE).
