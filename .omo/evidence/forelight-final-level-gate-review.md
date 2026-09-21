# Forelight Final Level Gate Review — Visual QA A

- recommendation: **APPROVE**
- blockers: **None**
- reviewType: Native macOS visual and functional QA, pass A (read-only product review; report artifact only)
- originalIntent: Verify the current Forelight MVP as a menu-bar utility whose frontmost window remains clear while other visible content dims, whose status item remains readable, and whose menu exposes ON/OFF plus four intensity presets.
- desiredOutcome: A fresh current-build capture visibly demonstrates a clean active-window cutout and background dimming, while source and macOS window-level ordering establish that the status item and its popup menu remain above the overlay.

## User Outcome Review

The current artifact satisfies the requested MVP outcome. `/tmp/forelight-final-level.png` shows the foreground App Store window bright and undimmed while Discord, the desktop, the calendar, and rear windows are materially dimmed. The cutout follows the App Store frame cleanly, including its rounded top corners, with no visible black fill, clipping, or offset.

The menu-bar strip has a darker translucent background because the desktop behind it is dimmed, but the menu-bar text and status icons remain rendered above the overlay and readable. This is consistent with the current implementation and locally reproduced AppKit levels: `.floating = 3`, `.mainMenu = 24`, `.statusBar = 25`, and `.popUpMenu = 101`. The overlay therefore sits above normal app windows but below the menu bar, status items, and popup menus.

The screenshot is a valid 2940×1912 RGBA PNG and is fresh relative to the reviewed build: latest source mtime `2026-09-20T23:57:04+0900`; bundled binary mtime `23:57:16`; running bundle process start `23:57:34`; capture mtime `23:59:59`.

## Blockers

None.

## Criterion Review

- `MVP-01 menu-bar utility`: PASS — accessory activation at `Sources/Forelight/main.swift:3-7`; `LSUIElement = true` at `Resources/Info.plist:23-24`; a readable status-item region is present in the current capture.
- `MVP-02 frontmost window clear / other content dimmed`: PASS — `/tmp/forelight-final-level.png` visibly shows the App Store window clear and all surrounding/rear content dimmed; the even-odd cutout is implemented at `Sources/Forelight/OverlayController.swift:201-222`.
- `MVP-03 menu bar and status item remain readable`: PASS — current overlay level is `.floating` at `Sources/Forelight/OverlayController.swift:175`; reproduced level ordering places it below main-menu, status-bar, and popup-menu levels; the capture visually agrees.
- `MVP-04 ON/OFF and four intensity presets`: PASS by source trace — context-sensitive ON/OFF item at `Sources/Forelight/AppDelegate.swift:45-53,94-98`; exactly four presets at `Sources/Forelight/OverlayController.swift:11-16`; submenu, actions, and current-value checkmark at `Sources/Forelight/AppDelegate.swift:57-71,100-104`.
- `MVP-05 per-display active-window cutout`: PASS by source trace for the captured single display — one overlay per `NSScreen` at `Sources/Forelight/OverlayController.swift:89-93`; per-screen front-to-back layer-0 window selection at `:103-113,123-154`; Quartz-to-Cocoa conversion at `:226-243`.

## Findings

- `[evidence] MEDIUM — /tmp/forelight-final-level.png, top menu-bar strip`: The status menu is closed, so this frame does not directly show the rendered ON/OFF wording, expanded four-preset submenu, or selected checkmark. Source and level ordering support the requirement, but an open-menu capture would raise confidence.
- `[evidence] LOW — build evidence`: The executable timestamp and running process are consistent with the current source and capture, but `swift build` was not rerun because the requested review was read-only.
- `[product] NOTE — Sources/Forelight/OverlayController.swift:117-120,150`: `WindowSnapshot.ownerPID` is stored after filtering but never consumed downstream. This is minor dead state and does not violate an MVP criterion.
- `[product] NOTE — Sources/Forelight/OverlayController.swift`: 209 pure LOC is in the programming guidance warning band (200–250) but below the blocking 250-line ceiling; no split is required for this review.

## What Is Good

- The active-window hole is a real transparent even-odd path, not a painted approximation.
- The cutout geometry aligns to the foreground window without visible seams or accidental dimming inside the App Store content.
- Rear windows and desktop content recede strongly enough to establish focus while remaining recognizable.
- `.floating` is the correct level choice for keeping ordinary windows dimmed without covering the system menu/status/popup planes.
- Menu copy is concise, presets are explicit percentages, and the selected preset receives a native checkmark.
- The implementation is small and direct; no unnecessary parsing, normalization, protocol/factory layers, broad defensive handling, or speculative abstraction is present.

## Remove-AI-Slops and Programming Pass

- Directly inspected all three supplied production files. No excessive complexity, one-off abstraction, unnecessary parsing/normalization, duplicated boundary defense, broad catch, or behavior-mirroring production structure was found that violates a success criterion.
- No tests exist, so there are no excessive, deletion-only, requested-removal-only, tautological, prose-pinning, snapshot-only, or implementation-mirroring tests creating false confidence. Missing interaction tests are an evidence gap, not a stated-criterion failure for this visual/source review.
- Pure LOC: `AppDelegate.swift` 100, `OverlayController.swift` 209, `main.swift` 6.
- `.omo/evidence/forelight-final-qa-gate-review.md:28-34` explicitly records the same slop/overfit and programming-size perspectives. This review independently repeated that pass; the prior report did not substitute for current inspection.

## Checked Artifact Paths

- `/tmp/forelight-final-level.png`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/AppDelegate.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/OverlayController.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/main.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Resources/Info.plist`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Package.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/README.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.build/Forelight.app/Contents/MacOS/Forelight`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-final-qa-gate-review.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-mvp-pass-b-gate-review.md`

## Exact Evidence Gaps

- No open-menu capture shows the ON/OFF item, all four preset labels, or the selected checkmark at runtime.
- No toggle-off/toggle-on or preset-change interaction sequence was supplied.
- No 75% intensity capture demonstrates worst-case background dimming with the status menu open.
- No multi-monitor capture demonstrates simultaneous per-display cutouts; that behavior is source-traced only.
- No standalone current-attempt code-review report, manual QA matrix, or notepad path was supplied. The prior gate report contains the required skill-perspective coverage and was checked as untrusted historical evidence.
- The workspace is not a Git repository, so changed-file history and a branch diff cannot be reconstructed.

These gaps lower confidence from HIGH to MEDIUM, but none is evidence that a stated criterion fails.
