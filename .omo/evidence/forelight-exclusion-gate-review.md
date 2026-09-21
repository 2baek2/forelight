# Forelight Current-App Exclusion Gate Review

- recommendation: **APPROVE**
- verdict: **PASS**
- confidence: **MEDIUM**
- reviewType: Native macOS visual/functional QA, read-only product review
- originalIntent: Verify that Forelight's status menu offers `Exclude <current app>` / `Include <current app>`, stores exclusions by Bundle ID, removes all dimming while the frontmost app is excluded, and restores normal active-window cutout dimming when it is included again.
- desiredOutcome: With Discord frontmost and `com.hnc.Discord` excluded, the whole desktop remains normally bright. After the exclusion is removed and Forelight restarts, Discord remains bright as the active-window cutout while surrounding windows and the desktop are dimmed.

## User Outcome Review

The supplied current artifacts satisfy the requested outcome. `/tmp/forelight-exclusion-discord-foreground.png` shows Discord as the active macOS application and no dim veil anywhere, including the desktop and rear windows. `/tmp/forelight-exclusion-restored-window.png` shows Discord still bright while the desktop, calendar, rear window, and content outside the Discord frame are uniformly dimmed. The cutout follows the Discord window cleanly without an opaque fill, clipping, or an obvious halo.

The captures are native macOS display screenshots rather than repository mock assets: both are valid 2940x1912 RGBA PNGs and carry macOS screen-capture extended attributes (`kMDItemIsScreenCapture`, global rect, and display capture type). Their distinct SHA-256 hashes and differing live window composition rule out reuse of one static frame. Both captures postdate the reviewed source and bundled binary. The currently running bundle process started at `2026-09-21 01:04:32 +0900`, between the excluded capture (`01:04:09`) and restored capture (`01:04:51`), matching the reported delete-and-restart transition. This does not cryptographically prove the historical preference value in the first frame, but it is coherent runtime evidence rather than a fake screenshot.

The source and current binary support the same behavior. `AppDelegate.rebuildMenu()` selects `Include <name>` or `Exclude <name>` from `currentApplicationIsExcluded` and explicitly targets the exclusion toggle. `OverlayController` loads and stores a sorted string array under `excludedBundleIDs`, with membership keyed by `NSRunningApplication.bundleIdentifier`. Its excluded path calls `hideImmediately()` on every overlay; removing the exclusion calls `refresh()`, which updates and reorders each overlay with the active-window cutout. The built executable contains the menu labels, all intensity labels, and `excludedBundleIDs`. The current defaults domain has no `excludedBundleIDs` key and the running restored state visibly agrees.

## Blockers

None.

## Criterion Review

- `EXCL-01 dynamic menu wording`: PASS by source/binary trace — `Sources/Forelight/AppDelegate.swift:90-101,136-139`; current executable strings contain `Exclude ` and `Include `.
- `EXCL-02 persistence by Bundle ID`: PASS by source trace — `Sources/Forelight/OverlayController.swift:7,29,46-49,58-61,140-152` loads, tests, mutates, sorts, and writes Bundle ID strings through `UserDefaults`.
- `EXCL-03 excluded app hides all dimming`: PASS — `/tmp/forelight-exclusion-discord-foreground.png`; source early-exit at `Sources/Forelight/OverlayController.swift:161-167` calls `hideImmediately()` for every overlay, whose implementation sets alpha to zero and orders the window out at `:587-591`.
- `EXCL-04 included app restores dimming with active-window cutout`: PASS — `/tmp/forelight-exclusion-restored-window.png`; source updates and orders every overlay at `Sources/Forelight/OverlayController.swift:169-187`, and draws a real transparent even-odd cutout at `:598-625`.
- `EXCL-05 no visual/functional regression in supplied states`: PASS — excluded state is normally bright; restored state has a clean Discord cutout and uniform surrounding dimming; no black fill, stale overlay, clipped cutout, or unreadable foreground content is visible.

## Findings

