# Forelight MVP Gate Review

- recommendation: **REJECT**
- reviewType: Native macOS visual and functional QA, pass A (read-only)
- originalIntent: Verify that the newly built Forelight MVP runs as a menu-bar-only macOS app, leaves the frontmost app window clear, dims other visible content, and exposes a real status item with an enable toggle and dim-intensity presets.
- desiredOutcome: A running bundled app whose status item is discoverable, whose overlay darkens non-active content without darkening the active window, and whose menu visibly and functionally exposes toggle and preset controls.

## User Outcome Review

The supplied capture is a real 2940x1912 screenshot from a running Forelight bundle, and it visibly shows broad dimming plus a viewfinder-style menu-bar icon. The central product promise is not demonstrated: the large, light App Store window identified as foreground by the menu bar is darkened along with the rest of the display. A full-image pixel scan found only 132 of 5,621,280 pixels with any channel at or above 220, while a clear cutout over that large light window would leave a substantial bright region.

The source contains an intended even-odd transparent cutout, status-item construction, toggle action, and four intensity presets. However, the supplied visual evidence does not show the menu open, so actual menu rendering and interactions remain unverified. The overlay uses `.screenSaver` level, which is above status-bar and pop-up-menu levels; the capture correspondingly shows the status item under the dim layer, reducing discoverability.

## Blockers

1. violatedCriterion: `MVP-02 frontmost app window remains clear`
   - observation: The foreground App Store window is uniformly dimmed in the supplied capture; no large clear region is present.
   - evidencePointer: `/tmp/forelight-final.png`; `Sources/Forelight/OverlayController.swift:103-110`; `Sources/Forelight/OverlayController.swift:194-215`

## Findings and Notes

- Product, blocking: Active-window exclusion is not observable in the capture, despite the source's intended cutout path.
- Product, non-blocking note: `.screenSaver` at `Sources/Forelight/OverlayController.swift:168` places the overlay above the status bar and pop-up menus. The status icon at approximately x=1768, y=30 in `/tmp/forelight-final.png` is visibly dimmed.
- Evidence, non-blocking gap: The status menu is closed in `/tmp/forelight-final.png`. Toggle and intensity items are source-evidenced at `Sources/Forelight/AppDelegate.swift:45-71` but not runtime-evidenced.
- Evidence, positive: A process was observed running from `.build/Forelight.app/Contents/MacOS/Forelight` (PID 3548 during review).
- Evidence, positive: Menu-bar-only configuration is supported by `Sources/Forelight/main.swift:3-7` and `Resources/Info.plist` (`LSUIElement = true`).
- Evidence, positive: Other visible content is materially dimmed in `/tmp/forelight-final.png`.
- Maintainability note: Direct `remove-ai-slops`/`programming` pass found no tautological, deletion-only, implementation-mirroring, or excessive tests because no tests exist. No unnecessary production parsing/normalization or speculative abstraction was found. `WindowSnapshot.ownerPID` is retained but unused after construction (`Sources/Forelight/OverlayController.swift:114-117,143`), a minor dead-field note only.
- Maintainability note: `Sources/Forelight/OverlayController.swift` is 209 pure LOC, within the programming skill's 200-250 warning band but below the blocking 250-LOC ceiling.

## Checked Artifacts

- `/tmp/forelight-final.png`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/AppDelegate.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/OverlayController.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/main.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Resources/Info.plist`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Package.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/README.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.build/Forelight.app`

## Exact Evidence Gaps

- No open-menu capture showing the toggle, preset submenu, selected preset, or menu legibility under the overlay.
- No observed toggle-off/toggle-on transition.
- No observed intensity change across presets.
- No before/after capture proving the active-window cutout follows a foreground-window change.
- The reported `swift build` success was not rerun during this read-only pass.
- No executor evidence directory, code-review report, manual QA matrix, or notepad path was supplied or found.
- The directory is not a Git repository, so no branch diff or changed-file history was available for comparison.

## Approval Condition

Provide a fresh capture in which a clearly light foreground window remains undimmed while surrounding windows and desktop content are dimmed, plus an open-menu capture (or equivalent runtime evidence) showing the toggle and all four intensity presets. Reconsider the overlay level so the status item and its menu are not themselves covered by the dim layer.
