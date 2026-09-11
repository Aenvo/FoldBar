# FoldBar build report

Verified locally on 2026-09-11 with Xcode 26.6 (17F113), Swift 6.3.3, and the macOS 26.5 SDK.

## Results

- Debug app-hosted test build: passed.
- Swift Testing: 22 tests passed.
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
- Promotion target geometry for drag-to-visible.
- Post-drag visible-side verification before re-collapsing.
- Command-drag source-window selection for menu-bar-to-panel import.
- Safe rejection of negative and out-of-range AppKit window numbers.
- Own-status-item frame fallback when no usable Core Graphics window ID exists.
- AppKit-to-Quartz panel coordinate conversion.
- Managed-side import target geometry and impossible-target rejection.
- Post-drag managed-side verification before re-collapsing.
- Defensive position snapshot merge and restore filtering.
- Expanded-section discovery used for flash-free pre-collapse caching.
- Adaptive one-, two-, and three-column spans for wide status items.

The earlier 0.1.0 build was interactively tested and exposed the permission repetition, visible capture flash, and aspect-ratio defects addressed in 0.2.0. The signed `feat/panel-command-drag-import` candidate is installed and launches from `/Applications/FoldBar.app`. After the window-ID fix, the installed trigger was exercised through System Events: the panel opened, remained alive across multiple candidate-refresh intervals, closed normally, and produced no new crash report. On 2026-09-11, the user then reported that the installed real-menu-bar Command-drag import acceptance path succeeded. The outside-panel cancellation path was not reported separately and remains pending. Screen Recording, Accessibility, click forwarding, and other cross-app synthetic Command-drag behavior also remain interaction-dependent.
