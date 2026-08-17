import AppKit
import SwiftUI

/// The one settings window, opened from any timer's gear.
///
/// A menu bar only app has no Window menu to reopen a closed window from, so the
/// window is rebuilt on demand and simply raised if it is already up.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show() {
        if window == nil { window = make() }
        applyAppearance()
        // Accessory apps are not frontmost by default; without this the window
        // appears behind whatever you were using.
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Called again whenever the preference changes, so the window restyles
    /// while you are looking at it rather than on next open.
    func applyAppearance() {
        window?.appearance = Preferences.shared.appearance.appearance
    }

    private func make() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false  // reopened later, not rebuilt

        // A preview outliving the window would be a sound with nothing on screen
        // to stop it — the app has no other visible surface to turn it off from.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SoundPreview.shared.stop() }
        }
        return window
    }
}

private struct SettingsView: View {
    @Bindable private var preferences = Preferences.shared

    /// Read once: the sound folders do not change while the window is open, and
    /// re-scanning the disk on every redraw would be wasteful.
    @State private var sounds = SoundCatalog.names()

    private var preview = SoundPreview.shared
    private var sounding: Bool { preview.playing == preferences.alarmSound }

    /// Reads the bundle, so it can only disagree with the installer if the
    /// plist does. A bundle-less `swift run` has no version at all.
    private var version: String {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "OsumTimer — development build"
        }
        return "OsumTimer \(short)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show label in menu bar", isOn: $preferences.showLabelsInMenuBar)

                Text("A tagged timer shows its tag beside the countdown, as “Therapy 2:12”.")
                    .font(Design.caption)
                    .foregroundStyle(Design.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Unavailable under `swift run`: no bundle, nothing to register.
            Toggle("Open at login", isOn: $preferences.launchAtLogin)
                .disabled(!LoginItem.isSupported)
                .help(LoginItem.isSupported
                    ? "Opens OsumTimer when you log in."
                    : "Only available in the packaged app.")

            HStack(spacing: 8) {
                Picker("Alarm sound", selection: $preferences.alarmSound) {
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                // Selecting plays it, so the choice is made by ear rather than by
                // guessing what "Sosumi" sounds like.
                .onChange(of: preferences.alarmSound) { _, name in preview.play(name) }

                // Stops as readily as it starts: the same button, showing what
                // pressing it now would do.
                Button {
                    preview.toggle(preferences.alarmSound)
                } label: {
                    Image(systemName: sounding ? "stop.circle" : "play.circle")
                }
                .buttonStyle(.borderless)
                .help(sounding ? "Stop" : "Play")
                .accessibilityLabel(sounding ? "Stop alarm sound" : "Play alarm sound")
            }

            VStack(alignment: .leading, spacing: 6) {
                Picker("Ring for", selection: $preferences.alarmRing) {
                    ForEach(AlarmRing.allCases) { ring in
                        Text(ring.label).tag(ring)
                    }
                }

                Text("Anything past “Once” loops the sound until the time is up, or until you touch the timer.")
                    .font(Design.caption)
                    .foregroundStyle(Design.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: preferences.appearance) { SettingsWindow.shared.applyAppearance() }

            Text(version)
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }
}
