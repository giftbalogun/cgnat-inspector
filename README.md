# CGNAT Inspector

> Detect Carrier Grade NAT (CGNAT) using multiple independent networking tests.

[![ShellCheck](https://github.com/giftbalogun/cgnat-inspector/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/giftbalogun/cgnat-inspector/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)

CGNAT Inspector is a dependency-light Linux CLI tool that answers one
question with **evidence, not guesswork**: "Am I behind Carrier Grade
NAT?" It runs several independent tests -- router WAN inspection via
UPnP, multi-provider public IP lookups, STUN cross-checks, RFC 6598/RFC
1918 range checks, and traceroute backbone analysis -- and combines them
into a weighted confidence score. It never concludes CGNAT from a single
signal, and it never reports a guessed value as if it were confirmed.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      CGNAT Inspector v1.0.0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Network Information

LAN IP:
192.168.1.15

Gateway:
192.168.1.1

Router WAN:
100.91.0.22

Public IPv4:
102.89.44.10

IPv6:
Not Available

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Assessment

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Status

CGNAT Detected

Confidence

95%

Evidence

✔ Internet connectivity confirmed
✔ Default gateway reachable
✔ DNS resolution working
✔ Router WAN address obtained
✔ Router WAN address is private or CGNAT range
✔ Public IPv4 address obtained
✔ Public IPv4 differs from Router WAN
✔ Traceroute shows a private/CGNAT backbone
✖ Public IPv6 available
✔ Multiple independent indicators corroborate

Conclusion

The available evidence strongly indicates this connection is behind
Carrier-Grade NAT.

Recommendations

• Request a Public IPv4 address from your ISP
• Use Tailscale or another WireGuard-based mesh VPN for inbound access
• Use Cloudflare Tunnel to expose services without port forwarding
• Use a VPS reverse proxy as a relay for inbound connections
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

If you self-host anything at home -- a game server, Plex, a security
camera NVR, a personal website -- and inbound connections mysteriously
don't work despite correct port forwarding, there's a good chance your ISP
has put you behind Carrier Grade NAT (CGNAT). CGNAT Inspector diagnoses
this quickly and explains *why*, showing you the actual evidence rather
than a black-box yes/no.

It's built as a modular, testable, ShellCheck-clean Bash project (not a
single monolithic script), with detection, scoring, reporting, and
networking kept in separate files so each can be understood and unit
tested independently. See
[`docs/how-it-works.md`](docs/how-it-works.md) for the full technical
explanation, including the scoring weights.

## Features

- ✅ Correctly distinguishes **LAN IP**, **Gateway**, **Router WAN**
  (UPnP-only, never guessed from the local interface), and **Public
  IPv4**
- ✅ Detect Carrier Grade NAT (RFC 6598, `100.64.0.0/10`)
- ✅ Detect a private/CGNAT router WAN address (RFC 1918 + RFC 6598)
- ✅ Multi-provider public IPv4 lookup (5 independent services, with
  retries) -- reports `Unavailable` (not a misleading `Unknown`) only
  after every provider fails
- ✅ STUN (RFC 5389) cross-check of your public address, independent of
  HTTP-based lookups, implemented in pure Bash
- ✅ Traceroute backbone analysis (multiple private/CGNAT hops, path
  transitions) -- used only as supporting evidence, never the sole basis
  for a conclusion
- ✅ Distinct `DNS_FAILURE` status, separate from "no internet"
- ✅ Detect IPv6 availability and public IPv6 address
- ✅ **Evidence-based confidence scoring** (0-100): missing data
  contributes uncertainty, never false-positive evidence
- ✅ Three-tier status: `Inconclusive` / `Possible CGNAT` / `CGNAT
  Detected` -- never a confident conclusion from weak evidence
- ✅ Full evidence checklist and a plain-English conclusion sentence in
  every report
- ✅ Human-readable colorized output *and* machine-readable `--json`
  output
- ✅ Automatic optional-dependency checking (never hard-fails on missing
  extras)
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
| `miniupnpc` (`upnpc`) | Router WAN IP via UPnP | Router WAN reported as `Unknown` |
| `jq` | Pretty-printing JSON in tests/tooling | JSON is still emitted validly without it |
| `dig` | DNS sanity check | Falls back to `getent`/`curl` |
| `od` | STUN response parsing (coreutils; essentially always present) | STUN evidence skipped |

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
| `--no-upnp` | Skip UPnP router WAN IP query |

## Detection logic

CGNAT Inspector gathers independent signals and combines them into a
weighted confidence score -- see
[`docs/how-it-works.md`](docs/how-it-works.md) for the full breakdown.
Summary:

1. **Router WAN inspection** (UPnP only) -- is it private/CGNAT space?
2. **Public IPv4 lookup** (5 providers) -- does it differ from the Router WAN?
3. **STUN cross-check** -- does the UDP-observed address differ from the HTTP-observed one?
4. **Traceroute backbone analysis** -- are 2+ hops beyond your gateway still private/CGNAT space?
5. **IPv6 availability** -- informational; often a workaround regardless of your CGNAT status.

### Confidence scoring

| Signal | Weight |
|--------|--------|
| Router WAN confirmed private/CGNAT | +35 |
| Router WAN could not be determined | +15 |
| Public IPv4 differs from Router WAN | +20 |
| Public IPv4 could not be determined | +10 |
| Traceroute shows a private/CGNAT backbone | +20 |
| STUN-observed address differs from HTTP-observed address | +15 |
| No public IPv6 available | +5 |
| Two or more strong signals agree (bonus) | +10 |

| Score | Status |
|-------|--------|
| 0-39 | Inconclusive |
| 40-79 | Possible CGNAT |
| 80-100 | CGNAT Detected |

Missing data (Router WAN or Public IPv4 unavailable) always scores its
smaller uncertainty weight, never the full "confirmed" weight -- this is
the core false-positive guard. A definitive `PUBLIC` result additionally
requires the Router WAN to be known, non-private, and matching the
Public IPv4 -- not just a low score.

## JSON output

```bash
cgnat-inspector --json
```

```json
{
  "status": "POSSIBLE_CGNAT",
  "confidence": 55,
  "local_ip": "192.168.1.15",
  "gateway": "192.168.1.1",
  "router_wan": null,
  "public_ip": null,
  "ipv6": null,
  "evidence": [
    { "description": "Internet connectivity confirmed", "present": true },
    { "description": "Router WAN address obtained", "present": false },
    { "description": "Traceroute shows a private/CGNAT backbone", "present": true }
  ],
  "conclusion": "The available evidence suggests the connection may be behind Carrier-Grade NAT. Additional information (such as the router WAN address or a confirmed public IPv4) is required before making a definitive determination.",
  "recommendations": [
    "Request a Public IPv4 address from your ISP",
    "Use Tailscale or another WireGuard-based mesh VPN for inbound access"
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
    echo "You have a confirmed public IP."
else
    echo "Some form of NAT/CGNAT (or connectivity issue) detected (exit code $?)."
fi
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Public IPv4 confirmed (No CGNAT) |
| 1 | CGNAT Detected |
| 2 | Possible CGNAT |
| 3 | Inconclusive |
| 4 | Internet unreachable |
| 5 | DNS failure |
| 6 | Internal error |

## Troubleshooting

See [`docs/troubleshooting.md`](docs/troubleshooting.md) for solutions to
common issues (missing dependencies, blocked ICMP, DNS failures, UPnP not
responding, empty traceroute, STUN not resolving, etc.).

## FAQ

See [`docs/faq.md`](docs/faq.md) for answers to common questions about
what CGNAT is, why the tool reports "Possible CGNAT" instead of a
confident yes/no, what STUN is for, and what data this tool sends (and
doesn't send) over the network.

## Screenshots

See the [`screenshots/`](screenshots/) directory. Contributions of
real-world screenshots (with IPs redacted or replaced with documentation
ranges) are welcome via PR.

## Contributing

Contributions are welcome! Please read
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the project layout, code style,
and how to add a new evidence signal, CLI flag, or test. Every change
should keep the project ShellCheck-clean and pass `./tests/run-tests.sh`.

## License

Released under the [MIT License](LICENSE).
