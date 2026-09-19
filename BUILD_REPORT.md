# FoldBar build report

## macOS 27 compatibility candidate — 2026-09-19

Verified on macOS 27.0 (26A428) with Xcode 27.0 (27A266a), Swift 6.4, and
the macOS 27.0 SDK.

- Branch: `fix/macos-27-compatibility`.
- Debug app-hosted test run: passed; all 63 Swift Testing cases passed.
- Release build: passed with no source compiler warnings.
- Release binary: universal `x86_64` + `arm64`.
- Code-signature structural verification (`codesign --verify --deep --strict`): passed.
- Installed executable SHA-256:
  `e55f8778ee92ccd64df412867398178e2a4f7599ba15c214065488a6b3873b9f`.
- Installed-runtime check: the exact `/Applications/FoldBar.app` candidate
  launched successfully as PID 35259. An installed-app panel capture measured
  the CodexSquad glyph at `x=109...138` inside a cell centred at `x=123.5`;
  both its bounds and alpha-weighted centre resolve to `x=123.5`, and all three
  source dots are present without right-edge clipping. Clicking that proxy
  opened CodexSquad's real two-item status menu and produced no FoldBar alert.

macOS 27 no longer exposes each third-party menu extra as an individual
WindowServer or ScreenCaptureKit window. The candidate therefore selects a
public Accessibility inventory on macOS 27 and newer, keeps the existing
Core Graphics / ScreenCaptureKit window path on macOS 14–26, and uses public
Accessibility identities on macOS 27. A system-overflow item can retain an
Accessibility frame while no longer owning the pixels at that coordinate;
capturing the rectangle can therefore copy the native `«` control or another
system indicator. Before entering FoldBar's collapsed state, the candidate uses
the public native overflow control to expose the real status artwork, waits for
both geometry and rendered foreground pixels, captures those pixels, removes
the menu-bar background, and restores native overflow. The resulting in-memory
templates preserve the actual menu-bar glyph, aspect ratio, visual size, and
centering instead of substituting the owning application's icon. A
background-only capture is rejected and retried rather than cached as a blank
cell.

The managed items remain in the same left-to-right order as the real menu bar.
Near-square captured glyphs now place their alpha-weighted visual centre on the
nearest pixel-aligned canvas centre before SwiftUI lays them out. The canvas is
expanded with transparent pixels when necessary, so asymmetric artwork is not
clipped or shifted to the right; wide text meters retain their geometric crop.
Live capture timing showed that macOS 27 publishes the final Accessibility
frame within about 20 ms but does not finish sliding its pixels into that frame
until roughly 650 ms. FoldBar now waits for that compositor transition and
rejects any transitional capture whose foreground still touches an image edge.
Live activation also showed that Tauri dispatches `AXPress` and opens the real
status menu while returning `kAXErrorCannotComplete` because it does not
acknowledge the synchronous accessibility message in time. FoldBar now accepts
that result only after the existing process, bundle, ordinal, label, and live
frame checks have already resolved the exact target; unsupported or invalid
Accessibility actions still fail closed.
On macOS 27, the system-owned `«` control is the source of truth for real
overflow visibility. FoldBar no longer places a background or click-blocking
window over those coordinates; doing so reserved the same space twice and was
the cause of the reported empty menu-bar gap. The panel action is labelled
Close on macOS 27, while macOS 14–26 retain the legacy Expand behavior.

Accessibility scanning runs on a utility task and publishes a short-lived
MainActor cache. Synthetic item identifiers are deterministic and occupy a
reserved range. Before an Accessibility-backed proxy click or synthetic
Command-drag, FoldBar re-resolves the owning process, bundle identifier, item
ordinal, semantic label when needed, and live frame. Any mismatch fails closed
and leaves the real menu bar available for manual operation.

