# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Detection engine rewritten to be evidence-based rather than
  single-signal.** A new weighted scoring engine (`detect_compute_score`
  in `lib/detect.sh`) combines several independent signals, each scored
  based on both *whether it's known* and *what it shows*, so missing data
  can no longer be mistaken for confirmed CGNAT evidence.
- **Status model expanded from a binary-ish result to three confidence
  tiers**: `Inconclusive` (0-39%), `Possible CGNAT` (40-79%), `CGNAT
  Detected` (80-100%), plus `Public`, `Internet Unreachable`, `DNS
  Failure`, and `Internal Error`.
- **Exit code table redefined** to match the new status model (`0`
  Public / `1` CGNAT Detected / `2` Possible CGNAT / `3` Inconclusive /
  `4` Internet unreachable / `5` DNS failure / `6` Internal error).
  Missing-dependency failures now map to `6` rather than a dedicated
  code, and the previous `DOUBLE_NAT` / `ROUTER_UNREACHABLE` statuses
  were folded into the evidence engine and `NO_INTERNET` respectively.
- Every report now includes a full **Evidence** checklist and a
  plain-English **Conclusion** sentence, generated from the same
  underlying data in both human and `--json` output so they can never
  drift out of sync.

### Fixed
- **Router WAN detection no longer reports the local LAN interface
  address as if it were the WAN address.** "Router WAN" is now
  obtained exclusively via a live UPnP/IGD query; if unavailable, it is
  honestly reported as `Unknown` rather than guessed.
- Public IPv4 unavailability is now reported as `Unavailable` (lookups
  were attempted and failed), distinct from `Unknown` (not checked).

### Added
- Multi-provider public IPv4 lookup expanded to 5 independent services
  (added `checkip.amazonaws.com`, `ipv4.icanhazip.com`), each retried
  before falling through to the next provider.
- STUN (RFC 5389) public-address discovery, implemented in pure Bash
  (`/dev/udp` + `od`), used as an independent cross-check against the
  HTTP-observed public IP. Fully unit-tested against hand-crafted wire
  fixtures in the new `tests/test-stun.sh`, with no live network
  required for the parser tests.
- Distinct `DNS_FAILURE` status/exit code, separate from "no internet",
  via a new `net_dns_resolves` check.
- Traceroute analysis rewritten (`tr_analyze`) to classify multiple hops
  and require **two or more** private/CGNAT hops beyond the gateway
  before contributing evidence (a single hop is treated as noise), and
  to track public/private path transitions.
- `docs/how-it-works.md` rewritten to document the scoring engine, its
  weights, and the false-positive-avoidance rationale in detail.

## [1.0.0] - 2026-07-02

### Added
- Initial public release.
- Multi-signal CGNAT detection: CGNAT range (RFC 6598), RFC1918 private WAN,
  WAN-vs-public IP comparison, and traceroute hop analysis.
- Double NAT detection via UPnP/IGD router WAN IP query.
- IPv4 and IPv6 public address detection.
- Weighted confidence scoring (0-100) with labeled bands.
- Human-readable formatted console output with ANSI colors
  (auto-disabled on redirect or in `--json` mode).
- `--json` machine-readable output mode, including optional
  `--traceroute` hop data.
- CLI flags: `--help`, `--version`, `--json`, `--verbose`, `--debug`,
  `--quiet`, `--ipv4-only`, `--ipv6-only`, `--traceroute`, `--no-upnp`.
- Documented exit code table (0-6) for scripting/automation use.
- Modular library architecture under `lib/` (colors, utils, network,
  detect, traceroute, json, output, version).
- Pure-Bash IP arithmetic (no hard dependency on `ipcalc`).
- `install.sh` / `uninstall.sh` for `/usr/local/bin` installation.
- Full Bash test suite (`tests/run-tests.sh`) covering IP arithmetic,
  JSON encoding, and detection/scoring logic.
- GitHub Actions workflows for ShellCheck linting and running the test
  suite on every push/PR, plus a tag-triggered release workflow.
- Complete documentation: `docs/how-it-works.md`, `docs/api.md`,
  `docs/faq.md`, `docs/troubleshooting.md`.

[Unreleased]: https://github.com/giftbalogun/cgnat-inspector/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/giftbalogun/cgnat-inspector/releases/tag/v1.0.0
