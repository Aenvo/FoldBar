# FoldBar build report

Verified locally on 2026-09-12 with Xcode 26.6 (17F113), Swift 6.3.3, and the macOS 26.5 SDK.

## Results

- Debug app-hosted test build: passed.
- Swift Testing: 36 tests passed.
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
trigger instead of exposing the real hidden section.

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
- Right-to-left overflow-panel presentation order.
- Visible menu-bar-segment validation, including overlapping X ranges on different displays.
- Adaptive one-, two-, and three-column spans for wide status items.
- Detection of newly registered managed-window IDs and free-space calculation
  for automatic placement.
- Menu-bar overlay clamping and proxy layout for the expanded presentation.

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
