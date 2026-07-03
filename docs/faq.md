# FAQ

### What is CGNAT?

Carrier Grade NAT (CGNAT), defined in RFC 6598, is a technique ISPs use to
share a single public IPv4 address among many customers. Instead of giving
your router a public IP directly, the ISP hands out addresses from the
`100.64.0.0/10` block, and does the "real" NAT translation to a public IP
somewhere inside their own network. IPv4 address exhaustion is the main
driver: there simply aren't enough public IPv4 addresses for every
household to have one anymore.

### Why does CGNAT matter to me?

If you're behind CGNAT, you generally **cannot**:

- Port forward to self-host a game server, web server, Plex, security
  camera NVR, etc.
- Get inbound connections to work for peer-to-peer applications
- Reliably use your own domain to reach a home server

Because you don't control the public-facing IP -- your ISP does, and it's
shared with other customers.

### How is this different from a normal home router NAT?

Your home router also does NAT (translating your LAN's private IPs to one
IP on its WAN side) -- that's completely normal and not what this tool
flags as a problem. CGNAT is a **second, ISP-side NAT layer** on top of
your router's own NAT. It's effectively "NAT of NAT," and it's outside your
control since it happens on ISP equipment.

### My WAN IP starts with 100. Is that always CGNAT?

The `100.64.0.0/10` block (100.64.0.0 - 100.127.255.255) is reserved
specifically for carrier-grade NAT under RFC 6598 and is never valid as a
public internet address. If your router's WAN IP is in this range, yes,
you are behind CGNAT.

### My WAN IP starts with 10, 172.16-31, or 192.168. Is that CGNAT too?

Those are RFC 1918 *private* ranges, not the RFC 6598 CGNAT range
specifically -- but seeing one of them as your *router's WAN* address
(as opposed to your LAN) still means there's another NAT layer between
your router and the internet. CGNAT Inspector flags this as
`private_wan: true` and treats it as a strong CGNAT/double-NAT signal,
even though it's technically a different address block than the "official"
CGNAT range.

### Can I fix CGNAT myself?

Not directly -- it's implemented on your ISP's network, not your own
equipment. Your options are:

1. **Ask your ISP for a public/static IPv4 address.** Many ISPs offer this
   as a paid add-on, or sometimes for free if you ask (or threaten to
   switch providers).
2. **Use IPv6.** Most CGNAT deployments don't apply to IPv6 traffic, since
   IPv6's address space is enormous. If your ISP supports IPv6 and your
   services/clients support it too, you can often bypass CGNAT entirely
   for IPv6-capable connections.
3. **Use a reverse tunnel / mesh VPN.** Tools like Tailscale, Cloudflare
   Tunnel, or a cheap VPS running WireGuard/ngrok-style relays let you
   expose services without needing any inbound port forward at all.

### Why does the tool need internet access to run?

Several tests inherently require reaching outside your network: querying
public "what's my IP" echo services, running a traceroute to a public
target, and pinging well-known hosts to confirm connectivity. Without
internet access, CGNAT Inspector can still tell you your local IP and
gateway, but reports `NO_INTERNET` and exits with code 3 rather than
guessing at the rest.

### Does this tool send any of my data anywhere?

CGNAT Inspector makes outbound requests only to: public IP echo services
(ipify.org, ifconfig.me, icanhazip.com, ident.me), well-known ping targets
(1.1.1.1, 8.8.8.8, 9.9.9.9), and your own local router (for UPnP queries).
It does not send telemetry to any project-controlled server -- there isn't
one. Everything runs locally on your machine.

### Why isn't `jq`/`ipcalc`/`miniupnpc` required?

The tool is designed to run on minimal systems (routers, containers, thin
VMs) where these tools may not be installed. All IP-range math is
implemented in pure Bash/awk (see `lib/utils.sh`), and JSON is
hand-assembled with proper escaping (see `lib/json.sh`). `jq` is only used
opportunistically to pretty-print JSON if it happens to be present, and
`upnpc`/`ipcalc`/`dig` are used only to *improve* accuracy when available,
never required.

### The tool says "WAN differs from Public IP" but I'm not behind CGNAT. Why?

This can happen with certain VPN configurations, if UPnP is reporting a
stale cached value, or on networks with asymmetric/policy routing. Try
running with `--no-upnp` to fall back to the simpler heuristic, and
`--verbose` to see each intermediate value the tool gathered.

### Can I run this on a router directly (e.g. via OpenWrt)?

Yes, as long as `bash`, `curl`, `ip`, `awk`, `grep`, and `sed` are
available (OpenWrt's default `ash`/BusyBox environment may need `bash`
installed separately via `opkg install bash`).
