# API / JSON Reference

CGNAT Inspector is primarily a CLI tool, but `--json` mode gives you a
stable, scriptable interface for integrating detection results into
monitoring dashboards, homelab automation, or CI pipelines.

## Invocation

```bash
cgnat-inspector --json
```

Colors are automatically disabled in JSON mode. Combine with other flags
as needed:

```bash
cgnat-inspector --json --ipv4-only --no-upnp
cgnat-inspector --json --traceroute   # includes raw hop data
```

## Output schema

A single JSON object is printed to stdout. All logging (`--verbose`,
`--debug`, warnings) goes to stderr, so `cgnat-inspector --json 2>/dev/null`
gives you clean, parseable output.

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
    { "description": "Default gateway reachable", "present": true },
    { "description": "DNS resolution working", "present": true },
    { "description": "Router WAN address obtained", "present": false },
    { "description": "Public IPv4 address obtained", "present": false },
    { "description": "Traceroute shows a private/CGNAT backbone", "present": true },
    { "description": "Public IPv6 available", "present": false },
    { "description": "Multiple independent indicators corroborate", "present": false }
  ],
  "conclusion": "The available evidence suggests the connection may be behind Carrier-Grade NAT. Additional information (such as the router WAN address or a confirmed public IPv4) is required before making a definitive determination.",
  "recommendations": [
    "Request a Public IPv4 address from your ISP",
    "Use Tailscale or another WireGuard-based mesh VPN for inbound access",
    "Use Cloudflare Tunnel to expose services without port forwarding",
    "Use a VPS reverse proxy as a relay for inbound connections",
    "Enable IPv6 if your ISP supports it; IPv6 traffic typically bypasses CGNAT entirely"
  ]
}
```

When `--traceroute` is passed, an additional `traceroute` field is
included (and omitted entirely otherwise -- check `has("traceroute")`
rather than assuming an empty array):

```json
{
  "traceroute": [
    { "hop": 1, "ip": "192.168.1.1" },
    { "hop": 2, "ip": "100.91.0.1" },
    { "hop": 3, "ip": "100.91.0.254" },
    { "hop": 4, "ip": "102.89.44.10" }
  ]
}
```

### Field reference

| Field | Type | Description |
|-------|------|--------------|
| `status` | string | One of `PUBLIC`, `CGNAT_DETECTED`, `POSSIBLE_CGNAT`, `INCONCLUSIVE`, `NO_INTERNET`, `DNS_FAILURE`, `INTERNAL_ERROR`. |
| `confidence` | integer (0-100) | Evidence-based confidence score. `0` for `PUBLIC`, `NO_INTERNET`, and `DNS_FAILURE` (the score isn't meaningful for those statuses). See `docs/how-it-works.md`. |
| `local_ip` | string or null | This machine's LAN-side IPv4 address. |
| `gateway` | string or null | Default gateway IPv4 address. |
| `router_wan` | string or null | Router's real WAN-facing IPv4 address, obtained **only** via UPnP. `null` means genuinely unknown (`--no-upnp`, UPnP unavailable/disabled) -- it is never filled in with the LAN address. |
| `public_ip` | string or null | Publicly observed IPv4 address (HTTP echo services). `null` means every provider failed ("Unavailable"). |
| `ipv6` | string or null | Public IPv6 address, if available. |
| `evidence` | array of objects | `{"description": string, "present": boolean}`. Comparison-dependent items (e.g. WAN-vs-public) are omitted entirely when the comparison wasn't possible. |
| `traceroute` | array (optional) | Present only with `--traceroute`. Array of `{"hop": N, "ip": "..."}`. |
| `conclusion` | string | One-sentence, human-readable explanation of the status. |
| `recommendations` | array of strings | Suggested next steps based on the result. |

## Exit codes

`--json` mode uses the exact same exit code table as normal mode -- check
`$?` after the call for scripting, no need to parse the `status` field if
you just need a pass/fail signal:

| Code | Meaning |
|------|---------|
| 0 | Public IPv4 confirmed (No CGNAT) |
| 1 | CGNAT Detected |
| 2 | Possible CGNAT |
| 3 | Inconclusive |
| 4 | Internet unreachable |
| 5 | DNS failure |
| 6 | Internal error |

## Example: shell scripting

```bash
#!/usr/bin/env bash
result=$(cgnat-inspector --json 2>/dev/null)
status=$(echo "$result" | jq -r '.status')

if [[ "$status" == "CGNAT_DETECTED" ]]; then
    echo "CGNAT detected -- falling back to Cloudflare Tunnel"
    systemctl start cloudflared
elif [[ "$status" == "POSSIBLE_CGNAT" ]]; then
    echo "Possible CGNAT -- see evidence for details:"
    echo "$result" | jq -r '.evidence[] | "\(.description): \(.present)"'
fi
```

## Example: cron-based monitoring

```bash
# Alert if CGNAT status changes from the last known state.
*/30 * * * * /usr/local/bin/cgnat-inspector --json 2>/dev/null > /var/log/cgnat-status.json
```

## Notes on stability

The JSON schema is considered stable as of the current release: existing
fields will not be removed or change type in a minor/patch release. New
fields may be added, and the set of `status` values may grow. Always
parse the response as an object and access fields by name (e.g. via `jq`)
rather than relying on field order or an exact byte-for-byte match.
