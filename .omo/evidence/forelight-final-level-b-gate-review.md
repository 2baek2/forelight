# Forelight Final Visual QA B Gate Review

- recommendation: **APPROVE**
- userVerdict: **PASS**
- confidence: **MEDIUM**
- reviewType: Native macOS visual fidelity and interaction-wiring review, pass B (read-only product review; report artifact only)
- originalIntent: Deliver a visually unobtrusive focus overlay that leaves the foreground window clear, dims background content, and remains controllable through a usable menu-bar item.
- desiredOutcome: A fresh current-build capture shows a clean foreground/background hierarchy and readable menu bar, while the current source coherently wires ON/OFF, intensity presets, selected state, About, and Quit.

## User Outcome Review

The current artifact satisfies the requested MVP outcome. `/tmp/forelight-final-level.png` is a valid 2940×1912 RGBA PNG and is newer than all three reviewed source files. It shows the foreground App Store window bright and fully legible while Discord, the desktop, the calendar, and rear windows are uniformly dimmed. The active-window boundary follows the App Store frame cleanly, including the rounded top corners, without visible opaque fill, offset, clipping, or halo.

The top menu-bar strip remains visible and readable. Source and reproduced AppKit values explain the result: the overlay uses `.floating` level 3, below `.mainMenu` 24, `.statusBar` 25, and `.popUpMenu` 101. Therefore normal app windows are covered while menu text, status items, and popup menus stay above the overlay. The configured `viewfinder` SF Symbol is available on the review host.

The menu is coherently wired in source. The context-sensitive toggle updates the controller and rebuilds its title; a local AppKit target-resolution reproduction confirmed its nil target resolves to the application delegate. Each of the four preset items explicitly targets the delegate, carries its `Double` in `representedObject`, updates/persists the controller intensity, and receives the native selected-state checkmark. About and Quit also have explicit targets.

## Blockers

None.

## Evidence Trace

- Capture freshness and integrity: `/tmp/forelight-final-level.png`; PNG signature; 2940×1912; RGBA; capture mtime `2026-09-20 23:59:59 +0900`, later than latest reviewed source mtime `23:57:04`; SHA-256 `caff9fa3f2df77ef04c5f7763f23ed27d10c25fd6673f3845fd976609258f1ca`.
- Visual hierarchy: foreground App Store region, approximately x=624..2939 and y=45..1911, is bright; Discord/desktop/rear-window regions are materially dimmed but recognizable.
- Transparency and cutout: `Sources/Forelight/OverlayController.swift:171-177` makes a non-opaque clear overlay window; `:201-222` draws a black-alpha even-odd path around the cutout. The pixels show no opaque fill inside the foreground window.
- Menu-bar visibility: `/tmp/forelight-final-level.png` top strip and diagnostic crop `/tmp/forelight-final-level-menubar-current.png`; menu text and status icons render above the dimmed desktop. `Sources/Forelight/OverlayController.swift:175` uses `.floating`; reproduced levels were `floating=3`, `mainMenu=24`, `statusBar=25`, `popUpMenu=101`.
- Status control: `Sources/Forelight/AppDelegate.swift:21-29` creates a square status item with a `viewfinder` symbol, accessibility description, tooltip, and attached menu. Runtime symbol construction returned non-nil.
- Toggle: `Sources/Forelight/AppDelegate.swift:48-53,94-98`; local AppKit target lookup returned `toggle_target_is_delegate=true`.
- Presets: `Sources/Forelight/OverlayController.swift:11-16` defines exactly 30%, 45%, 60%, and 75%; `Sources/Forelight/AppDelegate.swift:57-71,100-104` constructs the submenu, sets explicit targets, applies values, and marks the active value.
- Build: a fresh `swift build` completed successfully (`Build complete! (0.60초)`); the captured app process was running from `.build/Forelight.app/Contents/MacOS/Forelight` as PID 7102.

## Findings

- `[product] POSITIVE — /tmp/forelight-final-level.png, foreground App Store window`: Clear focal hierarchy; the active window remains undimmed while surrounding content recedes without disappearing.
- `[product] POSITIVE — Sources/Forelight/OverlayController.swift:171-177,201-222`: Transparency is implemented as a real clear window plus even-odd cutout, not a static or opaque approximation.
- `[product] POSITIVE — Sources/Forelight/AppDelegate.swift:45-104`: Menu copy, toggle state, preset values, selected checkmark, and action flow are internally coherent.
- `[evidence] MEDIUM — /tmp/forelight-final-level.png, top menu-bar strip`: The menu is closed, so the frame does not directly show the rendered ON/OFF item, expanded preset submenu, selected checkmark, or click feedback. Source/runtime target tracing supports them, but an open-menu capture and settled toggle/preset sequence would raise confidence to HIGH.
- `[evidence] LOW — live interaction surface`: Desktop-control inspection timed out, so no fresh UI click-through was added. This is an evidence gap, not proof of a product failure.
- `[product] NOTE — Sources/Forelight/OverlayController.swift:117-120,150`: `WindowSnapshot.ownerPID` is retained after filtering but not consumed downstream. This minor dead state does not violate a stated visual or control criterion.
- `[product] NOTE — Sources/Forelight/OverlayController.swift`: 209 pure LOC is in the programming guidance warning band (200–250) but remains below the 250-line defect threshold.

## Remove-AI-Slops and Programming Review

- Directly inspected the three supplied production files. No unnecessary parsing/normalization, speculative protocol/factory, pass-through wrapper, broad catch, repeated defensive layer, or implementation-mirroring production structure was found.
- No tests exist, so there are no excessive, deletion-only, requested-removal-only, tautological, prose-pinning, snapshot-only, or implementation-mirroring tests creating false confidence. Missing interaction tests remain an evidence gap, not a stated-criterion failure in this requested screenshot/source gate.
- Pure LOC: `AppDelegate.swift` 100, `OverlayController.swift` 209, `main.swift` 6.
- The prior pass-A report `.omo/evidence/forelight-final-level-gate-review.md` explicitly covers the same slop/overfit and programming perspectives. It was treated as untrusted supporting evidence; this pass independently repeated those checks.

## Checked Artifact Paths

- `/tmp/forelight-final-level.png`
- `/tmp/forelight-final-level-menubar-current.png` (diagnostic crop derived from the supplied current capture)
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/AppDelegate.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/OverlayController.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/main.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Resources/Info.plist`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Package.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/README.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.build/Forelight.app/Contents/MacOS/Forelight`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-final-level-gate-review.md`

## Exact Evidence Gaps

- No open-menu capture shows the ON/OFF item, all four preset labels, or selected checkmark at runtime.
- No settled toggle-off/toggle-on or preset-change capture sequence was supplied or reproduced.
- No 75% intensity capture demonstrates the strongest preset with the menu open.
- No multi-monitor capture demonstrates simultaneous per-display behavior; that behavior is source-traced only.
- No standalone manual QA matrix or notepad path was supplied or found.
- The workspace has no Git metadata, so changed-file history and a branch diff cannot be reconstructed.

These gaps lower confidence from HIGH to MEDIUM. None is evidence that a stated success criterion fails.
