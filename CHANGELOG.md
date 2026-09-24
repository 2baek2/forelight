# Changelog

## Unreleased

- Check for updates from the GitHub releases, from Settings → Advanced or the
  status menu, with an optional daily check on launch. A newer version installs
  in place (download, replace, relaunch) and falls back to a DMG download when
  the app cannot be replaced.
- Add a support link in About, Settings → Advanced, and the status menu.
- Sign releases with a stable certificate when one is available (instead of
  ad-hoc) and add a secure timestamp, so updates keep the Accessibility grant
  even after the certificate expires. `scripts/make-signing-cert.sh` creates a
  `Forelight` certificate (or reuses one), trusts it, and exports a `.p12` for
  CI; `release.sh` prefers it automatically.

## 0.1.0

First release.

- Active-window cutout on every connected display, with the option to keep every
  window of the frontmost app clear
- Continuous dim intensity, plus per-app and per-display overrides that each keep
  a toggle and fall back to the global value
- Per-app exceptions managed as a toggle list
- Cursor spotlight (window, cursor, or both) with adjustable radius and soft edge
- Dim style: custom tint color with black/warm/cool presets, cutout corner radius
  and padding, vignette, and cutout animation
- Hide while moving, with fade and restore timing controls
- Recordable global toggle shortcut, plus a shortcut per focus group
- Focus Groups that capture intensity, exceptions, per-app, per-display, and
  spotlight settings
- Automation rules (frontmost app, time window, power source, external display,
  idle, microphone in use) that turn dimming on or off, set intensity, apply a
  group, snooze, or set the spotlight
- Timed snooze and a capture-safe overlay that stays out of screen recordings
- Steps aside for Mission Control, App Exposé, Launchpad, and Show Desktop
- System, light, or dark appearance; optional launch at login
- Menu bar panel, sidebar settings, onboarding, About, and JSON settings
  export/import/reset
- `forelight://` URL scheme and a `forelight-cli` helper
- Adaptive refresh, display sleep/wake handling, and an Accessibility-revocation
  fallback