Live diagnosis reproduced all reported regressions and identified the former
188-point, layer-26 FoldBar mask as the empty region. A system-only baseline had
no gap. The macOS 27 native overflow boundary also explained the duplicates:
visible items had been classified relative to FoldBar's legacy separator rather
than MenuBarAgent's `«`. Final installed-app screenshots confirmed that the gap
is gone; the panel contains only the three native-hidden applications, while the
real menu bar contains a different visible set; and the panel glyphs are the
same CodexSquad four-diamond, ChatGPT knot, and Lemon hexagon shapes shown by the
system-expanded menu bar. The macOS 27 action reads Close. Closing the panel
leaves no FoldBar-owned on-screen window. The original pre-fix install remains
recoverable at
`~/.Trash/FoldBar.app.backup-20260919-154523`; the immediately preceding
installed candidate is recoverable at
`~/.Trash/FoldBar.app.backup-20260919-1958-axpress-fix`. Intermediate
candidates were also moved to the Trash rather than deleted.

Direct-drag acceptance used a temporary test status item so no real application
was reordered. With direct drag enabled, the item moved from the native-visible
frame at `x=1238` into the native-hidden frame at `x=987`; its trailing edge
aligned with the live `«` boundary at `x=1004.5`. Reopening FoldBar showed that
fourth item only in the panel. Terminating the temporary process removed it and
restored the user's original status-item set. No acceptance step changed the
user's real menu-bar order.

## Historical macOS 26 baseline

Verified locally on 2026-09-12 with Xcode 26.6 (17F113), Swift 6.3.3, and the macOS 26.5 SDK.

## Results

- Debug app-hosted test build: passed.
- Swift Testing: 45 tests passed.
- Release build: passed with no source compiler warnings.
- Release binary: universal `arm64` + `x86_64`.
- Deployment target: macOS 14.0.
- Bundle identifier: `local.foldbar.app`.
- Hardened runtime: enabled.
- Archive integrity (`unzip -t`): passed.
- Code-signature structural verification (`codesign --verify --deep --strict`): passed.
- Signing identity: Apple Development, team `42MUMXKY79`.

