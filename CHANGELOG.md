# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nothing yet.

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
