# Forelight MVP Gate Review, Pass B

- recommendation: **REJECT**
- userVerdict: **REVISE**
- reviewType: Native macOS visual and interaction QA, pass B (read-only source review; report artifact only)
- originalIntent: Review the current Forelight MVP as a user sees it: the active window remains bright, inactive/background content is dimmed unobtrusively, and a readable menu-bar control exposes ON/OFF and intensity choices.
- desiredOutcome: A fresh current-build capture visibly demonstrates the focus effect, while the status item and its menu remain discoverable and readable at every offered intensity and their interactions are evidenced.

## User Outcome Review

The fresh 2940x1912 RGBA capture is newer than all three supplied source files and the bundled executable. It shows the large foreground App Store window bright and legible while Discord, the desktop, and other background content are materially dimmed. That satisfies the central active-window/background hierarchy and corrects the active-window failure recorded by pass A.

The menu-bar surface is not yet acceptable for the stated outcome. The entire menu-bar strip is visibly dimmed in `/tmp/forelight-final-qa.png`, including third-party/status-item regions. Source explains why: `OverlayWindow.level = .screenSaver` and `orderFrontRegardless()` keep the black overlay above AppKit's main-menu, status-bar, and pop-up-menu levels. Locally reproduced raw levels were `mainMenu=24`, `statusBar=25`, `popUpMenu=101`, and `screenSaver=1000`. The current 45% capture is subdued but still parseable; the offered 60% and 75% presets will darken the same control surface further. The single capture also leaves the menu closed, so the ON/OFF item, intensity submenu, checkmark, and interaction feedback are not visible.

## Blockers

1. violatedCriterion: `MVP-04 readable menu-bar ON/OFF and intensity control`
   - observation: The overlay is above both the status bar and pop-up menus, so Forelight dims its own control surface. The screenshot confirms the menu-bar strip is under the dim layer; the `Strong (60%)` and `Deep (75%)` options make this increasingly incompatible with a consistently readable control.
   - evidencePointer: `/tmp/forelight-final-qa.png` top menu-bar strip; `Sources/Forelight/OverlayController.swift:111-112`; `Sources/Forelight/OverlayController.swift:171-176`; `Sources/Forelight/OverlayController.swift:221-222`; reproduced AppKit level values in this review.
   - concreteFix: Put the overlay above ordinary app windows but below main-menu/status/pop-up-menu levels, then capture the status item and open menu at every preset, especially 75%.

## Evidence Trace

- Foreground App Store window, approximately x=624..2939 and y=45..1911: bright, high-contrast content. This maps to per-screen active-window lookup and Cocoa-coordinate conversion in `Sources/Forelight/OverlayController.swift:103-112` and `Sources/Forelight/OverlayController.swift:226-243`, then to the even-odd cutout in `Sources/Forelight/OverlayController.swift:206-218`.
- Left/background region containing Discord, another window, calendar, and desktop: visibly and uniformly dimmed. This maps to the full-screen transparent `OverlayWindow` and black alpha fill in `Sources/Forelight/OverlayController.swift:157-177` and `Sources/Forelight/OverlayController.swift:221-222`.
- Active-window boundary: aligned cleanly to the App Store frame, with a small rounded allowance from the 2-point outward inset and 8-point radius at `Sources/Forelight/OverlayController.swift:210-215`; no obvious clipping or opaque fill is visible.
- Top menu-bar strip: dimmed with the background, not excluded from the overlay. This maps to `.screenSaver` level plus `orderFrontRegardless()` at `Sources/Forelight/OverlayController.swift:112` and `Sources/Forelight/OverlayController.swift:175`.
- Status-item behavior: source creates a square status item with a `viewfinder` symbol, Forelight accessibility description, and tooltip at `Sources/Forelight/AppDelegate.swift:21-29`. The crowded, dimmed capture does not provide enough visual evidence to identify it unambiguously as a user.
- Menu semantics: source provides context-sensitive `Turn Off Forelight` / `Turn On Forelight`, a `Dim Intensity` submenu, four clearly named percentage presets, selected-preset checkmarks, About, and Quit at `Sources/Forelight/AppDelegate.swift:45-91`. The menu is not open in the supplied capture.
- Interaction routing: intensity/About/Quit items have explicit targets. The toggle has a nil target, but a local AppKit target-resolution reproduction resolved the selector to the application delegate, so this is not treated as a product defect. Actual clicks remain unobserved.