The `fix/promotion-drag` candidate additionally uses paced, non-coalesced
Command-drag events and verifies that a promoted item crossed the separator
before collapsing again. Its build and focused geometry/state tests pass.
The overflow panel also exposes a direct Expand action that reuses the existing
separator expansion path.
Appearance settings preserve the original material fallback, add a dark style,
and use the public high-transparency Liquid Glass effect on macOS 26 or newer.
The Liquid Glass style pins readable dark-scheme foregrounds over a subtle tint,
with lightly blurred cells and drop target; dark and compatibility styles use
separately tuned panel and cell contrast.
The overflow panel now uses a single `FoldBar` heading. Its icon slots are
square, a complete five-column row spans the same inner width as the promotion
drop target, and that target is slightly taller for a more balanced layout.
The content width is derived from the grid and centered with equal 16-point
panel insets. The larger heading has additional separation from the drop target,
and drag previews reuse the full-height cell surface instead of shrinking.
Captured icons render up to 28 points high inside the unchanged 46-point cells.
Drag previews add a blue cell tint and activate the promotion target's light-blue
fill and blue border as soon as dragging starts. Each drag's item-provider closure
restarts that state, including subsequent drags that reuse the same preview.
Hovering over the target only strengthens the blue fill; its label remains stable.
A short-lived drag task observes the left-button state and clears the highlight
within one 8 ms polling interval of mouse release, without waiting for a failed
drag image to return to its starting position. Liquid Glass cells use a slightly
stronger material blur.
The former compatibility material is presented as Light Mode with a modest white
overlay that reduces panel transparency.
Interactive cross-app promotion still requires confirmation on the real menu
bar; a rejected synthetic drag now leaves the bar expanded and reports the
manual fallback instead of appearing to succeed.
The `feat/panel-command-drag-import` candidate adds a panel-scoped active event
tap for user-initiated Command-drags that begin on a validated visible status
item. The original downward mouse sequence is consumed, a screenshot proxy
follows the pointer, and a drop inside the panel starts a second, menu-bar-only
Command-drag to the managed side. Source identity, panel coordinate conversion,
target geometry, and post-drag placement all fail closed. Cancelling outside the
panel performs no synthetic move. The event tap and proxy are torn down whenever
the panel closes.
The same candidate now rejects AppKit window numbers that cannot be represented
as `CGWindowID` values instead of trapping during panel opening. When an own
status item has no usable Core Graphics window ID, its horizontal frame is used
as a fallback exclusion so FoldBar cannot select its own trigger as an import
source.
The `feat/direct-menu-bar-drag-setting` candidate keeps Command-drag available
and adds an opt-in setting for unmodified menu-bar drags while the overflow
panel is open. A five-point movement threshold separates dragging from clicking;
an ordinary click is replayed once with an event marker after the panel closes.
Both the overflow panel and FoldBar's arrow accept a drop, with the arrow showing
an accent-colored target state. The setting is read on every new mouse-down, so
changes apply without reopening the panel.
The `fix/external-drag-preview-style` candidate renders menu-bar-originated drag
proxies with the same SwiftUI surface used by grid drag previews, including the
appearance-aware base fill, blue tint, blue border, corner radius, and icon
sizing. Visible import candidates are pre-captured when the panel opens and
refreshed when a drag starts. If no real image is ready, the proxy stays hidden
instead of briefly displaying the generic menu-bar placeholder.
The panel now derives its presentation order from the live hidden windows in
right-to-left order, placing the item nearest the menu-bar right first and the
farthest-left/system-overflow item last. Promotion temporarily reduces FoldBar's
trigger length to zero, and does the same to its separator only when more room
is needed, then waits for the source frame to settle inside the current
display's visible right-hand menu-bar segment before posting any event. Both own
lengths are restored before post-drag verification and on every early exit or
application quit. It deliberately avoids `isVisible = false`, which macOS can
persist across launches.
When no managed items are present, the panel no longer renders a separate empty
state title or description. The dashed drop zone expands through the remaining
content area while the non-empty five-column layout stays unchanged.
The current candidate targets the insertion point immediately left of FoldBar's
trigger when a proxy is dragged to “keep visible”. It only re-collapses after
the real status-item window is both on the separator's visible side and directly
adjacent to the trigger; a different landing position leaves the bar expanded
for manual correction.
Panel hover help no longer treats the macOS 26 Control Center host process as
the identity of every third-party item. While preparing the screenshot cache,
FoldBar resolves each public `AXMenuExtra` help, description, or owning-app name
on a utility task and matches it to the corresponding status window by center
position. Empty or generic Control Center metadata falls back to a neutral menu
bar item label.
Proxy activation now requires the complete live status window to fit inside the
display's visible menu-bar segment. It temporarily reduces FoldBar's trigger
width, and then its separator width only when necessary, so far-left managed
items can clear the notch without changing their saved order. Every exit path
restores both widths; a target that still cannot become fully clickable receives
no synthetic event and leaves the bar expanded for manual interaction.
The current late-item candidate monitors the collapsed managed section for new
window IDs, waits ten seconds for registration to settle, measures free space
beside FoldBar's trigger, and attempts at most two automatic placements. It
performs one delayed retry and requires three consecutive adjacency checks
before accepting a move. Whether placement succeeds or falls back to overflow,
the expanded section is recaptured so restarted items do not disappear from the
proxy cache. The overflow panel's Expand action now presents those cached,
clickable proxies across the usable menu-bar area immediately left of the
trigger instead of exposing the real hidden section. The expanded proxy strip
uses a fully transparent panel surface, so only the captured item proxies are
drawn and no separate light rectangular backdrop appears behind them.

## Packaged artifact

`dist/FoldBar-0.2.0-macOS.zip`

