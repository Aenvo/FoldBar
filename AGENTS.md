# FoldBar agent guide

## Scope and intent

This file applies to the entire FoldBar repository. FoldBar is a lightweight macOS menu-bar overflow utility for Macs whose notch leaves too little room for status items. It is a native Swift/AppKit/SwiftUI app, not an iOS app.

Preserve the product model:

- FoldBar owns two `NSStatusItem`s: an always-visible trigger and a separator.
- Collapsing enlarges the separator so status items on its managed side are parked off-screen by macOS.
- The overflow panel shows in-memory screenshots of the real status-item windows. It does not take ownership of another app's `NSStatusItem`.
- Clicking a proxy temporarily expands the real menu bar and forwards a click to the validated real window.
- Dragging a proxy to “keep visible” forwards a validated Command-drag. While the panel is open, a Command-drag that starts on a validated visible status-item window is intercepted before the real icon can leave the menu bar; FoldBar shows a proxy and, after a drop inside the panel, performs a second validated Command-drag entirely within the menu-bar strip to move the real item into the managed section.

Do not replace this with Ice private-CGS behavior or claim that the panel contains real third-party views.

## Source of truth and repository layout

`project.yml` is the XcodeGen source of truth. When targets, build settings, identifiers, versions, or source membership change, edit `project.yml`, run `xcodegen generate`, and commit the resulting `FoldBar.xcodeproj` changes. Do not hand-edit `project.pbxproj` as the primary change.

Key files:

- `FoldBar/FoldBarApp.swift`: SwiftUI entry point and application lifecycle. Termination must expand the separator.
- `FoldBar/StatusBarController.swift`: status items, collapse/expand state machine, cached capture flow, permission onboarding, menu actions, and login-item control.
- `FoldBar/MenuBarItemScanner.swift`: discovery and filtering of menu-bar `NSStatusBarWindow` records.
- `FoldBar/IconCapturer.swift`: per-window ScreenCaptureKit screenshots. Images stay in memory.
- `FoldBar/OverflowPanel.swift`: non-activating panel, adaptive five-column layout, click targets, and drag destination.
- `FoldBar/EventForwarder.swift`: synthetic click and Command-drag events.
- `FoldBar/MenuBarArrangement.swift`: defensive backup and restore of valid status-item positions.
- `FoldBarTests/`: Swift Testing suites for scanner, geometry, event safety, recovery, and grid layout.
- `README.md`: user-facing behavior and build instructions.
- `BUILD_REPORT.md`: evidence from the latest verified build and package.
- `THIRD_PARTY_NOTICES.md`: attribution and license boundary.
- `dist/`: deliberately tracked handoff artifact; do not treat it as a notarized public release.

Do not modify sibling repositories or reference checkouts under the surrounding `work/` directory as part of FoldBar changes.

## Build and test workflow

Requirements are macOS 14 or newer, Xcode 16 or newer, and XcodeGen. The current verified environment and results are recorded in `BUILD_REPORT.md`.

From the repository root:

```bash
xcodegen generate

foldbar_derived="$(mktemp -d /private/tmp/foldbar-derived.XXXXXX)"
xcodebuild \
  -project FoldBar.xcodeproj \
  -scheme FoldBar \
  -destination 'platform=macOS' \
  -derivedDataPath "$foldbar_derived" \
  test

xcodebuild \
  -project FoldBar.xcodeproj \
  -scheme FoldBar \
  -configuration Release \
  -derivedDataPath "$foldbar_derived" \
  build
```

Use a unique temporary DerivedData directory for verification. Xcode can register every built `.app` with Launch Services, and multiple Debug/Release paths with the same display name make macOS privacy panes look duplicated. After verification, quit any test host, unregister built app bundles with `lsregister -u <exact-app-path>`, inspect the temporary directory, and remove only that exact directory. Never launch a Debug/test product as the user's installed copy.

For documentation-only changes, `git diff --check` plus inspection is sufficient; do not create new app registrations merely to prove Markdown did not alter compilation.

Before committing code, at minimum verify:

- `xcodegen generate` leaves the tracked project consistent with `project.yml`.
- All Swift Testing tests pass. The 0.2.0 baseline is 14 passing tests.
- A Release build completes without source warnings.
- `git diff --check` passes and no DerivedData or user-specific Xcode files are staged.

When packaging, additionally verify the archive with `unzip -t`, the application with `codesign --verify --deep --strict`, its architectures with `lipo -archs`, and record the SHA-256 in `BUILD_REPORT.md`.

## Runtime identity, installation, and permissions

The stable application identity is:

- Product: `FoldBar`
- Bundle identifier: `local.foldbar.app`
- Deployment target: macOS 14.0
- Development team: `42MUMXKY79`
- Current version baseline: 0.2.0, build 2

