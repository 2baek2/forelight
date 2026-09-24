# Forelight

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/s5010749300)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)

Forelight is a small macOS menu bar utility that keeps the frontmost window clear
while everything else fades into the background. Free and open source, with no
paid tiers.

- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [Automation](#automation)
- [Settings and data](#settings-and-data)
- [Development](#development)
- [Releasing](#releasing)
- [Permissions and troubleshooting](#permissions-and-troubleshooting)
- [Support](#support)
- [License](#license)

## Features

**Dimming**

- A clear cutout for the frontmost window on every connected display, or for
  every window of the frontmost app
- Continuous dim intensity (10–90%) with a slider and direct percentage input
- Hide while moving, with fade and restore timing controls
- Capture-safe: the dim layer never appears in screen recordings or shares
- Steps aside for Mission Control, App Exposé, Launchpad, and Show Desktop

**Per app and per display**

- Exceptions: keep chosen apps clear, managed as a toggle list
- Per-app intensity overrides, each with a toggle that falls back to the global value
- Per-display intensity overrides, plus a switch to skip dimming on a screen entirely

**Look**

- Custom dim tint with black / warm / cool presets
- Cutout corner radius and padding, an optional vignette, and cutout animation
- Cursor spotlight: light the area around the pointer instead of, or as well as,
  the focused window
- System, light, or dark appearance

**Automation**

- Focus Groups: save intensity, exceptions, per-app, per-display, and spotlight
  settings, then switch from the menu, a shortcut, the URL scheme, or the CLI
- Rules: when conditions match, turn dimming on or off, set intensity, apply a
  group, snooze, or set the spotlight
- Timed snooze and a recordable global shortcut
- `forelight://` URL scheme and a `forelight-cli` helper
- Update check against the GitHub releases, with an optional daily check

**Under the hood**

- Accessibility-based window tracking with a CoreGraphics fallback
- Adaptive refresh that backs off while idle, sleep/wake recovery, and a safe
  fallback if Accessibility is revoked
- Optional launch at login, onboarding, About, and JSON settings export/import/reset

## Requirements

- macOS 13 or later
- Building from source needs a Swift 6.2+ toolchain (a recent Xcode)

## Install

### Download

1. Get the DMG from the [latest release](https://github.com/2baek2/forelight/releases/latest).
2. Drag Forelight to Applications.
3. The build is not notarized, so clear the quarantine flag once:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Forelight.app
   ```

   Or right-click the app, choose **Open**, then **Open** again.
4. Grant Accessibility permission when Forelight asks.

### Build from source

```sh
git clone https://github.com/2baek2/forelight.git
cd forelight
./scripts/build-app.sh     # builds, signs, and launches .build/Forelight.app
```

`swift run Forelight` also works while developing.

## Usage

### Menu bar panel

Click the icon for the current state, the dim intensity slider, quick toggles,
and the current app. Right-click for the full menu: enable, snooze, appearance,
cursor spotlight, focus groups, settings, setup, support, and quit.

### Settings

| Section | What it holds |
|---|---|
| General | Enable, global shortcut, appearance, launch at login |
| Focus | Dim intensity, dim style, window movement, cursor spotlight |
| Exceptions | Apps kept clear, with a toggle each |
| Apps | Per-app intensity overrides |
| Displays | Per-display intensity and dimming on/off |
| Groups | Saved setups, with an optional shortcut each |
| Rules | Automatic actions when conditions match |
| Advanced | Accessibility, setup, About, updates, export/import/reset, support |

### Global shortcut

The default toggle is `⌥⌘F`. Change it under Settings → General: click the field
and press a new combination. While recording, Delete clears a group's shortcut
and Escape cancels.

## Automation

### URL scheme

| URL | Effect |
|---|---|
| `forelight://toggle` | Toggle dimming |
| `forelight://enable` / `forelight://disable` | Turn dimming on / off |
| `forelight://snooze?minutes=30` | Pause dimming |
| `forelight://resume` | Cancel a snooze |
| `forelight://intensity?value=0.5` | Set the global intensity |
| `forelight://appearance?mode=dark` | System, light, or dark |
| `forelight://spotlight?mode=cursor` | Window, cursor, or both |
| `forelight://group?name=Coding` | Apply a focus group |

Shortcuts can drive these with an Open URL action.

### CLI

```sh
forelight-cli toggle
forelight-cli snooze 30
forelight-cli intensity 0.6
forelight-cli appearance dark
forelight-cli spotlight cursor
forelight-cli group Coding
```

Run it with `swift run forelight-cli …` during development.

### Rules

A rule runs when every condition matches. Conditions: frontmost app, time window,
power source, external display, idle, microphone in use. Actions: enable, disable,
set intensity, apply a group, snooze, set spotlight. The last matching rule wins.

For example:

- Snooze for 30 minutes while the microphone is in use.
- Apply the "Coding" group when Xcode is in front.
- Lower the intensity on battery.

### Updates

Forelight checks the public GitHub releases. Use **Check for Updates…** in the
status menu or Settings → Advanced, or let it check once a day on launch. When a
newer version exists, choose **Install Update** and Forelight downloads it,
replaces itself, and relaunches. If the app lives somewhere it cannot write (or
you prefer a manual install), it falls back to downloading the DMG.

## Settings and data

- Everything is stored locally in `UserDefaults` for `com.forelight.app`. No
  account, no telemetry. Forelight installs nothing else and needs no admin rights.
- The only network request is the optional update check (Settings → Advanced,
  once a day on launch by default), which reads the public GitHub releases.
- Export and Import under Settings → Advanced write a JSON snapshot; Reset clears it.

## Development

```sh
swift build          # debug build
swift test           # 47 unit tests (Swift Testing)
./scripts/build-app.sh
```

Layout:

- `Sources/Forelight` — the app
- `Sources/ForelightCLI` — the `forelight-cli` helper
- `Tests/ForelightTests` — unit tests
- `Resources` — `Info.plist` and the app icon
- `scripts` — build, icon generation, and release scripts

## Releasing

```sh
./scripts/release.sh 0.2.0        # builds dist/Forelight-0.2.0.dmg and .zip
git tag -a v0.2.0 -m "Forelight 0.2.0"
git push origin main --tags       # GitHub Actions attaches the DMG and zip
```

### Keeping Accessibility permission across updates

macOS ties an Accessibility grant to the app's code signature. Forelight signs
every release with one stable certificate so the grant survives updates:

```
designated => identifier "com.forelight.app" and certificate leaf = H"…"
```

That requirement is identical for every build signed with the same certificate,
so a user who grants permission once is not asked again after an update. An
ad-hoc signature changes on every build, which is why it would ask again.

Create a dedicated certificate once:

1. **키체인 접근** → **인증서 지원** → **인증서 생성…**
   (Keychain Access → Certificate Assistant → Create a Certificate…)
2. Name it `Forelight`, choose **코드 서명** (Code Signing), and create a
   self-signed certificate.
3. On the **인증서 정보** (Certificate Information) screen set **유효 기간(일)**
   (Validity Period) to a long value such as `3650` days.
4. Export it as a `.p12` and keep a backup; it is the signing identity for every
   release.

Then sign releases with it:

```sh
FORELIGHT_SIGNING_IDENTITY="Forelight" ./scripts/release.sh 0.2.0
```

`release.sh` prefers `FORELIGHT_SIGNING_IDENTITY`, then `Local Self-Signed`, then
ad-hoc, and adds a **secure timestamp** so the signature stays valid even after
the certificate expires.

For GitHub Actions, base64 the `.p12` and add these repository secrets:
`MACOS_SIGNING_P12`, `MACOS_SIGNING_P12_PASSWORD`, `MACOS_KEYCHAIN_PASSWORD`, and
`MACOS_SIGNING_IDENTITY`. Without them the workflow signs ad-hoc.

Note: changing the certificate (or shipping an ad-hoc build) changes the
signature, and users will be asked to grant Accessibility again.

## Permissions and troubleshooting

**Accessibility.** Forelight uses macOS Accessibility to track the focused window
and to power the global shortcut. Without it, Forelight falls back to CoreGraphics
polling, which is slightly less precise. Everything stays on your Mac.

**"Forelight is damaged" or a Gatekeeper warning.** The build is not notarized, so
clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Forelight.app
```

**Accessibility stops working after a rebuild.** macOS ties the grant to the
bundle ID and code signature. Keep the same signing identity
(`./scripts/build-app.sh` and `./scripts/release.sh` do this when a certificate is
available) or re-grant in System Settings → Privacy & Security → Accessibility.

**An update asks for Accessibility again.** This happens when releases are signed
ad-hoc, because the signature changes on every build. Sign with a stable
certificate (see [Releasing](#releasing)) to keep the grant across updates.

## Contributing

Bug reports and pull requests are welcome. Please open an issue first for larger
changes.

## Support

Forelight is free, with no paid tiers or feature locks. If it is useful to you,
you can [buy me a coffee](https://buymeacoffee.com/s5010749300).

## License

MIT — see [LICENSE](LICENSE).