This checked-in ZIP predates the `fix/promotion-drag` candidate and was left
unchanged. It must not be used as evidence that the promotion fix is packaged.

SHA-256:

```text
d652429f6d76084038805948721a61c2a18a54b9361212f3581799874933c956
```

The packaged app is signed with the local Apple Development certificate so its privacy identity remains stable across local builds. It is **not** Developer ID signed or Apple-notarized, so it is not a public release artifact.

## Test scope

- macOS 26 status-window overflow discovery.
- Contiguity cutoff so a different display's status windows are not included.
- Menu-bar geometry validation before synthetic events.
- Negative X coordinates for displays left of the primary display.
- Promotion target geometry for insertion immediately left of the FoldBar trigger.
- Promotion targets the trigger's live frame after temporary width changes and
  remains trigger-anchored when earlier promoted items occupy the visible section.
- Post-drag visible-side and trigger-adjacency verification before re-collapsing.
- Accessibility hover-label priority, generic-host rejection, and status-window matching.
- Notch-overlap rejection for proxy-click forwarding.
- Command-drag source-window selection for menu-bar-to-panel import.
- Opt-in direct-drag modifier eligibility and five-point drag threshold.
- Panel and FoldBar-arrow import drop-target selection.
- Safe rejection of negative and out-of-range AppKit window numbers.
- Own-status-item frame fallback when no usable Core Graphics window ID exists.
- AppKit-to-Quartz panel coordinate conversion.
- Managed-side import target geometry and impossible-target rejection.
- Post-drag managed-side verification before re-collapsing.
- Defensive position snapshot merge and restore filtering.
- Expanded-section discovery used for flash-free pre-collapse caching.
- Left-to-right overflow-panel presentation order matching the real menu bar.
- macOS 27 native-overflow hidden/visible partition, fail-closed missing-boundary
  behavior, and language-independent expanded-state geometry.
- Native-size template rendering, internal detail contrast, transparent-margin
  trimming, non-clipping alpha-weighted optical centering for square glyphs,
  and rejection of compositor-transition frames clipped at a capture edge.
- AXPress result classification that preserves strict target resolution while
  accepting Tauri's dispatched-but-unacknowledged `cannotComplete` response.
- Visible menu-bar-segment validation, including overlapping X ranges on different displays.
- Adaptive one-, two-, and three-column spans for wide status items.
- Detection of newly registered managed-window IDs and free-space calculation
  for automatic placement.
- Menu-bar overlay clamping and proxy layout for the expanded presentation.
- Transparent expanded-proxy placement before existing visible status items,
  including fail-closed handling when those items leave insufficient room.

The earlier 0.1.0 build was interactively tested and exposed the permission repetition, visible capture flash, and aspect-ratio defects addressed in 0.2.0. The signed `feat/panel-command-drag-import` candidate is installed and launches from `/Applications/FoldBar.app`. After the window-ID fix, the installed trigger was exercised through System Events: the panel opened, remained alive across multiple candidate-refresh intervals, closed normally, and produced no new crash report. On 2026-09-11, the user then reported that the installed real-menu-bar Command-drag import acceptance path succeeded. The outside-panel cancellation path was not reported separately and remains pending.

The later notch-overflow and empty-panel candidate was built as a signed
universal Release app and installed over that same single
`/Applications/FoldBar.app`; the installed executable hash matched the verified
candidate. Two clean quit/normal-launch cycles completed the initial capture and
collapse with FoldBar's trigger visible. The final panel was opened through its
own Accessibility status item, rendered all nine cached proxies in the new
presentation order, closed with Escape, left the installed process alive, and
produced no new FoldBar crash report. The empty-state expansion was not rendered
live because the current managed list is non-empty; creating that state would
require rearranging the user's real menu-bar items. The real promotion of the
two system-hidden items was likewise left for user acceptance because it changes
the user's actual menu-bar order. Screen Recording, Accessibility, click
forwarding, the empty-state visual, that hidden-item promotion, and other
cross-app synthetic Command-drag behavior remain interaction-dependent.

