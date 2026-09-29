# Torrent client peer refresh and table parity

## Peer snapshot failure

Upstream `hayase-app/torrent-client/torrent/info.ts` returns speedometer's
fractional `wire.downloadSpeed()` / `wire.uploadSpeed()` values. Native
`WebTorrentPeerInfo.SpeedInfo` decodes unsigned integers. One fractional rate
rejects the whole peer array. Previously the failed refresh was applied as an
empty array, making connected peers disappear.

The bridge now normalizes byte counters and rates at its native transport
boundary, using the same conversion as Overview. Failed peer refreshes preserve
the last successful snapshot; successful empty snapshots still remove peers.
Changing the active torrent clears the previous peers. Failures remain logged
for diagnosis rather than being silently indistinguishable from an empty swarm.

## Source comparison

Reference: `interface/src/lib/components/ui/torrentclient` and
`interface/src/routes/app/client/+layout.svelte`.

- Overview: checked route padding, sidebar breakpoint, section spacing, status
  badges and progress presentation against the existing implementation.
- Files: corrected table column gaps, vertical cell padding, progress spacing
  and track color, empty-state wording and ascending/descending sort cycling.
- Peers: corrected horizontal scroll width resolution, column gaps, progress
  intrinsic sizing and label constraints, track color, speed icon spacing and
  sort cycling, in addition to the RPC/snapshot fix.
- Trackers: corrected column spacing consistently with the shared header.
- Library: corrected column spacing and minimum scroll width, cell padding,
  status/date text size, compact episode labels and name-only search semantics.
- Settings remains a link to the existing client settings page, as in interface.

This is not a claim of complete pixel or functional identity: native sort menus,
library confirmation/promise notifications and expired-metadata date indicators
still differ from web. Legacy LibTorrent peer data is outside this WebTorrent
fix. No Apple toolchain or device is available in this workspace.

## Validation

Inline Node regression exercised the actual peerInfo bridge branch with fractional
rates, zero/nonfinite rates, missing seeder flag, an empty snapshot and a rejected
request. JavaScript syntax and whitespace checks passed.

Device checks still required: open Peers during active downloading (not just
seeding), switch torrents, disconnect peers, and inspect all tables on compact
and regular widths. Confirm that rates update without the list disappearing and
that horizontal scrolling reaches every column.
