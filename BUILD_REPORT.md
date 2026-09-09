# Build report

Verified locally on 2026-09-09 with Xcode 26.6 (17F113), Swift 6.3.3, and the macOS 26.5 SDK.

## Results

- Debug app-hosted test build: passed.
- Swift Testing: 10 tests in 3 suites passed.
- Release build: passed with no source compiler warnings.
- Release binary: universal `arm64` + `x86_64`.
- Deployment target: macOS 14.0.
- Bundle identifier: `local.menubaroverflow.app`.
- Hardened runtime: enabled.
- Archive integrity (`unzip -t`): passed.
- Code-signature structural verification (`codesign --verify --deep --strict`): passed.

## Packaged artifact

`dist/MenuBarOverflow-0.1.0-macOS.zip`

SHA-256:

```text
0a74568b14bd353b437cec9bb6b9d62e00176f80e67f41340823a4cdcd3dda03
```

The packaged app is signed ad hoc for local evaluation. It is **not** Developer ID signed or Apple-notarized, so it is not a public release artifact.

## Test scope

- macOS 26 status-window overflow discovery.
- Contiguity cutoff so a different display's status windows are not included.
- Menu-bar geometry validation before synthetic events.
- Negative X coordinates for displays left of the primary display.
- Promotion target geometry for drag-to-visible.
- Defensive position snapshot merge and restore filtering.

The app itself was not launched during this verification. Live Screen Recording, Accessibility, click forwarding, and cross-app Command-drag behavior require an interactive signed-app test on the target Mac.