For the current arrow-left and hover-label candidate, a read-only live metadata
probe matched all nine currently managed status windows to distinct owning-item
information (CodexSquad, Bob, PixPin, Nutstore, ChatGPT, WeChat Input, Notion,
Clash Verge, and Eagle). The probe did not move any real menu-bar item. The
30-test suite and universal Release build pass; final drag placement remains a
real-menu-bar acceptance item because exercising it changes the user's status
item order.

The later proxy-click regression was reproduced against the preceding installed
build: after expansion, the last CodexSquad item occupied Quartz `x=928...962`
while the display's visible right-hand menu-bar segment began at `x=948`. The
old full-display check therefore authorized a click at the notch edge, matching
the reported no-panel behavior. With the current candidate installed, the same
last-cell activation temporarily moved the item fully into the interactive
segment and produced CodexSquad's on-screen `430 x 494` panel. FoldBar then
restored its own widths, closed the external panel during cleanup, and returned
to the collapsed state without a Command-drag or item-order change.

On 2026-09-12, the expanded proxy strip was observed across the menu-bar area
left of FoldBar's trigger, and clicking its CodexSquad proxy opened the intended
application panel. A separate cold-start late-item test detected the replacement
CodexSquad window, expanded the real menu bar after the stabilization delay, and
performed the configured retry. Neither attempt passed the final position
verification: the item returned to the hidden side after collapse rather than
remaining adjacent to FoldBar's trigger. Therefore automatic real-item placement
from a fresh process is not accepted as reliable. The experimental transparent-window
drag-session primer was removed from both working trees; the remaining behavior
falls back to overflow and refreshed proxies.

The `fix/external-drag-preview-style` working-tree candidate is installed at
`/Applications/FoldBar.app` with bundle identifier `local.foldbar.app`, Apple
Development team `42MUMXKY79`, and executable SHA-256
`3083752770f322124706466a1b240154cb2c0bacd545e0250f75c97150a0b1cf`.
The 36-test suite and signed universal Release build (`arm64` + `x86_64`) pass.
The installed process launched successfully from the single intended path.
Exact drag-preview appearance and the absence of a first-frame placeholder still
require direct visual acceptance during a real menu-bar drag; no drop was
completed during automated verification, so no real item order was changed.

Follow-up promotion diagnostics on 2026-09-12 separated event delivery from
post-drag placement. Two initial attempts posted complete synthetic drag
sequences but left their items immediately on the managed side of the separator.
After avoiding the unnecessary trigger-width reduction, one real promotion was
observed and confirmed adjacent to the trigger. A subsequent promotion entered
the visible section but stopped one already promoted item's width (`38 pt`) away
from the trigger, showing that a separator-relative target cannot satisfy the
required insertion order once the visible section is occupied. The candidate for
this promotion fix therefore targets the live trigger frame after every layout
adjustment while retaining fail-closed visible-side and adjacency verification.
It is installed at `/Applications/FoldBar.app` with executable SHA-256
`48ca06c5bfaaa383b1720ad75091da3f389258b32bcb902f2405c506cff8ec18`.
The 38-test suite and signed universal Release build (`arm64` + `x86_64`) pass;
two consecutive real promotions with this final target remain pending user
acceptance. Correlated `Promotion` and `SyntheticDrag` unified-log categories
remain enabled for that acceptance check.

The preceding transparent-strip candidate removed the expanded proxy panel's menu
material and white overlay while retaining its clear window, borderless proxy
buttons, scrolling, and click forwarding. Its 38-test suite and signed universal
Release build (`arm64` + `x86_64`) passed. It was installed at the single intended
`/Applications/FoldBar.app` path with executable SHA-256
`fe11a020ead6ca85f4936fcbb8ef85f55b579b71bc9247bbbbf69371739c3833`.
The user's next visual check confirmed that the backdrop was gone, but also
revealed that the transparent proxies overlapped an already-visible status item.