## Findings and Notes

- [product] **HIGH**: Forelight dims its own status item and nominal pop-up-menu plane because the overlay uses level 1000. Fix the overlay level and verify the menu at 30%, 45%, 60%, and 75%.
- [evidence] **MEDIUM**: No open-menu capture demonstrates readable ON/OFF wording, all four intensity choices, or the active checkmark. Add a fresh open-menu capture and an expanded intensity-submenu capture from the same current build.
- [evidence] **MEDIUM**: No observed toggle-off/toggle-on or preset-change sequence exists. Record settled before/after frames proving the overlay disappears/reappears and intensity changes while the menu remains usable.
- [product] **POSITIVE**: The main visual hierarchy now works: active App Store content remains bright while inactive windows and desktop content recede.
- [product] **POSITIVE**: The cutout is transparent rather than an opaque mock; `isOpaque = false`, clear window background, even-odd path construction, and the fresh screenshot agree.
- [product] **POSITIVE**: The menu copy is short and semantically clear in source. No CJK clipping issue applies to Forelight's English-only menu strings; visible Korean text in App Store belongs to the focused host app and is not clipped by Forelight.

## Remove-AI-Slops and Programming Pass

- Scope: the three supplied Swift files, because this directory is not a Git repository and no diff can be reconstructed.
- Tests: no test files exist. Therefore there are no excessive, deletion-only, removal-only, tautological, snapshot-prose, or implementation-mirroring tests to reject. The absence of interaction tests is an evidence gap, not an overfit finding.
- Production code: no unnecessary parsing/normalization layer, speculative factory/protocol, pass-through wrapper, broad catch, or comment slop was found.
- Minor maintenance note only: `WindowSnapshot.ownerPID` is retained after owner filtering but never consumed downstream (`Sources/Forelight/OverlayController.swift:117-120`, `Sources/Forelight/OverlayController.swift:138-150`). Removing the stored field would reduce dead state, but it does not violate a stated success criterion.
- Size: `AppDelegate.swift` 100 pure LOC, `OverlayController.swift` 209, and `main.swift` 6. `OverlayController.swift` is in the programming guidance's 200-250 warning band but below the 250-LOC defect threshold; this is not a blocker.
- Prior review coverage: `.omo/evidence/forelight-mvp-gate-review.md:28-29` explicitly records the same overfit/slop and size perspectives. This pass independently rechecked them; the prior report did not substitute for direct inspection.

## Checked Artifacts

- `/tmp/forelight-final-qa.png`
- `/tmp/forelight-menubar-crop.png` (diagnostic crop of the supplied image)
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/AppDelegate.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/OverlayController.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/main.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Resources/Info.plist`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Package.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/README.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.build/Forelight.app/Contents/MacOS/Forelight`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-mvp-gate-review.md`

## Exact Evidence Gaps

- No open-menu screenshot showing the ON/OFF item.
- No expanded intensity submenu showing all four choices and the current checkmark.
- No capture at `Strong (60%)` or `Deep (75%)`, where self-dimming is most consequential.
- No toggle-off/toggle-on interaction sequence.
- No preset-change interaction sequence.
- No before/after capture proving the cutout follows a foreground-window change.
- Build success was supplied by the executor and the binary/source timestamps are consistent, but `swift build` was not rerun because this pass was explicitly read-only.
- No executor evidence directory beyond the prior gate report, no standalone code-review report, no manual QA matrix, and no notepad path were supplied or found.
- No Git metadata exists, so changed files and a branch diff cannot be independently reconstructed.
- The computer-use surface could launch the current bundle and observe its overlay, but the status item did not expose a clickable accessibility element; menu interaction could not be reproduced without using a different UI automation mechanism.

## Approval Condition

Lower the overlay below menu/status/pop-up layers, then provide fresh current-build evidence with the menu open and the intensity submenu expanded at 75%, plus settled frames for toggle off/on and one intensity change. Preserve the now-correct active-window cutout.
