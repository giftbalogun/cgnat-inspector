# How It Works

CGNAT Inspector never relies on a single signal. Instead, it gathers several
independent facts about your network and combines them into a weighted
confidence score. This document explains each test in detail.

## 1. Local IP detection

**Function:** `net_get_local_ip` (`lib/network.sh`)

Uses `ip -4 route get 1.1.1.1` to ask the kernel which local address would be
used to reach the internet, then falls back to the first global-scope IPv4
address on any interface if that fails. This is the address your machine
sees on its own network interface (e.g. `192.168.1.10`).

## 2. Gateway detection

**Function:** `net_get_gateway`

Reads the default route via `ip -4 route show default` and extracts the
`via` address. This is your router's LAN-facing address.

## 3. Internet connectivity

**Function:** `net_check_internet`

Pings several well-known, highly available anycast addresses
(`1.1.1.1`, `8.8.8.8`, `9.9.9.9`). If ICMP is blocked entirely, falls back to
an HTTPS request via `curl`. This is a prerequisite check: if it fails,
CGNAT Inspector reports `NO_INTERNET` immediately rather than guessing.

## 4. Gateway reachability

**Function:** `net_check_gateway_reachable`

A simple ping to the detected gateway. If your machine can reach the
internet but not the gateway (unusual, but possible with certain routing
setups), the tool reports `ROUTER_UNREACHABLE`.

## 5. Public IPv4 lookup

**Function:** `net_get_public_ipv4`

Queries multiple independent "echo" services (ipify, ifconfig.me,
icanhazip.com) and uses the first valid response. Multiple providers are
used so a single service outage doesn't produce a false result.

## 6. WAN IP determination

The "WAN IP" is the address your router believes it has been assigned by
your ISP. CGNAT Inspector determines this two ways, in order of
preference:

1. **UPnP/IGD query** (`net_get_wan_ip_upnp`, requires `upnpc` from
   `miniupnpc`): asks the router directly for its `ExternalIPAddress`. This
   is the most accurate signal, because it comes straight from the router.
2. **Fallback heuristic**: if UPnP is unavailable or disabled
   (`--no-upnp`), and the local machine's own IP is *not* private/CGNAT
   space, the tool assumes this host has direct WAN-facing visibility
   (common when running on a modem in bridge mode). Otherwise the local
   (private) IP is reported as the WAN IP for transparency, but this case
   contributes less certainty to the final score than a real UPnP answer.

## 7. CGNAT range check (RFC 6598)

**Function:** `detect_is_cgnat_range`

Checks whether the WAN IP falls inside `100.64.0.0/10` -- the address block
IANA reserved specifically for carrier-grade NAT deployments (RFC 6598).
**If your WAN IP is in this range, you are behind CGNAT, full stop.** This
is the single strongest signal and carries the highest score weight (+40).

## 8. RFC 1918 private address check

**Function:** `detect_is_private_ipv4`

Checks whether the WAN IP falls inside any RFC 1918 private range:

- `10.0.0.0/8`
- `172.16.0.0/12`
- `192.168.0.0/16`

A WAN IP in these ranges (as opposed to a LAN IP, which is expected to be
private) means there is at least one more layer of NAT between your router
and the public internet -- your ISP's equipment is handing your router a
private address instead of a public one. Weighted +30.

## 9. WAN vs. Public IP comparison

**Function:** `detect_wan_matches_public`

Compares the router's reported WAN IP against the publicly-observed IP (as
seen by the internet). If they differ, there is NAT happening somewhere
between your router and the public internet that isn't visible to the
router itself. Weighted +20.

## 10. Traceroute analysis

**Functions:** `tr_run_traceroute`, `tr_has_private_hop_beyond_gateway`

Runs a short traceroute toward a public anycast address (`1.1.1.1`) and
inspects each hop beyond your gateway. If any of those early hops are
*also* private or CGNAT addresses, your traffic is passing through
ISP-internal NAT infrastructure before it reaches the real internet --
another classic CGNAT fingerprint. Weighted +10.

## 11. Double NAT detection

**Function:** `detect_double_nat`

If UPnP is available and the router's *own* reported external IP is itself
private or CGNAT space, then there is another NAT device between your
router and the internet (e.g. an ISP modem doing NAT *and* your own router
also doing NAT). This is reported as a distinct `DOUBLE_NAT` status,
separate from plain CGNAT, since the fix (bridge mode) is different.

## 12. IPv6 detection

**Functions:** `net_has_ipv6_route`, `net_get_public_ipv6`

Checks for a usable IPv6 route and, if present, queries an IPv6-only echo
service. IPv6 traffic on most ISPs bypasses CGNAT entirely (there's enough
address space that NAT isn't needed), so having working IPv6 is one of the
most reliable workarounds regardless of your IPv4 situation. This is
reported informationally and factored into recommendations, not into the
CGNAT confidence score itself (CGNAT is fundamentally an IPv4 phenomenon).

## Putting it together: confidence scoring

Each boolean signal contributes a fixed weight if true:

| Signal                              | Weight |
|--------------------------------------|--------|
| WAN IP in CGNAT range (100.64/10)   | +40    |
| WAN IP is RFC1918 private            | +30    |
| WAN IP differs from public IP        | +20    |
| Traceroute hop beyond gateway is private/CGNAT | +10 |

The total (0-100, capped) maps to a label:

| Score  | Label              |
|--------|--------------------|
| 0-20   | Probably Public    |
| 21-50  | Possible CGNAT     |
| 51-80  | Likely CGNAT       |
| 81-100 | Confirmed CGNAT    |

Separately, the final **status** (`PUBLIC`, `CGNAT`, `DOUBLE_NAT`,
`NO_INTERNET`, `ROUTER_UNREACHABLE`) is derived from the same underlying
booleans via `detect_final_status`, and drives both the exit code and the
human-readable STATUS line. The numeric confidence score is a supplementary
signal of *how strong* the evidence is, not the sole basis for the status
determination.
