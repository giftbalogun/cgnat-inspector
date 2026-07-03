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
    "Use Cloudflare Tunnel to expose services without port forwarding",
    "Consider a cheap VPS with a public IP as a reverse-proxy relay"
  ]
}
```

When `--traceroute` is passed, an additional `traceroute` field is
included:

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

| Field                 | Type            | Description |
|------------------------|-----------------|-------------|
| `status`               | string          | One of `PUBLIC`, `CGNAT`, `DOUBLE_NAT`, `NO_INTERNET`, `ROUTER_UNREACHABLE`. |
| `confidence`            | integer (0-100) | Weighted CGNAT confidence score. See `docs/how-it-works.md`. |
| `local_ip`              | string or null  | This machine's local IPv4 address. |
| `gateway`               | string or null  | Default gateway IPv4 address. |
| `wan_ip`                | string or null  | Router's WAN-facing IPv4 address (via UPnP if available, otherwise a heuristic fallback). |
| `public_ip`             | string or null  | Publicly observed IPv4 address, as seen by external echo services. |
| `ipv6`                  | string or null  | Public IPv6 address, if available; `null` otherwise. |
| `private_wan`           | boolean         | `true` if `wan_ip` falls in an RFC1918 private range. |
| `cgnat`                 | boolean         | `true` if `wan_ip` falls in `100.64.0.0/10` (RFC 6598). |
| `double_nat`            | boolean         | `true` if the router's own UPnP-reported external IP is itself private/CGNAT. |
| `traceroute_private`    | boolean         | `true` if any traceroute hop beyond the gateway is private/CGNAT space. |
| `traceroute`            | array (optional)| Present only with `--traceroute`. Array of `{"hop": N, "ip": "..."}`. |
| `recommendations`       | array of strings| Human-readable suggested next steps based on the result. |

## Exit codes

`--json` mode uses the exact same exit code table as normal mode -- check
`$?` after the call for scripting, no need to parse the `status` field if
you just need a pass/fail signal:

| Code | Meaning              |
|------|----------------------|
| 0    | Public IP            |
| 1    | CGNAT                |
| 2    | Double NAT           |
| 3    | Internet unreachable |
| 4    | Missing dependency   |
| 5    | Router unreachable   |
| 6    | Unknown error        |

## Example: shell scripting

```bash
#!/usr/bin/env bash
result=$(cgnat-inspector --json 2>/dev/null)
status=$(echo "$result" | jq -r '.status')

if [[ "$status" == "CGNAT" ]]; then
    echo "CGNAT detected -- falling back to Cloudflare Tunnel"
    systemctl start cloudflared
fi
```

## Example: cron-based monitoring

```bash
# Alert if CGNAT status changes from the last known state.
*/30 * * * * /usr/local/bin/cgnat-inspector --json 2>/dev/null > /var/log/cgnat-status.json
```

## Notes on stability

The JSON schema is considered stable as of v1.0.0: existing fields will
not be removed or change type in a minor/patch release. New fields may be
added. Always parse the response as an object and access fields by name
(e.g. via `jq`) rather than relying on field order or an exact byte-for-byte
match.
