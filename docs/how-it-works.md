# How It Works

CGNAT Inspector never concludes CGNAT from a single signal. Instead, it
gathers several independent facts about your network and combines them
into an **evidence-based confidence score**. This document explains each
test, the scoring engine, and why the design deliberately avoids false
positives.

## Why evidence-based, not a single yes/no check

An earlier design treated a single strong-looking signal (e.g. "the
router's WAN address looks private") as proof of CGNAT. In practice that
produces false positives: the router might simply not have obtained its
lease yet, UPnP might be misreporting, or a lookup service might be
temporarily down. The current design instead:

1. Gathers several independent signals.
2. Weighs each one, including a smaller weight for "we don't know" (so
   missing data nudges the result toward **Inconclusive**, never toward a
   false **CGNAT Detected**).
3. Only reaches a strong conclusion once multiple signals corroborate
   each other.

## 1. LAN IP, Gateway, Router WAN -- three different addresses

CGNAT Inspector is careful to never conflate these:

- **LAN IP** (`net_get_local_ip`): this machine's own address on its local
  network (e.g. `192.168.1.10`). Never reported as a WAN or public
  address.
- **Gateway** (`net_get_gateway`): your router's LAN-facing address.
- **Router WAN** (`net_get_router_wan_ip`): the address your router
  believes it has been assigned by your ISP, obtained **only** via a live
  UPnP/IGD query (`upnpc -s`, from `miniupnpc`). If UPnP is unavailable,
  disabled, or doesn't respond, this is reported as `Unknown` -- it is
  **never** filled in with the LAN IP or any other guessed value. Earlier
  versions of this tool mistakenly reported the local interface address
  as "WAN"; this has been fixed.

## 2. Public IPv4 detection

**Function:** `net_get_public_ipv4`

Queries multiple independent HTTP(S) echo services, in order, retrying
each one before moving to the next:

- `api.ipify.org`
- `ifconfig.me/ip`
- `icanhazip.com`
- `checkip.amazonaws.com`
- `ipv4.icanhazip.com`

Each request is time-limited (`CURL_TIMEOUT`, default 5s). If every
provider fails, the tool reports `Public IPv4: Unavailable` -- explicitly
distinct from `Unknown`, since "unavailable" means lookups were attempted
and failed, not that the check was skipped.

## 3. DNS failure vs. no internet

**Function:** `net_dns_resolves`

It's possible to have raw IP connectivity (e.g. you can ping `1.1.1.1`)
while DNS resolution itself is broken. CGNAT Inspector checks this
separately (via `getent hosts`, falling back to `dig`, falling back to a
full HTTPS request) and reports a distinct `DNS_FAILURE` status/exit code
rather than lumping it in with "no internet" -- the fix is different
(check your resolver configuration) from a genuine outage.

## 4. STUN-based public address (independent second opinion)

**Functions:** `net_stun_get_public_ip`, `stun_query`, `stun_parse_response`

In addition to HTTP-based lookups, CGNAT Inspector performs a raw UDP
[STUN](https://www.rfc-editor.org/rfc/rfc5389) (RFC 5389) Binding Request
to a public STUN server and parses the XOR-MAPPED-ADDRESS (or legacy
MAPPED-ADDRESS) attribute from the response. This is implemented in pure
Bash (`/dev/udp` plus `od`), so it introduces no new required dependency.

Comparing the STUN-observed address against the HTTP-observed address is
useful supporting evidence: if they disagree, UDP and TCP/HTTPS traffic
are very likely taking different NAT bindings, which is common under some
CGNAT deployments. STUN is always best-effort -- any failure (blocked
UDP, no `/dev/udp` support, malformed response) simply omits this piece
of evidence, never a hard error.

## 5. Traceroute analysis (supporting evidence only)

**Functions:** `tr_run_traceroute`, `tr_analyze`

Runs a short traceroute toward a public anycast address (`1.1.1.1`) and
classifies each hop beyond your gateway as private/CGNAT or public,
tracking:

- Count of private/CGNAT hops and public hops
- Whether the path shows a "private backbone" (**two or more** private/
  CGNAT hops beyond the gateway -- a single private hop is treated as
  noise, not evidence, to avoid over-weighting a fluke result)
- Public-to-private and private-to-public transitions along the path

Traceroute is **never** the sole basis for a CGNAT conclusion; it
contributes at most 20 of the 100 possible confidence points.

## 6. IPv6 availability

**Functions:** `net_has_ipv6_route`, `net_get_public_ipv6`

CGNAT is fundamentally an IPv4 phenomenon -- most ISPs don't apply it to
IPv6 traffic, since IPv6's address space doesn't need conserving in the
same way. A lack of public IPv6 contributes a small amount of uncertainty
weight (+5) and is called out in recommendations as a possible mitigation
regardless of your IPv4 CGNAT status.

## The scoring engine

**Function:** `detect_compute_score` (`lib/detect.sh`)

| Signal | Weight | Notes |
|--------|--------|-------|
| Router WAN confirmed private/CGNAT | +35 | Strongest single signal |
| Router WAN could not be determined | +15 | Uncertainty, not evidence of CGNAT |
| Public IPv4 differs from Router WAN | +20 | Only scored when both are known |
| Public IPv4 could not be determined | +10 | Uncertainty, not evidence of CGNAT |
| Traceroute shows a private/CGNAT backbone (>=2 hops) | +20 | Supporting evidence only |
| STUN-observed address differs from HTTP-observed address | +15 | Only scored when STUN succeeded |
| No public IPv6 available | +5 | Minor; IPv6 usually bypasses CGNAT anyway |
| Two or more of the above **strong** signals agree | +10 bonus | "Multiple independent indicators" |

The score is capped at 100. Note the asymmetry: a signal that is
**unknown** (router WAN or public IP couldn't be determined) scores a
smaller "uncertainty" weight, not the full "confirmed private/differs"
weight. This is the key false-positive guard: missing data alone can
reach at most 25 points (15 + 10), which is comfortably within the
**Inconclusive** band, never **Possible CGNAT** or **CGNAT Detected**.

## Status thresholds

| Score | Status |
|-------|--------|
| 0-39 | Inconclusive |
| 40-79 | Possible CGNAT |
| 80-100 | CGNAT Detected |

## Overall status determination

**Function:** `detect_final_status`

Evaluated in this order (each step short-circuits the ones below it):

1. **No internet, or gateway unreachable** -> `NO_INTERNET` (exit 4).
   If basic connectivity is broken, nothing else can be determined.
2. **DNS not resolving** (but connectivity otherwise works) ->
   `DNS_FAILURE` (exit 5).
3. **Definitive public confirmation**: the router WAN is known, is *not*
   private/CGNAT, a public IPv4 was obtained, and the two match ->
   `PUBLIC` (exit 0), regardless of any leftover uncertainty score from
   e.g. traceroute noise.
4. Otherwise, the numeric score (see above) is mapped through the
   threshold table to `INCONCLUSIVE`, `POSSIBLE_CGNAT`, or
   `CGNAT_DETECTED`.

## Evidence checklist

**Function:** `detect_build_evidence`

The human-readable "Evidence" section and the JSON `evidence` array are
both generated from the exact same function, so they can never drift out
of sync. Each line is a plain boolean statement (✔ = true, ✖ = false);
comparison-dependent lines (e.g. "Public IPv4 differs from Router WAN")
are omitted entirely when the comparison wasn't possible, rather than
misleadingly shown as `false`.