- `[product] POSITIVE` — The excluded-state effect is global, not limited to Discord: all overlay windows are removed across `overlays`, matching the requested “hide all dimming” behavior.
- `[product] POSITIVE` — Inclusion restores the existing focus model instead of merely turning the whole screen dark: Discord remains bright and only surrounding content dims.
- `[product] POSITIVE` — Menu state is rebuilt immediately after the exclusion action and on application activation, so its label follows the current app and current exclusion state.
- `[evidence] NOTE` — Neither supplied screenshot has the Forelight menu open. Runtime typography, exact `Exclude Discord` / `Include Discord` rendering, and click feedback are therefore source/binary-evidenced rather than directly visible.
- `[evidence] NOTE` — The first frame's historical `excludedBundleIDs = ["com.hnc.Discord"]` value cannot be read after the key was deleted. The native capture metadata, process restart timing, source path, and two visibly correct settled states make the account credible but not independently replayable from retained artifacts.
- `[product] NOTE` — `README.md:38` still says app exclusions “come after” overlay verification, contradicting `README.md:10,36` and the implemented feature. This is stale documentation, not a functional or visual criterion failure.
- `[product] NOTE` — `OverlayController.swift` is 566 pure LOC, exceeding the programming guidance's 250-line maintainability ceiling. This is scope/maintenance debt, but it does not violate any stated exclusion-feature success criterion and is not a gate blocker under the review contract.

## Remove-AI-Slops and Programming Pass

- Directly reviewed the supplied production files and feature path. The exclusion implementation is small and uses native `NSMenuItem`, `NSRunningApplication.bundleIdentifier`, `UserDefaults`, and existing overlay lifecycle methods. No unnecessary parsing/normalization, speculative protocol/factory, pass-through wrapper, duplicated exclusion path, broad catch, or needless production extraction was introduced in this feature.
- No test files exist, so there are no excessive, deletion-only, requested-removal-only, tautological, prose-pinning, snapshot-only, or implementation-mirroring tests creating false confidence. Lack of automated exclusion coverage remains an evidence gap, not a stated-criterion failure.
- Prior gate reports explicitly include remove-ai-slops/overfit and programming perspectives, but they cover earlier source/captures. They were treated as untrusted historical evidence; this report independently repeated the current-feature pass.
- The oversized controller and stale README sentence are maintenance notes. Neither proves a failure of the user's requested menu, persistence, hide, or restore behavior.

## Checked Artifact Paths

- `/tmp/forelight-exclusion-discord-foreground.png` — SHA-256 `d014297f17d0ce5f386bec1a1b6ec8c3b91feb5d78daeabe24a9e45ff5983f83`
- `/tmp/forelight-exclusion-restored-window.png` — SHA-256 `404a7a5ca57ece75548c882f10c92fa0cf00eacb2d6a1be6c83f86a09f67ae2f`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/AppDelegate.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/OverlayController.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Sources/Forelight/main.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Resources/Info.plist`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/Package.swift`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/README.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.build/Forelight.app/Contents/MacOS/Forelight` — SHA-256 `9e983e3352d55e21ba2c8189a99958346bbee1f908bdcd162e057e0c14d4ffe2`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-final-qa-gate-review.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-final-level-gate-review.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-final-level-b-gate-review.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-mvp-gate-review.md`
- `/Users/hyunjoonkim/Documents/code/my_hazeover/.omo/evidence/forelight-mvp-pass-b-gate-review.md`

## Exact Evidence Gaps

- No open-menu capture directly shows `Exclude Discord` or `Include Discord` at runtime.
- No continuous interaction recording shows the exclusion click, immediate menu relabel, preference write, key deletion, restart, and inclusion transition end to end.
- The historical excluded preference value was intentionally deleted before the second capture and is therefore not recoverable from current `defaults` output.
- No automated tests, current-attempt standalone code-review report, manual QA matrix, or notepad path were supplied or found.
- The workspace is not a Git repository, so changed files and a branch diff cannot be reconstructed.
- The available tool surface exposed no independent subagent runner for an additional visual-oracle pass; direct gate review and the retained earlier independent visual reports were used instead.

These gaps lower confidence from HIGH to MEDIUM. None is evidence that a stated success criterion fails.
