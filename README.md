# Forelight

Forelight is a small macOS menu bar utility that keeps the frontmost window clear and fades everything else.

## MVP

- Active-window cutout on every connected display
- Menu bar panel with enabled state, current app, settings, and quit actions
- Continuous dim-intensity slider with direct percentage input
- Recordable global toggle shortcut (default `⌥⌘F`)
- Optional hide-while-moving behavior with fade and restore timing controls
- Per-app exceptions, persisted by Bundle ID, managed as a toggle list
- Per-app dim intensity overrides (set from the panel or Settings → Apps), each with a toggle that keeps the entry but falls back to the global value
- Per-display dim intensity overrides in Settings → Displays, where each screen also has a switch to skip dimming entirely (a display override wins over an app override)
- Focus Groups: save the current intensity, exceptions, and per-app intensities and switch between them from Settings, the status menu, or `forelight-cli group <name>`
- Timed snooze and a capture-safe overlay that stays out of screen recordings
- `forelight://` URL scheme (toggle, snooze, intensity, appearance, group) and a `forelight-cli` helper
- Dark, light, or system appearance
- Optional launch at login
- Steps aside while Mission Control, App Exposé, Launchpad, or Show Desktop is open
- Automatic refresh after app activation, mouse clicks, display changes, and window changes
- Accessibility-based movement and resize tracking, with CoreGraphics polling as a fallback

## Run

```sh
swift run Forelight
```

To build and launch the app with a stable signing identity, use:

```sh
./scripts/build-app.sh
```

Drive Forelight from scripts, Shortcuts, or the terminal:

```sh
swift run forelight-cli toggle
swift run forelight-cli snooze 30
swift run forelight-cli group Coding
open "forelight://toggle"
```

The URL scheme supports `toggle`, `enable`, `disable`, `snooze?minutes=`, `resume`, `intensity?value=`, `appearance?mode=`, and `group?name=`.

macOS Accessibility permission is associated with the app's Bundle ID and code-signing identity, not just the app name. The build script keeps the Bundle ID as `com.forelight.app` and signs with the installed `Local Self-Signed` identity by default, so replacing the app on this Mac keeps the same identity. If you use an Apple Developer signing identity, pass it explicitly:

```sh
FORELIGHT_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

The local identity is machine-specific. For distributing Forelight to other Macs, use the same Apple Developer ID signing identity for every release. Changing the Bundle ID or signing identity, resetting Accessibility permissions, or moving to another Mac can require granting permission again.

Forelight requests macOS Accessibility permission on first launch. This lets it detect real window movement and resizing, hide the dim layer while the window is moving, and restore the cutout when the window settles. If permission is not granted, the app keeps using its fallback window polling.

Click the menu bar icon to open the compact control panel. It shows the current state, provides the continuous intensity slider, and lets you exclude the focused app. Exclusions are stored by Bundle ID and can be reversed with `Include <App>`.

Open `Settings…` for the sidebar settings window. It contains focus behavior, window-movement animation timing, app exceptions, and Accessibility permission status. Under `General`, click the shortcut field and press a new key combination to change the global toggle shortcut; the default is `⌥⌘F`. Under `Exceptions`, the excluded apps are listed with a toggle each; use `+` to add apps and `−` to remove the selected one. Toggling an app off keeps it in the list without excluding it. Under `Advanced`, revisit setup, open the About window, and export, import, or reset your settings.

The app uses public AppKit, Application Services, NSWorkspace, and CoreGraphics APIs. Focus Groups are stored locally; deeper automation rules are the next step.
