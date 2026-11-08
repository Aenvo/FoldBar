# FoldBar build report

## v0.2.1 source and installation guidance — 2026-11-08

- Advanced the permission-onboarding fix to version **0.2.1 / build 3** for a
  separate patch release. The earlier v0.2.0 tag and build-2 archive are retained.
- Both README languages now put signing, first-launch confirmation, permission
  requirements and unverified system coverage beside the download entry. The
  first-launch instructions use macOS's per-application confirmation when
  available, and explain that managed-device policy may prevent opening the app.
- On macOS 27.2 with Xcode 27.1, **150 tests in 15 suites passed** and the
  universal x86_64/arm64 Release build succeeded without Swift source warnings.
  The existing skipped AppIntents metadata warning remains.
- Gitleaks 8.30.1 scans of the intended repository files and all reachable Git
  history completed with zero findings. Reports were redacted. This checks
  credential patterns and does not establish a complete privacy or security audit.
- Bilingual README validation and `git diff --check` passed. Developer ID
  signing, notarization, clean-Mac first launch, legacy-system/Intel runtime,
  and complete panel click/drag acceptance remain pending.

## Permission onboarding fix and local build 3 acceptance — 2026-11-08

- Separated the onboarding decision from the existing system-permission request
  history. Choosing Later stops automatic startup reminders; the manual
  Permission Settings action still offers the first request. Previously
  requested users retain settings-only recovery. The delayed startup action
  rechecks the decision and current grants before presenting a reminder.
- Added eight isolated-UserDefaults regression tests for Later across restart,
  a subsequent manual request, denied/partial grants, legacy request history,
  a decision made while presentation is pending, and externally granted access.
  These tests do not invoke or reset macOS TCC prompts.
- Xcode 27.1 (`27A9275`), macOS 27.2 (`26B123`): **150 tests in 15 suites passed**.
  The universal **x86_64 / arm64 Release** build succeeded without Swift source
  warnings; the existing skipped AppIntents metadata warning remains.
- `project.yml` advances the build number to **3**, preserving version 0.2.0,
  `local.foldbar.app`, team `42MUMXKY79`, and macOS 14.0 minimum. XcodeGen
  generated the project and included the policy and test sources.
- A separate `FoldBar-0.2.0-build3-macOS.zip` candidate is retained outside this
  repository. Size: **1,991,879 bytes**; SHA-256:
  `166600b52b21a35de953ca16b52d6167601129962526c4c5efb8426af3b18c7d`.
  ZIP integrity, extracted strict signature verification, architecture and
  bundle metadata checks passed. Its manifest identifies the modified source
  snapshot based on `f2dd588`, rather than claiming an unchanged commit build.
- Backed up the previous installed build, quit it through its native menu,
  installed from the verified candidate archive at `/Applications/FoldBar.app`,
  and relaunched that sole installed copy. Its executable matches the candidate:
  `853eaac94bb6df59ffc737655fcd1e6708cf63b4a80885f0661e68f7fbc5cd99`.
  The designated requirement matches the prior installation. The managed set,
  language, direct-drag option and permission history checked before and after
  installation were unchanged.
- Native About displayed **0.2.0 (3)**. Normal quit, relaunch and the trigger's
  return were observed. Accessibility nodes for three managed applications
  returned after quit and disappeared again after startup settled. Direct status
  control clicking was rejected by the UI tool as off-screen, so panel proxy
  clicking and dragging remain unverified in this pass.
- Matching universal dSYM UUIDs were verified and symbols retained outside the
  candidate archive. Test hosts exited; temporary Debug/Release and extracted
  app registrations were removed, and the exact inspected temporary directories
  were deleted. Repeated XcodeGen generation, bilingual README validation and
  `git diff --check` passed.
- Apple Development signing is retained. No Developer ID Application identity
  is available locally; the candidate's Gatekeeper assessment remains rejected
  (exit 3). Public-distribution signing, notarization, fresh-Mac permission
  dialogs, macOS 14–26/Intel and multi-display runtime acceptance remain pending.
  Startup logs also contain preference-domain access and Security performance
  diagnostics; this observation does not establish a clean or long-running pass.
- The tracked `dist/` build-2 package and remote Release were not replaced by
  this local candidate. No public-visibility change was performed.

## GitHub Latest release promotion — 2026-10-21