`/Applications/FoldBar.app` is the only intended installed/running copy on the current development Mac. Keep build products in temporary paths, and do not copy another FoldBar bundle into Downloads, the repository, or a second Applications directory for execution. Before replacing the installed app, quit it cleanly, verify the candidate's bundle identifier and signature, install one copy, and relaunch that copy explicitly.

Screen Recording and Accessibility are separate macOS TCC grants. FoldBar may present one explanatory onboarding action, but it cannot merge the two system permissions. Preserve these behaviors:

- Ask automatically only once; later interactions should direct the user to System Settings instead of repeatedly prompting.
- Screen Recording is used only for individual menu-bar window images.
- Accessibility is used only while the panel is open for a user-initiated Command-drag import, or after a user-initiated proxy click or drag.
- A newly granted Screen Recording permission may require relaunching the app before ScreenCaptureKit returns usable content.

Do not change `PRODUCT_BUNDLE_IDENTIFIER`, the signing team, or signing style casually. TCC considers the bundle's designated requirement, so identity churn can cause duplicate privacy entries and repeated authorization. Do not run `tccutil reset`, edit TCC databases, or remove user preferences as routine testing; those actions require an explicit cleanup request and exact before/after verification.

## Safety invariants

Treat synthetic input and status-item preference recovery as high-risk code.

- Keep geometry checks fail-closed. A forwarded event must remain inside a known display's menu-bar strip and inside the intended managed side.
- Preserve support for negative global X coordinates on displays left of the primary display.
- Resolve the live window frame again before clicking or dragging; cached screenshots do not prove that a target is still at the same coordinate.
- Keep the menu-bar import event tap scoped to the visible panel. Consume input only after a Command mouse-down hits a recently scanned, explicitly allowed status-item frame; pass every other event through unchanged and tear down the tap when the panel closes.
- If a real item cannot be resolved safely, leave the menu bar expanded and ask the user to interact manually.
- Never synthesize events into ordinary application windows or arbitrary screen coordinates.
- Snapshot only sane `NSStatusItem Preferred Position` values, never restore paths outside the user's own preference domains, and never restore FoldBar's own domain through the generic recovery loop.
- On termination, cancel pending work, close the panel, remove monitors, and expand the separator so third-party items are not left parked off-screen.
- Preserve the pre-collapse capture cache. Opening the panel must not visibly expand the real menu bar merely to take screenshots.
- Preserve each captured item's aspect ratio and the one-to-three-slot adaptive layout for text, temperature, battery, and other wide items.

Add focused tests whenever scanner cutoffs, coordinate transforms, promotion geometry, recovery filtering, or grid-span rules change. Interactive behavior still requires a real menu bar; unit tests alone are not acceptance evidence.

## Manual acceptance checklist

For runtime-affecting changes, verify on a notch-equipped Mac with several third-party menu items:

1. Only one `FoldBar.app` appears in Screen Recording and Accessibility settings.
2. The installed `/Applications/FoldBar.app` is the process actually running.
3. Permission onboarding does not repeat after the first decision.
4. Initial collapse waits for menu-bar items to stabilize and does not permanently lose their positions.
5. Opening the grid has no expand/capture flash.
6. Square and wide icons keep correct proportions and occupy appropriate grid spans.
7. Proxy click expands, resolves the current real frame, clicks the intended item, and safely collapses afterward.
8. Drag-to-visible and panel import synthesize Command-drag only within the menu-bar strip. An import cancelled outside the panel leaves the item untouched; failed post-drag verification leaves the bar expanded with a manual fallback.
9. Escape and outside clicks close the panel, and quitting restores the visible menu bar.
10. Multi-display layouts, including a display left of the primary display, do not receive out-of-bounds events.

Record what was actually observed. Do not convert an incomplete interactive pass into a claim that click forwarding, drag behavior, or privacy onboarding is fully proven.

## Licensing and release boundaries

FoldBar uses public AppKit, CoreGraphics, ScreenCaptureKit, Accessibility, and ServiceManagement APIs. It contains adapted MIT-licensed MenubarHide work covered by `THIRD_PARTY_NOTICES.md`. Ice may be studied for product behavior and public issue context, but no GPL-3.0 Ice source may be copied into this repository.

The checked-in 0.2.0 ZIP is Apple Development signed for local handoff. It is not Developer ID signed, notarized, stapled, or a public release. Do not claim otherwise, create a tag or GitHub Release, notarize, publish, push, or change remote state without explicit user authorization.

## Git hygiene

- Preserve unrelated user changes and inspect `git status` before editing and before committing.
- Keep generated build directories, DerivedData, `.DS_Store`, and `xcuserdata` out of commits.
- Update user-facing documentation and `BUILD_REPORT.md` when behavior, requirements, test counts, version, artifact hash, signing, or verification evidence changes.
- Use narrow commits whose message describes the actual change.
- A request to commit does not authorize pushing. Never push, force-push, merge, tag, or publish a release unless the user explicitly requests that separate action.
