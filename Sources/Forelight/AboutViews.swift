import AppKit
import SwiftUI

struct AboutView: View {
    let version: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)

            Text("Forelight")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ForelightStyle.text)

            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(ForelightStyle.muted)

            Text("Keeps the frontmost window clear and fades everything else.")
                .font(.callout)
                .foregroundStyle(ForelightStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(ForelightLinks.support)
                } label: {
                    Label("Support Forelight", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Button("Settings…", action: onOpenSettings)
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Quit Forelight") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .frame(width: 380, height: 340)
        .background(ForelightStyle.windowBackground)
        .tint(ForelightStyle.accent)
    }
}

struct OnboardingView: View {
    @ObservedObject var model: ForelightModel
    let onShortcutChanged: (KeyCombo) -> Void
    let onShortcutRecordingChanged: (Bool) -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onFinish: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content

            Spacer(minLength: 0)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Text("\(step + 1) of 3")
                    .font(.caption)
                    .foregroundStyle(ForelightStyle.muted)
                Spacer()
                if step < 2 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started", action: onFinish)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 540, height: 460)
        .background(ForelightStyle.windowBackground)
        .tint(ForelightStyle.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(ForelightStyle.accent)
                Text("Welcome to Forelight")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(ForelightStyle.text)
                Text("Forelight dims everything on screen except the window you are working in, so your attention stays where it belongs.")
                    .foregroundStyle(ForelightStyle.text)
                Text("It lives in the menu bar. Click the icon for quick controls, or right-click it for more.")
                    .foregroundStyle(ForelightStyle.muted)
            }
        case 1:
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(ForelightStyle.accent)
                Text("Accessibility")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(ForelightStyle.text)
                Text("Forelight uses macOS Accessibility to track the focused window and to power the global shortcut. Nothing leaves your Mac.")
                    .foregroundStyle(ForelightStyle.text)
                HStack(spacing: 8) {
                    Image(systemName: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.accessibilityTrusted ? ForelightStyle.green : ForelightStyle.orange)
                    Text(model.accessibilityTrusted ? "Permission granted" : "Permission not granted yet")
                        .foregroundStyle(ForelightStyle.muted)
                }
                Button("Open System Settings", action: onOpenAccessibilitySettings)
                    .buttonStyle(.bordered)
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "keyboard")
                    .font(.system(size: 40))
                    .foregroundStyle(ForelightStyle.accent)
                Text("Global shortcut")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(ForelightStyle.text)
                Text("Pick the shortcut that toggles focus mode from anywhere. You can change it later in Settings.")
                    .foregroundStyle(ForelightStyle.text)

                ShortcutRecorder(
                    combo: model.shortcut,
                    onChange: { combo in onShortcutChanged(combo) },
                    onRecordingChanged: { recording in onShortcutRecordingChanged(recording) }
                )
                .frame(width: 160, height: 26)
            }
        }
    }
}