- Promoted the existing [FoldBar v0.2.0](https://github.com/Aenvo/FoldBar/releases/tag/v0.2.0)
  to a regular GitHub release and explicitly selected Latest. API read-back
  confirms `prerelease: false`, `draft: false`, and the latest-release endpoint
  returns this version. The authenticated repository homepage displays
  **FoldBar v0.2.0 · Latest** in its Releases sidebar.
- Updated the bilingual README download labels, release title and notes,
  package installation instructions, and manifest channel to match. Historical
  preview checkpoints below retain their original evidence.
- Repackaged the existing ZIP with only `INSTALL.txt` changed. Every other
  archive entry, including all signed application files, is byte-identical to
  the previous package. The application executable SHA-256 remains
  `bd166c93cc0626ee322bac3ea84bd30fadd48f48c90d4cbc79dbea4bc38c4d32`.
- `dist/FoldBar-0.2.0-macOS.zip`: **1,991,023 bytes**; SHA-256
  `12e0086afbaa32210118bde07bab2f1d3d71f4f447a61dea214cdd23e6121cee`.
  ZIP CRC checks, extracted application strict signature verification, and
  **x86_64 / arm64** architecture checks passed. Bundle identity, version
  0.2.0/build 2, team, and macOS 14.0 minimum remain unchanged.
- Uploaded the ZIP, updated manifest, and checksums to the existing release.
  All three GitHub asset digests match local SHA-256 values; downloaded files
  are byte-identical to the corresponding local files. The original tag target
  remains `8ad96938b6d148c12030f4d7cfa7c6719be28776`.
- Bilingual README validation and `git diff --check` passed. The temporary
  extracted app path was absent from Launch Services, and its inspected
  verification directory was removed.
- Reused the original application build and its 142-test/14-suite results;
  this text and packaging update did not rebuild or install the application.
  Apple Development signing, the previous Gatekeeper rejection, the lack of
  notarization, and pending hands-on acceptance remain documented below. The repository
  remains private and requires access to view or download the release.

## GitHub developer-preview publication — 2026-10-19

- Published [FoldBar v0.2.0 — Developer preview](https://github.com/Aenvo/FoldBar/releases/tag/v0.2.0)
  as a **prerelease**, not a stable Latest release. The annotated `v0.2.0` tag
  resolves to `8ad96938b6d148c12030f4d7cfa7c6719be28776`.
- Uploaded the existing validated ZIP, `SHA256SUMS.txt`, and
  `release-manifest.json`. All three GitHub asset digests and downloaded-file
  hashes match the local files. The ZIP is still 1,991,230 bytes with SHA-256
  `c3cd05f1e810dec0645b805f303b3700ebcfa768d2582e7a771328deedc21acb`.
- Added and read back eight Topics: `appkit`, `macos`, `macos-app`, `menu-bar`,
  `menu-bar-manager`, `notch`, `swift`, and `swiftui`. Description and homepage
  were preserved. The repository remains **private**; access is required to view
  or download this release.
- Both README languages now link to the versioned release and its real assets.
  Existing package checks are reused; no application rebuild or local install
  was performed for this publication. Developer-signing, Gatekeeper, notarization
  and hands-on acceptance limitations below remain unchanged.

## Release package candidate — 2026-10-18

Prepared a fresh **0.2.0 / build 2 developer-preview** package from application
source at `beb5f024729b37052b53c86e662ffe2161b5bb33`. No application source, signing
team, bundle identity or deployment target changed. The installed application
was not replaced or launched from a build directory.

- Xcode 27.1 (`27A9275`): **142 tests in 14 suites passed**; a fresh universal
  **arm64 / x86_64 Release** build passed without Swift source warnings.
  Existing skipped AppIntents metadata warnings remain.
- Bundle: `local.foldbar.app`; minimum macOS **14.0**; Apple Development signing,
  team `42MUMXKY79`. Strict signature verification passed before packaging and
  again after ZIP extraction. No personal build-home path was found in the
  stripped executable's strings.
- `dist/FoldBar-0.2.0-macOS.zip`: **1,991,230 bytes**; SHA-256
  `c3cd05f1e810dec0645b805f303b3700ebcfa768d2582e7a771328deedc21acb`.
  The archive contains the app, bilingual `INSTALL.txt`, `LICENSE`, and
  `THIRD_PARTY_NOTICES.md`; no dSYM, test products or AppleDouble metadata.
  ZIP CRC checks and extracted executable equality passed.
- `dist/release-manifest.json` records source revision, architectures, signing
  status and validation limits. `dist/SHA256SUMS.txt` covers the ZIP and manifest.
  `dist/RELEASE_NOTES.md` provides matching Chinese and English preview notes.
- Gitleaks **8.30.1**, default rules, redacted reports: the current directory and
  all reachable Git history both completed with zero findings. This does not
  establish a complete security or publication-privacy audit.
- **Gatekeeper assessment rejected the app** (exit 3). No Developer ID identity
  is available locally, and no notarization or stapling was performed. Structural
  signature success is not acceptance for unrestricted distribution.
- Clean-Mac installation, updated macOS 14–26 runtime, multi-display and final
  package click/drag acceptance remain pending. Prior short runtime and memory
  observations are not new package-level interactive acceptance.
- Matching universal dSYM UUIDs were verified and symbols retained outside the
  app/archive. Temporary app registrations and inspected DerivedData/package
  verification directories were removed. The existing installed app is unchanged.

At this checkpoint no tag, GitHub Release, topic update or repository visibility
change has been applied. The candidate package and bilingual README use valid
repository-relative download links without claiming a published Release exists.

## Background inventory and capture optimization — 2026-10-18

Implemented and installed, preserving the existing language changes:

- An empty persisted macOS 27 managed set no longer arms the collapsed background
  monitor. A nonempty persisted set still retries missing images even when its
  usable image cache is empty. Removing the last managed bundle recomputes the
  monitor lifetime; importing the first bundle resumes it.
- AX inventory now keys snapshots by PID, bundle ID and launch date. Normal
  discovery refreshes known menu-extra owners, MenuBarAgent, and newly observed
  processes during a 30-second discovery grace. A full sweep becomes due every
  30 seconds and runs on the next monitor request; this is a fallback cadence,
  not a strict 30-second wall-clock discovery guarantee. Exited/reused generations
  are pruned, completed empty scans replace old snapshots, and partial/cancelled
  scans do not postpone the full sweep. One shared detached scan remains in flight.
- Explicit panel opening performs a full fresh inventory. Its input tap starts
  with no allowed candidates until that refresh completes, preventing old cached
  coordinates from being intercepted after an idle empty collection. Cancellation
  and panel/tap lifetime are rechecked before publishing candidates or previews.
- Legacy collapsed polling changes from 600 to 1,500 ms; panel polling changes
  from 250 to 500 ms, matching the AX minimum refresh interval. Live source-frame
  resolution before clicks and drags is unchanged; no global geometry TTL was added.
- Background missing-image recovery makes one capture attempt per cooldown batch
  instead of three. Startup and explicit imports keep their existing retries.
  The 15/30/60/120/300-second cooldown and fail-open visibility remain intact.
- Removed a redundant all-process property query immediately after creating a
  new shared scan. The fresh post-await generation check remains.
- Added explicit `--inventory-performance-probe` developer diagnostics: ten paired
  full/scoped scans in one process, existing AX permission only, no screenshots,
  visibility assertions, synthetic input or preference writes. Ordinary launches
  never enter this mode. Only bounded scalar refresh statistics are retained.

Validation:

- **142 Swift Testing tests in 14 suites passed** on the final source. Ten new
  tests cover discovery scope/grace, forced and fallback scans, generation reuse,
  empty/partial merges, incomplete sweeps and empty-managed monitor behavior.
- The universal **x86_64 / arm64 Release** build passed without source warnings;
  the existing skipped AppIntents metadata warning remains. A second XcodeGen
  generation was byte-identical and `git diff --check` passed.
- Strict code signature validation passed. Bundle `local.foldbar.app`, team
  `42MUMXKY79`, version 0.2.0/build 2, deployment target 14.0, and the designated
  requirement match the prior installation. Both localized catalogs still contain
  78 keys. Membership, language, appearance, direct-drag and onboarding preference
  values were compared before/after and preserved; no TCC reset occurred.

The controlled inventory comparison used the same process and the same twelve
menu-item identities in all ten pairs, with 114 running applications throughout:

| Per refresh | Full inventory | Scoped inventory |
| --- | ---: | ---: |
| Applications receiving an AX scan | 114 | 13 |
| Mean elapsed time | 1.632262 s | 0.078371 s |
| Mean FoldBar CPU time | 0.034960 s | 0.028769 s |

This is **88.6% fewer applications scanned**, **95.2% less elapsed
scan time** and **17.7% less process CPU time per refresh** in this
specific probe. It does not measure total-system power, and a periodic full
fallback remains part of normal operation.

Separate normal-launch observations, 91 samples over approximately 180 seconds
each, with heap/leak inspection outside the CPU windows:

| Metric | Prior installed build | Final optimized build |
| --- | ---: | ---: |
| Mean FoldBar CPU, percent of one core | 0.875% | 0.675% |
| Last approximately 60 s mean CPU | 0.904% | 0.683% |
| Interrupt wakeups per second | 1.447 | 0.316 |
| Package-idle wakeups per second | 0.322 | 0.083 |
| Physical footprint range | 28.77–28.97 MiB | 20.86–20.95 MiB |

The observed mean CPU difference is 22.9%. These normal
launches had ten successfully captured IDs each but only nine in common, and
cold/warm framework caches differed. Do not attribute all of the CPU or memory
difference to this change. The controlled same-process comparison above isolates
inventory selection. CPU counters use Mach timebase 125/3 ns per tick.

Final normal-mode heap/leak observations remained stable across the sample:
CGImage 34 → 34, CGImageProvider 18 → 18, NSImage 17 → 17, IOSurface heap objects
0 → 0; `leaks --noContent` reported **432 → 432 bytes** in six objects, rooted at
three NSMutableDictionary instances. No background capture failure occurred in
this final interval, so it does not directly exercise the new one-attempt failure
path or prove zero future leakage.

Residual screenshot leak attribution:

- A single installed current-API probe with process-local `MallocStackLogging=lite`
  completed **100/100 captures at 44 x 44 pixels**. All 100 leaked dictionary
  allocation stacks point to ScreenCaptureKit's internal
  `captureScreenshotWithRect:contentFilter:configuration:completionHandler:` →
  `CGRectCreateDictionaryRepresentation` → `CFDictionaryCreateMutable`.
  `malloc_history` independently confirmed three sampled roots.
- Lite instrumentation reported 17,600 leaked bytes (allocator overhead changes
  the per-pair sizes). The earlier uninstrumented residual was 144 bytes per
  region call. The dictionary is internal to the OS API; FoldBar does not own a
  releasable reference to it. Image/output ownership was left correct.
- The OS leak is **not fixed** by this change. Reducing unnecessary capture
  attempts reduces potential triggers; actual background 3→1 failure behavior
  is a source-level change, not a reproduced failure during the final sample.

Installation and retained artifacts:

- The optimized sole installed `/Applications/FoldBar.app` is running normally,
  PID 56213, with no diagnostic arguments or stack-logging environment.
  `ps`, `lsof`, strict signature and executable hash were checked after all probes.
  Installed executable SHA-256:
  `ba42acae269d82709c2b102be397c5a4b42018ab03845d4973d538262f6f78ba`.
- Final app file bytes: **3,001,077 (2.862 MiB)**,
  versus 2,868,981 bytes before optimization. The additional policy, regression
  tests' source membership and diagnostics do not bundle test products or dSYMs;
  both architectures and original icon assets remain.
- Rollback: `~/Library/Application Support/FoldBar/Backups/FoldBar-before-inventory-optimization-2026-10-18-172938.zip`.
  `unzip -t` passed and the archived executable matches the prior installed build.
  Archive SHA-256: `d2c1e52e2951f9d3eb257d7e3ed3fe7ecd1093ee724399fecc2ebdf0428c559d`.
- Matching final universal symbols: `~/Library/Application Support/FoldBar/Symbols/FoldBar-0.2.0-build2-ba42acae.dSYM.zip`.
  Both UUIDs match the installed executable and `unzip -t` passed.
  Archive SHA-256: `b568b0278f84ddeb775f57a7dbad90b79ab5f6bc508d9d7d7027f53f97eb5186`.
- Temporary Debug/Release registrations were removed. Moved-old-app paths had no
  registration (`-10814`). Inspected DerivedData, moved candidates and termination
  helper were removed; intermediate symbols were removed after final symbols were
  verified. The tracked distribution ZIP and remote Git state were not changed.

Native UI automation did not expose FoldBar's accessory process in its inventory;
actual proxy-click/import/promotion acceptance and macOS 14–26 runtime remain
unverified for this change. A first-open import waits for fresh inventory. Total
system watts, temperature and multi-day stability were not measured. No speculative
OS callback ownership/timeout workaround was introduced.

Raw counters, paired probe output, no-content heap/leaks, final build logs and
installation metadata are retained at
`~/.codex/visualizations/2026/10/18/01a14e35-8548-7273-9868-73ea497cca3a/foldbar-performance-optimization-20261018-172712/`.
Allocation stack evidence is in the sibling `foldbar-leak-attribution-pc7u97g1/`;
capture-cohort comparisons are in `foldbar-capture-cohorts-11yu4wtm/`.

## Installed performance and memory audit — 2026-10-18

Scope: the currently installed signed `/Applications/FoldBar.app`, PID 51599,
macOS 27.0 (`26A428`), Mac17,4, 10 logical CPUs. Its executable SHA-256 remains
`b0e863fa212fd83536a10d70eba622ac46ac15a23da0d012e5bb58c47d6fe6ef`. All 44 source/project files from the signed installation
snapshot still match. No application source, preferences, permissions, managed
membership, installed bundle or running process was changed during this audit.

Measurements:

| Metric | Result |
| --- | --- |
| Installed bundle file bytes | 2,868,981 bytes (2.736 MiB) |
| Change from the pre-language-switch backup | +90,326 bytes (+3.25%) |
| Main executable / Assets.car | 1,523,488 / 1,253,736 bytes |
| Four localized resource files | 22,302 bytes |
| Physical footprint during 151 samples over 300.57 seconds | 41.20–41.31 MiB; start 41.251, end 41.267 MiB |
| CPU, mean / maximum two-second interval | 0.457% / 1.595% of one CPU core |
| Interrupt / package-idle wakeups | 0.349 / 0.093 per second |
| Process-attributed disk reads / writes during this series | 0 / 0 bytes |
| `leaks --noContent`, 361.475 seconds apart | 95 objects / 6,800 bytes → 107 objects / 7,664 bytes; +864 bytes |
| `heap -s --noContent`, initial → final | CGImage 65 → 65; CGImageProvider 45 → 45; NSImage 17 → 17; IOSurface heap objects 0 → 0 |

CPU uses `proc_pid_rusage` cumulative user/system time deltas normalized with this
host's Mach timebase (125/3 ns per tick), cross-checked against `ps` cumulative
CPU time. The first top snapshot is not used as a rate. Heap/leak inspection and
the final five-second stack sample ran outside the CPU series. Physical footprint
is reported separately from RSS (~127.6 MiB of resident mappings) and virtual
address space; those are different accounting measures.

Findings and limits:

- **Small residual leak reports remain.** All leak roots in both snapshots were
  NSMutableDictionary; no CGImage, CGDataProvider or IOSurface leak root appeared.
  Six failed region-fallback attempts were logged during the leak-comparison
  interval, coinciding with the 864-byte increase. Allocation backtraces were
  not enabled, so this correlation does not establish the source of the leaked
  dictionaries. Do not describe this build as leak-free or extrapolate a daily
  growth rate from this short interval.
- **No current package-size problem or large image accumulation was observed.**
  The app remains universal, with no bundled dSYM, test bundle or third-party
  framework. Settings intentionally retains a single panel; screenshot and
  preview caches have finite live-item/session boundaries. The known historical
  image leak chain did not recur in these samples.
- **Recurring system calls remain an optimization opportunity.** Collapsed
  macOS 27 operation scans all running apps' AX menu extras every 5 seconds plus
  scan duration (`StatusBarController.swift:552`, `MenuBarAccessibility.swift:138`).
  It still scans when the managed set is empty, although no visibility assertion
  needs reconciliation. An unchanged visibility key avoids replacing the private
  assertion; successful images are reused rather than recaptured every tick.
- **Legacy polling is more frequent in source.** macOS 14–26 requests the full
  CG window list about every 600 ms while collapsed, and every 250 ms with the
  panel open (`MenuBarItemScanner.swift:247`, `StatusBarController.swift:1205`).
  macOS 27's panel loop is 250 ms with a 500 ms AX refresh throttle. This is a
  code finding; its actual older-system CPU and energy cost was not measured.
- **Failed screenshot backoff is active.** The latest stable failed-capture batch
  starts were 33.895, 61.550 and 120.934 seconds apart, consistent with the
  30/60/120-second policy plus scan overhead. Each batch contained three failed
  attempts. The code caps later retries at 300 seconds; the 300-second stage was
  not reached within this observation. No per-5-second blanket screenshot retry
  or unbounded concurrent periodic scan was found.
- **Cancellation and OS callback robustness can improve.** Cancelling a caller
  does not cancel the shared detached AX scan already in flight. Screenshot and
  private activation continuations have no explicit timeout/cancellation bridge
  (`IconCapturer.swift:246`, `MenuBarVisibilityRestriction.swift:322`). A lost
  callback could retain one pending operation; no lost-callback occurrence or
  resulting resource growth was observed in this audit.
- **No sustained high-load heating evidence was found in this interval.** The
  main thread mostly waited for events; the worker sample included synchronous
  AX IPC waits. `pmset -g therm` reported no recorded thermal/performance warning,
  which is not a temperature measurement. Total-system watts, other processes'
  induced CPU work, a quit/running A/B comparison, multi-day stability, repeated
  user interactions and macOS 14–26 runtime were not measured.

Recommended optimization order: eliminate unnecessary
empty-managed-set scans, reduce unchanged all-application polling while retaining
new-item fail-open reconciliation, then isolate the residual dictionary leak with
allocation stacks. Give OS callback cancellation/timeouts focused coverage before
changing their lifetime semantics.

Raw no-content heap/leak summaries, process samples, clock-normalized counters,
source hashes and logs are preserved outside the repository in
`~/.codex/visualizations/2026/10/18/01a14e35-8548-7273-9868-73ea497cca3a/foldbar-performance-audit-20261018-171327/`.
Only this report was updated; no new app build or registration was needed.
`git diff --check` passed. Existing localization changes and `.codex-probe/` were
preserved.

## Chinese / English language switching — 2026-10-18

- Settings now offers Follow System, 简体中文, and English. The app saves the
  selection and updates its own interface immediately through explicit localized
  resource lookup. It does not change AppleLanguages, recreate status items,
  refresh screenshot caches, or request permissions again.
- Both language catalogs contain **78 matching interface keys**. Coverage
  includes settings, appearance descriptions and fallback text, overflow/drop
  hints, context menus, About, login-item errors, permissions and restart flows,
  and click/import/promotion recovery messages on **macOS 14–26 and 27+**.
- Native third-party names and hover help retain their original text. Generic
  proxy names are resolved for display in the chosen language; the underlying
  AX labels used to validate item identity stay stable. macOS privacy dialogs
  and System Settings continue to use the system's language controls.
- The settings form has room for English descriptions and adapts its height to
  the visible screen. The existing macOS 27 per-application membership limit
  is explained in both languages. Deployment remains macOS 14.0.

Verification on macOS 27.0 (`26A428`), Xcode 27.1 (`27A9275`):

- All **132 Swift Testing tests in 12 suites passed**, including 11 new tests
  for language preferences, isolated persistence, complete built-resource
  coverage, format argument parity/substitution, and legacy recovery guidance.
- The universal Release build completed for **x86_64 and arm64**, without Swift
  source warnings. The existing skipped AppIntents metadata warning remains.
- `codesign --verify --deep --strict` passed for the Release candidate. Its
  bundle identifier is `local.foldbar.app`, team `42MUMXKY79`, and minimum
  system version `14.0`.
- Both `.strings` catalogs and localized InfoPlist files pass `plutil -lint`.
  A second XcodeGen generation produced an identical tracked project;
  `git diff --check` passed.
- A temporary standalone executable rendered the production settings view with
  the real resource catalogs, without launching another FoldBar app bundle or
  creating status items. English and Chinese content fit at 500 x 590 points.
  A live change through the volatile argument domain refreshed both the view
  and native window title. At 500 x 380 points, the longest English glass and
  direct-drag descriptions remained readable through normal vertical scrolling,
  with no observed horizontal truncation. The harness wrote no persistent
  settings; these renders do not exercise older-system visual styles.
- Test hosts and the settings harness exited. Temporary Debug/Release app
  registrations and the inspected temporary build directories were removed.

The initial source/build verification left the installed app untouched. Real
macOS 14–26 runtime and the full interactive menu-bar acceptance checklist remain
unverified for this change. No TCC reset, preference deletion, commit, or push
was performed.

Local installation, explicitly authorized on 2026-10-18:

- Rebuilt the unchanged source snapshot as a signed universal Release; strict
  signature, both architectures, 78 keys in each built language catalog, and
  the designated requirement matching the prior installation all passed.
- Quit the prior installed process cleanly, replaced only
  `/Applications/FoldBar.app`, and explicitly launched that path without probe
  arguments. `ps` and `lsof` confirm the running executable at that path
  (PID 51599). The installed executable matches the candidate SHA-256:
  `b0e863fa212fd83536a10d70eba622ac46ac15a23da0d012e5bb58c47d6fe6ef`.
- Identity remains `local.foldbar.app`, team `42MUMXKY79`, version 0.2.0/build 2,
  minimum macOS 14.0. The installed signature and both localized resource
  catalogs were checked again after replacement.
- Rollback archive: `~/Library/Application Support/FoldBar/Backups/FoldBar-before-language-switch-2026-10-18-170910.zip`.
  `unzip -t` passed; the archived executable matches the prior installed hash.
  Archive SHA-256: `02789e3896854994da39ddd73ff0f38f451e11493726512c26c0540eb77a009f`.
- Matching arm64/x86_64 debug symbols were archived outside the app at
  `~/Library/Application Support/FoldBar/Symbols/FoldBar-0.2.0-build2-b0e863fa.dSYM.zip`.
  Both UUIDs match the installed executable and `unzip -t` passed.
  Archive SHA-256: `abb8e1ba0b38c78f022935fb220652e96c991596f70d895a63d017cf9bace7bc`.
- Temporary build/moved-app registrations were removed (the moved-old-app
  path had no registration, `-10814`); the inspected temporary directory was
  deleted after preserving the rollback archive, dSYM and build evidence.
  The tracked historical distribution ZIP was not changed.
- Installed interaction acceptance is left to the user. Native UI inspection
  timed out; no installed proxy click, membership change, or language preference
  change was performed as part of installation.

## Screenshot memory and Release-size optimization — 2026-10-16

The prior installed process accumulated 98.5 MiB of unreachable image objects.
Logs showed one unavailable item retried in three-attempt batches every 5–6
seconds. This is separate from the much smaller assessment-assertion ownership
issue fixed in the preceding audit.

Changes:

- On macOS 26+, the region fallback uses `captureScreenshot(rect:configuration:)`
  and `SCScreenshotOutput.sdrImage`, whose ownership is explicit. It requests
  SDR, no cursor or file output, and native pixel dimensions. The old 15.2–25
  region branch and legacy per-window path remain available. No speculative
  manual Core Foundation release was added.
- Only failed background captures back off, at 15/30/60/120/300 seconds with a
  five-minute cap. Application-generation or frame changes, a panel session or
  explicit import can retry. AX inventory and new-application visibility
  reconciliation keep their existing cadence. A bundle still needs all real
  images before it can be hidden; failed images remain fail-open.
- Preview caches retain current candidates and active dragging only. Panel
  generations reject late results and prefetch cannot overwrite a fresher drag
  image. Eleven deterministic regression tests cover cooldown and cache lifetime.
- Release enables dead-code stripping, deployment postprocessing, installed
  product stripping and non-global symbol stripping. `-O`, whole-module builds,
  both architectures, external dSYM output and signing identity are preserved.
- An explicit, bounded `--capture-memory-probe legacy|current` diagnostic mode
  performs at most 100 region captures of a live, validated visible AX item.
  It bypasses the normal controller during the comparison and stores no pixels
  or preferences. Normal launches do not enter the probe.

Verification on macOS 27.0 (`26A428`) and Xcode 27.0 (`27A266a`):

- All **121 Swift Testing tests in 11 suites passed**. The universal Release
  build passed with no source warnings; only the existing skipped AppIntents
  metadata warning remains. XcodeGen regenerated the tracked project.
- Controlled comparison used two fresh processes of the same signed candidate,
  the same AX item, and **100/100 successful captures at 44 x 44 pixels** in each
  mode, with normal background captures disabled:

  | After 100 captures | Legacy region API | Screenshot-output API |
  | --- | ---: | ---: |
  | CGImage objects | 112 | 12 |
  | IOSurface objects | 100 | 0 |
  | Reported leaked bytes | 684,880 | 14,400 |

  The CGImage/CGDataProvider/IOSurface leak chain disappeared; total leaked bytes
  fell **97.9%**. The remaining 14,400 bytes are small NSMutableDictionary leaks
  with no established allocation origin, so this is not a zero-leak claim.
- The app was then relaunched normally, without probe arguments, at the sole
  installed `/Applications/FoldBar.app` path (PID 51002). Initial logs confirm
  nine usable real-image captures. The first normal sample at 08:45:23 reported
  21.58 MiB physical footprint, 33 CGImage objects, zero IOSurface objects and
  2,160 leaked bytes of small dictionaries, with no CGImage leak root.
  A second sample at 08:47:45 (142 seconds later) retained exactly the same
  physical footprint, CGImage count (33), IOSurface count (0) and NSImage count
  (16). Small dictionary leaks were 2,880 bytes, an increase of 720 bytes.
  Log batches were spaced 16.156/31.928/63.590 seconds apart, confirming the
  15/30/60-second cooldown stages including scan overhead. The 120/300-second
  stages are covered by deterministic tests, not this short runtime interval.
- Native UI inspection opened the installed panel and showed all nine proxies.
  Its screenshot showed the expected grid and icon proportions. Escape closed
  the panel; reopening showed the same nine proxies, then Escape closed it
  again. No real membership change or third-party proxy click was performed.
  The post-UI sample at 08:49:54 measured 28.44 MiB physical footprint,
  41 CGImage objects, zero IOSurface objects, 16 NSImage objects and 4,608 bytes
  of small dictionary leaks. The large image leak chain did not reappear.
- Installed app size: **3,946,175 -> 2,778,655 bytes** (3.76 -> 2.65 MiB), a
  **29.6% reduction** versus the prior installed copy. Executable size:
  2,624,480 -> 1,456,960 bytes. Both `x86_64` and `arm64` remain present.
- Candidate and installed app pass `codesign --verify --deep --strict` with the
  same designated requirement, bundle `local.foldbar.app`, team `42MUMXKY79`,
  version 0.2.0/build 2 and deployment target 14.0. Installed executable SHA-256:
  `7dc88f4b16055f3a94b94a31e10d80a091658a5c80c0c8036a9116f5fabd0a02`.
- The prior installed app was quit cleanly and preserved in the verified backup
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-memory-optimization-2026-10-16-083631.zip`.
  `unzip -t` passed; archive SHA-256:
  `e836b34b07fd46eecb8719a60ab0a6745bf64e19d8185fa88328e086a86eadea`.
- The matching universal dSYM was preserved outside the app in
  `~/Library/Application Support/FoldBar/Symbols/FoldBar-0.2.0-build2-7dc88f4b.dSYM.zip`.
  Its arm64/x86_64 UUIDs match the installed executable and `unzip -t` passed;
  archive SHA-256:
  `692e6b9f2627414458e2a3d8a0fff7f32c514068f222ea64e71e38bc490e6895`.

Test hosts exited. Temporary Debug/Release Launch Services registrations were
removed; the moved-old-app path had no registration (`-10814`). The inspected
DerivedData and moved-old-app folders were deleted after preserving the verified
rollback ZIP and dSYM.
`git diff --check` passed. The original untracked `.codex-probe/` remains outside
the change.

No new claim is made for multi-day stability, macOS 14–26 runtime, physical
multi-display or drag acceptance. No TCC reset or preference deletion occurred.
The tracked historical distribution ZIP was not replaced by this optimization.

## Performance and compatibility audit — 2026-10-16

Reviewed source at `2ee7b40` and fixed the following confirmed paths:

- Dynamic Objective-C `alloc`/`init` IMPs returned `AnyObject`, incorrectly
  applying the autoreleased return convention to retained results. Independent
  NSObject probes leaked with the old code in both Debug and optimized builds.
  The bridge now returns `Unmanaged`, transfers the initialized +1 result to
  ARC, and checks initializer availability before allocation. Three regression
  tests call the actual production bridge with harmless NSObject subclasses,
  verify configuration arguments, and confirm weak references become nil.
- With direct menu-bar dragging enabled, replaying an ordinary click waited for
  an all-application AX scan and used `AXPress`, which some hosted/Tauri extras
  acknowledge without presenting UI. It now refreshes only the target identity,
  validates its live geometry and identity, and posts the existing marked
  primary-click sequence.
- Closing the panel during an AX refresh could start a new, unused screenshot
  batch after cancellation. The refresh loop now rechecks panel/tap lifetime;
  image capture cooperatively stops at window, retry, sleep and screenshot-await
  boundaries. An in-flight ScreenCaptureKit request itself is not forcibly
  interrupted. Screenshot scheduling cancellation was reviewed statically;
  the tests do not inject ScreenCaptureKit callbacks.
- Private imports now share the tracked membership-operation task and exclude
  concurrent activation/promotion. Trigger clicks cannot start another
  transition during those operations. Opening the panel cancels background reconciliation; dismissing it
  rearms monitoring. Assertion requests check cancellation and generation after
  suspension so late completions cannot replace newer state or survive quit.
  These race protections were reviewed at the control-flow level; delayed real
  private-service callbacks were not injected or exercised on the live menu bar.
- Legacy discovery now uses the separator's Quartz rectangle and menu-bar Y
  strip, preserving negative-X parked items while excluding another vertically
  arranged display. Panel display selection uses full screen bounds before
  returning its usable area. Six new geometry tests cover stacked displays,
  coordinate conversion, negative coordinates, Dock insets and stale anchors.
- Build documentation now requires Xcode 26+ for the referenced Liquid Glass
  SDK. The deployment target remains macOS 14.0; macOS 27 verification uses
  Xcode 27.

Verification on macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`):

- XcodeGen generation leaves the tracked project unchanged.
- All **110 Swift Testing tests in nine suites passed** on the final source
  (101 baseline tests plus nine regressions).
- Universal Release (`x86_64 arm64`) build succeeded without source compiler
  warnings. Xcode emitted only its existing skipped AppIntents metadata warning.
- `codesign --verify --deep --strict` passed. Bundle identifier
  `local.foldbar.app`, version 0.2.0/build 2, team `42MUMXKY79`, deployment target
  14.0. Temporary Release executable SHA-256:
  `e29149e1c747a39381fa3d45b1ba4848c8023ac523d47ac1de646a2efc213200`.
- A five-second sample of the existing installed process, PID 30250 at
  `/Applications/FoldBar.app`, showed the main thread predominantly waiting for
  events, with a 145.3 MB physical footprint. This is a short baseline sample of
  the previous build, not a before/after benchmark or long-term leak profile.
- Native UI inspection timed out twice. No new real-menu-bar click/drag,
  private-service timing, privacy-onboarding, macOS 14–26, or physical
  multi-display acceptance is claimed. The installed app and tracked
  `dist/FoldBar-0.2.0-macOS.zip` were not replaced by this audit.
- Test hosts exited; temporary Debug/Release Launch Services registrations were
  removed and the inspected DerivedData directory was deleted.
  `git diff --check` passed. The pre-existing untracked `.codex-probe/` directory
  remains outside the commit.

## External import press versus click arbitration — 2026-10-11

The user reported real menu/UI activation at the moment of pressing a visible
menu-bar item to import it. The installed direct-drag preference was enabled.
The existing gesture code already consumed an eligible plain down and replayed
only on up, so that replay could not itself explain activation during a held
press. Its session-stage tap was a plausible later interception point; Apple
places the HID stage at WindowServer entry and the session stage at login-session
entry ([CGEventTapLocation](https://developer.apple.com/documentation/coregraphics/cgeventtaplocation)).
This ordering explanation is an inference, not a reproduced pre-fix trace.

The scoped filter now prefers a head-insert HID tap. If creation is unavailable,
it retains the existing scoped session fallback and logs the actual location;
no extra permission prompt or identity change was added. Candidate geometry,
modifier eligibility, marked synthetic replay bypass, visible-panel lifetime,
and live revalidation before click/import remain unchanged. Diagnostics record
claimed candidate presses, click/drag decisions, and tap disable notifications,
without logging unrelated input or pointer coordinates.

A concrete state-machine defect was also fixed: a release at least 5 points
from its down could replay a click if no intermediate dragged event arrived,
even while still inside the original status-item rectangle. Such coalesced
sequences now begin/end a drag and never replay a click. If the tap is disabled
while a claimed press is pending or dragging, the interaction is canceled,
its remaining drag/up events are consumed after recovery, and no click is
replayed. Active cancellation ends with no drop target and clears the preview.
A normal released click within the threshold still activates once after the
existing identity/frame checks.

Verification on macOS 27.0 with Xcode 27.0:

- XcodeGen registered `MenuBarImportGestureTests.swift`; project settings and
  application identity remain unchanged. All **101 Swift Testing tests in eight
  suites passed** on the final source. Eight new event-sequence tests cover held
  presses, jitter/released clicks, threshold drags, coalesced drags, pass-through,
  Command-drag, and cancellation of pending/active gestures. They exercise the
  same synchronous decision path without creating taps, posting OS input, or
  modifying defaults. The canceled-session test-host XPC diagnostic did not
  cause a failure; the test host exited.
- The universal Release build succeeded with no source compiler warnings;
  Xcode emitted the existing skipped AppIntents metadata warning.
- Candidate and installed app passed `codesign --verify --deep --strict`.
  Bundle ID `local.foldbar.app`, version 0.2.0/build 2, team `42MUMXKY79`, and
  designated requirement match the prior build. Architectures: x86_64 and arm64.
  Installed executable SHA-256:
  `0d11ba1f0a246d4b911486ca11ac9fe1eacf5df9b511a3ab3ee2b577ee645d10`.
- The sole running app was `/Applications/FoldBar.app`, PID 30250. Native UI
  inspection at 14:45:19 showed all nine panel proxies. At 14:45:18.516 the
  installed process logged `import tap created location=0` (HID), followed by
  `menu-bar import armed candidates=2 cachedBundles=9 persistedBundles=10`.
  The direct-drag preference remained enabled.
- Native MenuBarAgent screenshots still provided a blank white menu-bar strip,
  so no trustworthy source coordinates were available for an automated physical
  press/hold/drag. This pass verifies actual HID-tap creation and unit gesture
  behavior; it does not establish that every real status-item menu stays closed
  during live dragging. Multi-display, macOS 14–26, and privacy onboarding were
  not re-proven. No system `«` interaction was performed.
- The prior build is preserved in the verified backup ZIP
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-press-drag-fix-2026-10-11-1444.zip`.
  Temporary Debug/Release registrations were removed and the exact inspected
  DerivedData directory was deleted. No new crash report appeared. No TCC reset,
  preference deletion, distribution archive update, commit, or remote operation
  was performed. `git diff --check` passed.


## External drag preview black outline — 2026-10-11

The user supplied a runtime screenshot showing a tight black rounded outline
around an external Notion import preview. The shared cell surface contains no
stroke or shadow. The external transparent borderless NSPanel still enabled an
independent AppKit window shadow, unlike the individual grid cells. This was
the identified source candidate for the extra outline.

The external preview now sets `hasShadow = false` so the shared cell surface
alone draws the card. Card dimensions, native artwork size, fill, and corner
radius remain shared with the panel. The main overflow panel retains its shadow.
No capture, membership, event forwarding, or permission behavior changed.

Verification on macOS 27.0 with Xcode 27.0:

- XcodeGen generation remained consistent with `project.yml`. All **93 Swift
  Testing tests in seven suites passed**, including preview movement, sizes,
  late screenshots, cancellation, and colour recovery. No additional test was
  added for this low-impact window appearance setting.
- The universal Release build succeeded with no source compiler warnings;
  the existing AppIntents metadata warning remains.
- Candidate and installed app passed `codesign --verify --deep --strict`.
  Bundle ID `local.foldbar.app`, version 0.2.0/build 2, team `42MUMXKY79`, and
  designated requirement match the previous installed build. Architectures:
  x86_64 and arm64. Installed executable SHA-256:
  `281db0fa751866eaad3a51cca941cbc4d1c4e64b9006486629701850348f67d4`.
- The sole running app after clean replacement was `/Applications/FoldBar.app`,
  PID 6616. At 14:26:52 native UI inspection confirmed the panel still rendered
  its nine proxies normally. End-to-end live external dragging and the
  disappearance of the outline still require runtime observation; compilation and existing window
  tests alone are not visual acceptance evidence for the WindowServer shadow.
- The previous app is preserved in the verified backup ZIP
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-drag-border-fix-2026-10-11-1426.zip`.
  Debug/Release app registrations were removed and the exact inspected temporary
  DerivedData directory was deleted. No new crash report appeared. No TCC reset,
  preference deletion, distribution archive update, commit, or remote operation
  was performed. `git diff --check` passed.


## Icon colour recovery and matching drag cells — 2026-10-11

This supersedes the blue drag-card appearance and colour interpretation in the
previous section. Native inspection reproduced pink fringes on Eagle and
CodexSquad, with Bob and PixPin also carrying wallpaper tint. The capture
classifier had counted chroma in already-composited antialiased pixels, and
its coloured output multiplied those screenshot pixels by estimated alpha,
retaining the wallpaper matte and reducing genuine colour opacity.

Capture now fits neutral artwork against the sampled local background before
classifying it as coloured. Neutral templates retain grey detail. For genuinely
coloured artwork, flat chromatic interiors provide a small foreground palette;
edge coverage is recovered against the background and output is premultiplied
foreground colour. Neutral edges within coloured artwork are also un-matted.
The existing clipping, displaced-artwork, substantial-artwork, menu-strip, and
fail-open membership gates remain in place. Uniformly translucent artwork or
colour gradients without a flat core still use a conservative estimate; this
pass does not establish perfect reconstruction of every possible status item.
The source bitmap context is kept alive until its pixel buffer has been copied.

Panel cells, native panel drag previews, and external import previews now use
one `OverflowIconCellSurface`. Square cards are 46 points high and wide, with
9-point corners and the same native artwork sizing, fill, and appearance.
Wide previews retain the original status-item frame's one-to-three-column span,
including when the screenshot arrives late. No blue overlay or border is added
to the dragged card. The destination drop zone retains its existing feedback.

Verification on macOS 27.0 with Xcode 27.0:

- XcodeGen registered the two new test files; no target identity or build
  setting changed. All **93 Swift Testing tests in seven suites passed**.
  New tests inspect output RGB and opacity for white/grey antialiasing on pink,
  same-hue coloured cores, mixed neutral/coloured edges, and blank backgrounds.
  Actual preview-window tests check square/wide dimensions and late-image spans;
  existing movement and cancellation tests also pass.
- The universal Release build succeeded with no source compiler warnings.
  The only build warning is the existing skipped AppIntents metadata extraction.
  The test host emitted a canceled-session XPC diagnostic; no test failed and
  the host exited.
- Candidate and installed app passed `codesign --verify --deep --strict`.
  Bundle ID `local.foldbar.app`, version 0.2.0/build 2, team `42MUMXKY79`, and
  designated requirement match the prior installed app. Architectures:
  x86_64 and arm64. Installed executable SHA-256:
  `04945f1ca8f19d3f9bac9ccfba7c7433ccf7a8f8e6fc3000a3ec6edfd4cd12ad`.
- The sole running app was `/Applications/FoldBar.app`, PID 98154. At 14:14:31,
  native UI inspection showed all **nine proxies**: ChatGPT, LOGO 16 black,
  Notion, Clash Verge, Bob, Eagle, PixPin, CodexSquad, and 微信输入法.
  The previous pink contamination was no longer visible. Bob and PixPin now
  render as neutral artwork; their earlier pink was not evidence of an intrinsic
  pink icon. Genuine colour preservation is covered by pixel regressions.
- NeatDownloadManager's previously displaced/blank capture is still rejected;
  its saved intent was preserved. No new item was hidden on an unusable image.
- End-to-end external pointer dragging and dropping was not re-proven by native
  automation; the frame, image sizing, shared style, movement, and cancellation
  have code/window-test evidence. Multi-display interaction, proxy clicks,
  privacy onboarding, and the macOS 14–26 path were not re-proven in this pass.
- The prior installed build is preserved in the verified backup ZIP
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-color-parity-2026-10-11-1414.zip`.
  Temporary Debug/Release registrations were removed and the exact inspected
  DerivedData directory was deleted after verification. No new crash report
  appeared. No TCC reset, preference deletion, distribution archive update,
  commit, or remote operation was performed. `git diff --check` passed.


## Real icon capture and original drag appearance — 2026-10-11

This supersedes the loading-indicator approach recorded below. The user's
screenshot and installed import logs showed that the floating preview was
tracking a drag while its real screenshot remained unavailable. The spinner
made that capture failure look like an ongoing load and changed the appearance
of the original blue drag card.

The shared `IconDragPreviewSurface` is restored to its original image-based
appearance. An active cold drag retains its latest pointer location; a late
real screenshot appears there, and cancellation prevents it from reopening.
There is no spinner or application-icon substitute on the macOS 27 path.

Capture diagnosis showed usable ScreenCaptureKit images being rejected because
wallpaper gradients were classified as artwork reaching the capture edges.
Capture now uses an explicit display-local item rectangle and a separately
filtered background sample. A four-corner residual corrects menu material
differences between the two samples. The region-image fallback uses the same
background sample. Significant coloured artwork keeps its colour. Square items
can receive three points of padding within the display's menu strip and clear
of the other items in that capture batch. Disconnected peripheral edge fragments
are discarded; components reaching the centre still fail the clipping check.
Weak neutral noise and substantially displaced artwork cannot create a proxy.
Wide text and meter items retain their complete component layout.

An attempted capture from full-width app-owned host windows did not resolve
the remaining items and was removed. The final implementation captures only
validated item rectangles, retains screenshots in memory, and keeps the
existing private assertion and fail-open membership checks. No system `«`
interaction was performed.

Verification on macOS 27.0 with Xcode 27.0:

- `xcodegen generate` left the tracked project unchanged; `git diff --check`
  passed. All **85 Swift Testing cases in five suites passed**. Added coverage
  includes display-local coordinates, padding boundaries and neighbours,
  nonlinear wallpaper samples, colours on similar-hue backgrounds, peripheral
  fragments, weak material noise, displaced artwork, pointer updates, late
  screenshot delivery, and cancellation.
- The universal Release build succeeded with no source compiler warnings.
  Xcode emitted its existing AppIntents metadata warning because this app has
  no AppIntents framework dependency.
- Candidate and installed app passed `codesign --verify --deep --strict`.
  Bundle ID `local.foldbar.app`, version 0.2.0, signing identity and designated
  requirement remain unchanged. Architectures: arm64 and x86_64.
- Installed executable SHA-256:
  `a511e88978e71712836c98c93199c9d531b827a46860aec05d4b8ab2d7b879c5`.
  The sole running app was `/Applications/FoldBar.app`, PID 82416.
- At 13:52:45, native UI inspection of that installed candidate confirmed
  **seven rendered proxies**: ChatGPT, LOGO 16 black, Notion, Clash Verge,
  Bob, PixPin, and 微信输入法. Bob and PixPin retained visible pink artwork.
  NeatDownloadManager was omitted after its capture showed displaced or
  incomplete artwork. It was not newly hidden on that evidence; its persisted
  intent remains available for a later capture. No empty proxy was rendered.
- Import prefetch logs confirmed real images for visible Eagle, CodexSquad,
  and AlDente candidates. Native menu-bar automation screenshots did not
  supply usable source coordinates, so an end-to-end external pointer drag
  and successful drop still require installed-runtime user acceptance.
  Proxy activation, multi-display interaction, privacy onboarding, and the
  macOS 14–26 path were not re-proven by this pass.
- The previous spinner build is preserved in the verified backup ZIP
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-real-capture-fix-2026-10-11.zip`.
  Temporary Debug/Release app registrations were removed, and the exact
  verification DerivedData directory was inspected and deleted after testing.
  No new crash report appeared. No TCC reset, preferences deletion, commit,
  distribution archive replacement, or remote operation was performed.

## Immediate external drag preview — 2026-10-11

Historical intermediate build; superseded by the real-capture correction above.

The user observed no icon following the pointer during a menu-bar import.
The installed import log confirmed two active drag sessions at 13:05:25 and
13:05:28; both ended outside the drop targets. The preview code only created
its floating NSPanel when an image was available. A cold cache or failed
real screenshot therefore left an otherwise active drag with no pointer
feedback.

External drags now create the floating preview immediately, using a loading
indicator while the real screenshot is unavailable. Every pointer update moves
that panel; a completed screenshot replaces the loading surface at the most
recent point. Image updates after cancellation cannot reopen the panel. The
loading indicator is never added to the real-image cache or used to hide an
application; existing identity, screenshot, and membership checks remain in
place. Import logs now distinguish a warm preview, a completed screenshot, and
an unavailable screenshot.

Verification on macOS 27.0 with Xcode 27.0:

- All 76 Swift Testing cases passed. Three new tests instantiate the actual
  preview NSPanel and check immediate visibility without an image, movement
  after pointer updates, replacement at the latest point, and cancellation.
  These window-state tests are not a live pointer-drag acceptance pass.
- `xcodegen generate` left the tracked project consistent with `project.yml`.
- Universal Release build succeeded with no source compiler warnings. Xcode
  emitted the existing AppIntents metadata warning.
- Candidate passed `codesign --verify --deep --strict`, retained identifier
  `local.foldbar.app` and the installed designated requirement, and contains
  arm64 and x86_64 slices.
- Executable SHA-256:
  `35a46507052f431f372786c492961ab939ddf7c7e2acdc3c5e984410dbfcb9a5`.
- The exact candidate was installed at `/Applications/FoldBar.app`. The prior
  app is preserved in the verified ZIP
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-preview-fix-2026-10-11.zip`.
- Installed PID 55371 remained running through the 45-second observation with
  no new crash report. The opened panel logged 10 import candidates. Temporary
  Debug/Release app registrations and the exact verification directory were
  removed after inspection. `git diff --check` passed; no commit or remote
  operation was performed.
- A real drag with this candidate still requires user acceptance. The native
  UI automation menu-bar screenshot did not provide usable drag coordinates.
  Screenshot success, full import, proxy activation, privacy onboarding, and
  macOS 14–26 interactions were not re-proven by these tests.

## Visible-item direct import regression — 2026-10-11

The user reported that a plain drag closed the panel before any drag preview
appeared. The image correction introduced fail-open capture behavior, but the
macOS 27 import-candidate filter still excluded the full persisted managed set.
A persisted application whose capture failed therefore remained visible while
being absent from both the panel and its drag candidates. The outside-click
monitor dismissed the panel on mouse-down because that item was not eligible.
Live inspection of the previous installed build confirmed that direct drag was
enabled, the panel contained only two cached proxies, and persisted PixPin,
Clash Verge, and ChatGPT items remained present in MenuBarAgent.

The filter now excludes only the bundles represented by FoldBar's active panel
cache. Visible uncaptured bundles can start another import. The real-frame
checks still reject off-strip, notch, and occluded rectangles. The system
overflow control is used solely as a rectangle occlusion check; its position
does not define import membership. Capture and identity checks before hiding
remain intact. Import monitoring now logs setup and drag begin/end for runtime
diagnosis.

Verification on macOS 27.0 with Xcode 27.0:

- `xcodegen generate` left the tracked project unchanged.
- All 73 Swift Testing cases passed. New regressions cover direct mouse-down
  eligibility of visible uncaptured bundles, exclusion of cached bundles,
  negative-X display geometry, occlusion, and independence from the system
  overflow boundary.
- The universal Release build succeeded without source compiler warnings.
  Xcode emitted its existing AppIntents metadata warning because the app has
  no AppIntents framework dependency.
- The Release candidate and installed app passed
  `codesign --verify --deep --strict`; bundle identifier and designated
  requirement match the prior installed app. Architectures: arm64 + x86_64.
- Executable SHA-256:
  `778a5a025df9d513860247d1bf2df95c3e30aa068cc986fc320961adfbe79e27`.
- The exact candidate was installed at `/Applications/FoldBar.app` and ran as
  PID 54594. Opening the installed panel logged `candidates=8 cachedBundles=1
  persistedBundles=8`, confirming that visible items in the persisted set
  were no longer all excluded. The prior app is preserved in the verified ZIP
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-drag-fix-2026-10-11.zip`.
- Full pointer-drag acceptance is pending the user's installed-runtime retry.
  The UI automation interface exposes the menu extras but its menu-bar capture
  is blank, so it did not supply usable drag coordinates. Unit tests and
  listener setup alone do not prove successful drop, screenshots, or proxy
  activation. The macOS 14–26 path was not manually exercised.
- The installed process remained running for more than one minute without a
  new crash report. Temporary Debug and Release app registrations were removed,
  and the exact verification DerivedData directory was deleted after inspection.
- `git diff --check` passed. Existing unrelated changes were preserved; no
  commit, distribution ZIP replacement, or remote operation was performed.

## Menu-bar proxy image correction — 2026-10-09

The macOS 27 region-capture path previously converted every real screenshot
to a monochrome template. It now keeps the sampled colour pixels for artwork
with significant chroma and retains adaptive templates for neutral glyphs.
The panel continues to use the captured item's original aspect ratio.

The managed-item path no longer accepts an owning application's icon as a
substitute for its menu-bar artwork. Initial collapse retries missing captures
and hides only application bundles whose observed menu extras all have real
captures. A late-launching or restarted application stays visible while its
new generation is uncaptured; the collapsed monitor captures it before adding
that bundle to the assertion. Import likewise declines to hide an application
unless all of its observed menu extras have real captures. Preview fallback
remains available only on the macOS 14–26 path. Region capture also rejects
virtual/off-strip frames and rectangles occluded by the system overflow control;
that control is used only to avoid copying its pixels, not for membership.
ScreenCaptureKit's nullable Objective-C callbacks are used directly for
shareable-content and image requests so an empty result does not trap in the
generated Swift async bridge.

The first installed candidate (`f8279add6c595bbecbd63e9319c7218e047918e34b8cc7a36dfc0f39d7602a1d`)
crashed about 14 seconds after launch. The crash report at
`~/Library/Logs/DiagnosticReports/FoldBar-2026-10-08-233656.ips` shows
`EXC_BREAKPOINT` in the generated `SCShareableContent` async completion
handler; the system log immediately before it reports that SkyLight returned
zero active displays during a region screenshot. The previous installed app
was restored and launched before the nullable-callback repair was built.

Verification on macOS 27.0 with Xcode 27.0:

- `xcodegen generate` left the tracked project consistent with `project.yml`.
- All 70 Swift Testing cases passed, including colour and neutral screenshot
  rendering, complete per-application capture, and occluded-frame rejection.
- The Release build completed without source warnings.
- The Release app retained bundle identifier `local.foldbar.app`, passed
  `codesign --verify --deep --strict`, and contains arm64 and x86_64 slices.
- The repaired candidate executable SHA-256 is
  `5cec78ee393f7d6e57eec4def00a487f386c7dbc1c23a6f9b297bc7347fe6adb`.
  That exact build was installed at `/Applications/FoldBar.app` and ran as PID
  50808 for more than one minute with several collapsed-monitor intervals and
  no new FoldBar crash report. The prior app is preserved as a verified ZIP at
  `~/Library/Application Support/FoldBar/Backups/FoldBar-before-icon-fix-2026-10-08.zip`.
- The user's specific panel icons, proxy clicks, drag behavior, and privacy
  onboarding have not yet been visually rechecked in this installed build.

## macOS 27 late status-item reconciliation — 2026-09-26

The macOS 27 assessment assertion is an application allowlist, not only a list
of FoldBar-managed applications. The previous adapter cached only the managed
bundle set. A menu-bar application that launched or restarted after the active
assertion could therefore be absent from the effective MenuBarAgent session:
its real item was parked off-screen, but FoldBar did not persist or cache it as
a managed proxy. Replacing the assertion while the previous session remained
active updated the configured allowlist but did not make MenuBarAgent publish
the new application generation.

The final adapter keys the active configuration by the managed set, allowed
bundle identifiers, and the bundle/PID generations that currently publish
public `AXMenuExtra` elements. The collapsed macOS 27 monitor refreshes that AX
inventory before reconciling the assertion. When it observes a new un-managed
menu-extra generation without a managed-set change, it releases the stale
session for 120 ms and reapplies the same managed set. Ordinary helper launches
do not trigger this path, managed membership changes retain the existing atomic
replacement, and macOS 14–26 retain their separator implementation unchanged.

Live A/B verification used macOS 27.0 (26A428) and a temporary signed status
item with bundle identifier `local.foldbar.capacity-probe`. Before the fix its
AX frame remained off-screen at `(7, 1095, 26, 24)` across multiple five-second
monitor polls, and quitting FoldBar immediately moved it to the real menu bar.
With the final reconciliation candidate, the same item began off-screen at one
second and moved to the visible menu-bar frame `(969, 5, 26, 24)` by eight
seconds without quitting or restarting FoldBar. CodexSquad remained at a visible
menu-bar frame during this test, and the eight persisted managed bundle
identifiers were unchanged.

Final verification used Xcode 27.0, Swift 6.4, and the macOS 27.0 SDK:

- `xcodegen generate` left the tracked project consistent with `project.yml`.
- All 66 Swift Testing cases passed.
- The Release build succeeded for `x86_64` and `arm64`.
- `codesign --verify --deep --strict` passed for bundle identifier
  `local.foldbar.app`.
- Release executable SHA-256:
  `732862b210d93a6929f0bcb22e0fd85f51e3b4c7931e2259534d76f2da6c73c7`.
- The exact candidate was installed at `/Applications/FoldBar.app` and was
  running as PID 19668 for the final probe and CodexSquad checks.

## macOS 27 independent visibility candidate — 2026-09-26

The macOS 27 architecture no longer treats the system `«` control as
FoldBar's storage boundary. FoldBar dynamically loads MenuBarClientCore and
creates an `MBAssessmentModeAssertion` with an
`MBAssessmentModeConfiguration` application allowlist. macOS 14–26 retain the
existing two-`NSStatusItem` separator implementation.

The first independent-visibility candidate called
`MBVisibilityRestrictionXPCServer` directly. Its completion returned no error,
so FoldBar persisted the managed bundle and displayed its proxy, but the raw
request did not enter the effective assessment visibility session. The real
menu-bar item therefore stayed rendered, producing the reported duplicate.
The final adapter uses the framework's high-level assertion and passes the
`NSNumber` raw values of all macOS 27 `MBSystemItemIdentifier` cases instead of
display-name strings. It activates a replacement assertion before invalidating
the old one, loads no private framework on macOS 26 or earlier, and fails open
if any runtime class, selector, configuration, or completion is unavailable.

The macOS 27 managed set is persisted by application bundle identifier. This is
an observed limitation of the private service: applications that publish more
than one menu extra are imported and promoted as a group. FoldBar's panel still
contains in-memory screenshot proxies, not third-party views. The system `«`
continues to operate independently and is never clicked or expanded by the new
path.

A follow-up live regression reproduced proxy activation against Clash Verge
2.5.5 with its main window closed. Replacing the visibility assertion made the
real glyph appear, but the immediate Accessibility `AXPress` produced no Clash
Verge window after two seconds. A real primary mouse sequence at the same
identity-checked frame also failed at 50 ms and opened the expected main window
at 200 ms. The activation path now waits that bounded settling interval,
re-resolves the process, bundle, ordinal, label, frame, and visible segment, and
then sends the marked primary mouse sequence instead of relying on `AXPress`.
This is application-independent and remains fail-closed before input dispatch.

The macOS 27 panel header no longer renders the redundant Close action or its
system-overflow explanation. The remaining Settings action now uses the native
`gearshape` symbol with an icon-only label. An installed-app capture confirms
that the header renders only the gear glyph, while accessibility inspection
retains its settings help text. The visible panel text contains only the FoldBar
title and the keep-visible drop-zone copy. The same header and toggle flow now
applies on macOS 14–26: the legacy-only Expand action has been removed, so the
FoldBar arrow opens or closes the panel and the header contains only Settings
on every supported release.

Final verification used macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4,
and the macOS 27.0 SDK:

- Debug app-hosted test run: passed; all 64 Swift Testing cases passed with no
  failures, skips, or runtime warnings.
- Release build: passed with no source compiler warnings.
- Release binary: universal `x86_64` + `arm64`.
- Code-signature structural verification (`codesign --verify --deep --strict`):
  passed; identifier `local.foldbar.app`, team `42MUMXKY79`.
- Installed executable SHA-256:
  `51d66ab328d3bd22b65f0984acb7c00355cf8c9f203658ec1940066910be8538`.
- The exact candidate launched from `/Applications/FoldBar.app` as PID 8460.
  It loaded the managed bundle identifiers already persisted by the user's
  prior imports and removed their real glyphs from the rendered menu bar while
  leaving FoldBar, Wi-Fi, battery, temperature, Control Center, and the clock
  visible.

Live assertion replacement first hid all five managed applications, then
removed only `com.openai.codex` from the managed set: only the ChatGPT glyph
returned while the other four stayed hidden. Terminating the diagnostic
process restored every real glyph, confirming fail-open connection cleanup.
For the proxy-activation regression, Clash Verge began with zero windows. The
installed candidate exposed the real item, dispatched the validated click after
the settling interval, and produced one frontmost standard Clash Verge window
between the 100 ms and 300 ms observations; it remained present at 700 ms and
1,500 ms. A post-action accessibility snapshot confirmed the expected Clash
Verge home panel rather than an unrelated or empty window.
The direct drag gesture on the newly installed build and the macOS 26 legacy
regression remain user-acceptance items; the duplicate-rendering failure itself
is reproduced and corrected by installed-runtime evidence.

## macOS 27 compatibility candidate — 2026-09-20

Verified on macOS 27.0 (26A428) with Xcode 27.0 (27A266a), Swift 6.4, and
the macOS 27.0 SDK.

- Branch: `fix/macos-27-compatibility`.
- Debug app-hosted test run: passed; all 64 Swift Testing cases passed.
- Release build: passed with no source compiler warnings.
- Release binary: universal `x86_64` + `arm64`.
- Code-signature structural verification (`codesign --verify --deep --strict`): passed.
- Installed executable SHA-256:
  `6c2a33b3ab94e9279538cb84fb04daca2038026b4ab7867f781ff1bed4aa84ca`.
- Installed-runtime check: the exact `/Applications/FoldBar.app` candidate
  launched successfully as PID 46081. AppKit and Accessibility report exactly
  one registered FoldBar status item: the trigger. With no native `«` and an
  empty panel, an unmodified drag beginning on ChatGPT was claimed by FoldBar;
  the panel remained on screen through mouse-down, movement, and mouse-up. The
  unchanged real icon stayed in the menu bar and the still-open panel displayed
  `macOS 当前无折叠区；出现 « 后可收纳`, rather than dismissing, caching a fake
  proxy, or creating a capacity-reservation slot.

The immediately preceding installed build exercised the unchanged
native-overflow import path with a temporary status-item probe. It moved from
the visible Accessibility frame at `x=1019` to the native hidden frame at
`x=973` in 1,376 ms, including the 494 ms system Command-drag event sequence
and two stable hidden-position checks. No
`com.apple.ec.MenuBar.overflow.expanded` event occurred. Reopening FoldBar
showed the probe and LemonMonitor as the two in-panel proxies while the
previously hidden NeatDownloadManager was visible, proving that the cache
followed MenuBarAgent's capacity exchange rather than retaining a duplicate.
Terminating the temporary probe removed it from the menu bar.

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
cell. The expand/capture/restore transaction is now covered by an exact,
non-interactive snapshot of that display's current menu-bar strip. The shield
is excluded from screen sharing so ScreenCaptureKit still sees the real artwork
underneath it, and its window animation is disabled. Runtime sampling observed
one stable full-width, fully opaque layer-35 shield frame followed by immediate
removal, with no resize or fade sequence.

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
overflow visibility. FoldBar no longer leaves a persistent layout mask or a
click-blocking window over those coordinates; doing so reserved the same space
twice and was the cause of the original large menu-bar gap. A second, narrower
gap remained because macOS 27 reserves a 16-point outer host slot even when the
legacy separator's content length is zero. The candidate now unregisters that
legacy separator before first presentation and uses the system `«` boundary for
promotion verification. macOS 14–26 retain the two-item separator path. The
panel action is labelled Close on macOS 27. Clicking FoldBar's trigger while
the panel is open is excluded from the outside-click monitor, allowing the
trigger's own mouse-up action to close the panel instead of reopening it.

Accessibility scanning runs on a utility task and publishes a short-lived
MainActor cache. Synthetic item identifiers are deterministic and occupy a
reserved range. Before an Accessibility-backed proxy click or synthetic
Command-drag, FoldBar re-resolves the owning process, bundle identifier, item
ordinal, semantic label when needed, and live frame. Any mismatch fails closed
and leaves the real menu bar available for manual operation.

The macOS 27 import path now preserves the already-prefetched real glyph before
closing the panel, performs the native Command-drag, and verifies only that
specific Accessibility identity plus the native overflow boundary. It no longer
walks every running application for each verification poll and no longer opens
`«` after the drop to recapture the icon. The earlier full-scan prototype took
6,152 ms in the same installed-runtime test; the targeted path completed in
1,376 ms and avoided the visible return/flash caused by post-import expansion.
Two consecutive hidden readings are still required before the proxy cache is
committed.

The native overflow count on macOS 27 is capacity-managed by MenuBarAgent and
varies with the foreground application's menu width. Moving one selected item
to the hidden side can therefore make a previously hidden item visible; FoldBar
updates its proxies to the final native membership instead of representing the
operation as an unlimited custom container. macOS 14–26 retain the enlarged
separator model and are unaffected by this rule.

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
- Overflow-panel dismissal geometry that leaves trigger clicks to the trigger's
  own open/close action.

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
