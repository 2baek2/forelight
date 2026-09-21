# Forelight Final QA Gate Review — Pass A

- recommendation: **APPROVE**
- blockers: **None**
- reviewType: Native macOS visual and functional QA, pass A (read-only)
- originalIntent: Verify the current Forelight MVP as a menu-bar-only macOS app that keeps the frontmost normal window clear on every connected display, dims other visible content, and provides a status item with an enable toggle and four intensity presets.
- desiredOutcome: The foreground App Store window is visibly undimmed, Discord/background content is visibly dimmed, Forelight remains discoverable in the menu bar, and the current source implements one active-window cutout per connected display plus the requested controls.

## User Outcome Review

The current artifact satisfies the visible core outcome. `/tmp/forelight-final-qa.png` shows the foreground App Store window bright while Discord, the desktop, and rear content are under a dark veil. A status item is visible in the top menu bar. The capture is valid 2940×1912 RGBA PNG evidence and is fresh: it postdates `OverlayController.swift` by 13 seconds and the reviewed app binary by 1 second.

The source supports the remaining functional intent. `main.swift` uses accessory activation and `Info.plist` sets `LSUIElement = true`; `AppDelegate.swift` creates the status item, enable toggle, and a submenu generated from exactly four presets; `OverlayController.swift` creates one overlay per `NSScreen`, selects the first front-to-back layer-0 window intersecting each target display, converts that window's Quartz frame into the target screen's Cocoa coordinates, and cuts it out of that display's dim layer. A fresh `swift build` completed successfully, and the bundled Forelight process was alive during review.

## Blockers

None.

## Criterion Review

- `C1 current-build visual evidence`: PASS — `/tmp/forelight-final-qa.png` mtime `2026-09-20 23:49:13 +0900`; latest reviewed source mtime `23:49:00`; `.build/Forelight.app/Contents/MacOS/Forelight` mtime `23:49:12`.
- `C2 active window clear / background dimmed`: PASS — the large App Store window is bright; Discord, desktop, rear windows, and non-cutout regions are dimmed in the capture.
- `C3 menu-bar-only status control`: PASS — status item is rendered in the capture; menu-bar-only configuration is at `Sources/Forelight/main.swift:3-7` and `Resources/Info.plist` (`LSUIElement = true`).
- `C4 toggle and four intensity presets`: PASS by source trace — toggle construction/action at `Sources/Forelight/AppDelegate.swift:45-53,94-98`; four preset definitions at `Sources/Forelight/OverlayController.swift:11-16`; preset submenu/action/checkmark at `Sources/Forelight/AppDelegate.swift:57-71,100-104`.
- `C5 per-display frontmost normal-window selection`: PASS by source trace — per-screen overlay construction at `Sources/Forelight/OverlayController.swift:89-93`; per-overlay selection at `:103-113`; front-to-back, visible, layer-0, display-intersection filtering at `:123-151`; display-specific coordinate conversion at `:226-243`.
- `C6 build and launch`: PASS — `swift build` rerun returned `Build complete!`; process `/Users/hyunjoonkim/Documents/code/my_hazeover/.build/Forelight.app/Contents/MacOS/Forelight` was alive as PID 5721 during review.

## Remove-AI-Slops and Programming Pass

- Directly reviewed all three production source files. No unnecessary parsing/normalization, speculative abstraction, broad defensive layers, or implementation-mirroring production structure was found that violates a success criterion.
- No tests exist, so there are no excessive, deletion-only, requested-removal-only, tautological, prose-pinning, or implementation-mirroring tests creating false confidence. The absence of interaction tests is an evidence gap, not a stated-criterion failure for this requested screenshot/source QA pass.
- Pure LOC: `AppDelegate.swift` 100, `OverlayController.swift` 209, `main.swift` 6. `OverlayController.swift` is in the programming warning band (200–250) but below the 250-line blocking threshold; this is a maintenance NOTE only.
- `WindowSnapshot.ownerPID` is retained after filtering but not subsequently consumed. This is a minor dead-field NOTE and does not violate a stated criterion.
- Existing reports `.omo/evidence/forelight-mvp-gate-review.md` and `.omo/evidence/forelight-mvp-pass-b-gate-review.md` include explicit slop/overfit coverage, but they review an older failing/stale capture. They were consulted as untrusted historical evidence and do not override this direct current-artifact pass.

## Checked Artifact Paths

- `/tmp/forelight-final-qa.png`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/AppDelegate.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/OverlayController.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/main.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Resources/Info.plist`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Package.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/README.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.build/Forelight.app/Contents/MacOS/Forelight`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-mvp-gate-review.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-mvp-pass-b-gate-review.md`

## Exact Evidence Gaps

- No open-menu capture demonstrates the rendered toggle, preset submenu, selected checkmark, or menu legibility over the overlay.
- No interaction record demonstrates toggle-off/on or switching among the four presets.
- No multi-monitor capture demonstrates simultaneous per-display cutouts; implementation is verified by source trace only.
- No automated tests, current-attempt code-review report, manual QA matrix, or notepad path was supplied or found.
- The workspace is not a Git repository, so changed-file history and a commit/branch diff cannot be reproduced.

These gaps lower confidence from HIGH to MEDIUM, but none provides evidence that a stated criterion fails.