The overlap-avoidance candidate detects visible status-item windows on
the trigger's display and stops the transparent proxy strip before their
leftmost edge. In the reported live geometry, the existing `68 pt` item at
`x=1291...1359` remains next to the FoldBar trigger while the `334 pt` proxy
strip moves from `x=1025...1359` to `x=957...1291`. Other displays, FoldBar's
own windows, and system items to the right of the trigger are excluded. If less
than one proxy slot remains, presentation fails closed instead of overlapping.
The 41-test suite and signed universal Release build (`arm64` + `x86_64`) pass.
It is installed and running from `/Applications/FoldBar.app` with executable
SHA-256 `8481f1e02a2371a3ee4cbba935fd7e6ac6e060019edef2edc95c21ad6154004b`.
No real menu-bar item was dragged, hidden, or reordered during verification;
direct visual acceptance of the expanded strip remains pending.

The hidden-separator candidate keeps the separator's symbol as its
variable-length sizing reference but makes the separator button visually
transparent. This removes the K-like `chevron.left.to.line` glyph without
changing the separator window, saved order, collapse boundary, or promotion
geometry. The 41-test suite and signed universal Release build (`arm64` +
`x86_64`) pass. It is installed and running from `/Applications/FoldBar.app`
with executable SHA-256
`ae0a47f915ed55b13a13ca40288a704591e387d09e22d1f8d08391317c76a0e0`.
Direct visual acceptance remains pending; no real menu-bar item was moved.

The rejected proxy-activation handoff candidate kept the expanded proxy strip
visible as a click-through transition layer while the real status items reflowed
underneath. Live acceptance showed that the transparent window did not mask the
real items: both rows were visible at once, followed by a second shift caused by
the invisible variable-width separator, and only then the target popover. Its
installed executable SHA-256 was
`03cd26316deff72a255f6e45b7146a7de120fb20fa79add0a70d44c694ff5e50`.

The replacement activation path removes the proxies before revealing any real
status windows and expands directly to a zero-length separator layout. Control
Center retains a measured `16 pt` outer slot even when the status-item length,
image, and button content are all zero; the proxy layout reserves that same slot
from the outset so the real row does not shift left after a click. It polls the
target frame at approximately one display refresh interval, then waits until the
owning application's accessibility menu-item anchor agrees with the already-
visible Quartz status-window center before forwarding the click. This closes the
interval in which an icon looks visible but its application would still anchor a
new popover to the old off-screen position. The forwarded mouse events carry
FoldBar's existing synthetic-click marker, and the automatic collapse monitor
ignores that marker instead of mistaking the opening mouse-up for a request to
close the target. The ordinary path therefore has one aligned reflow, no
proxy/real overlap, no new gap after click, and no fixed post-click overlay delay.
Only a target that still needs the FoldBar trigger's slot retains the existing
bounded `140 ms` safeguard before that temporary width is restored.

The final candidate passed 45 Swift Testing tests and a signed universal Release
build (`arm64` + `x86_64`). It is installed and running from
`/Applications/FoldBar.app` with executable SHA-256
`6696126d877bfce32ac2897c439407fc9e3b24ebf3b419753849c7d6406af839`.
An automated live activation of the ChatGPT proxy measured: proxy removed at
`14 ms`; separator at its final `16 pt` slot by `24 ms`; all real items in their
single final layout with ChatGPT at `x=1235...1273` by `33 ms`; the owning AX
anchor synchronized by `143 ms`; and the `767 x 197` ChatGPT popover visible on
screen at `x=937` by `209 ms`. No doubled row, intermediate separator gap, second
row shift, early collapse, or off-screen target popover was observed. The test
popover was closed and FoldBar was returned to its collapsed state afterward.
