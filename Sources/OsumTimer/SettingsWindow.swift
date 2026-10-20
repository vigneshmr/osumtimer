import AppKit
import SwiftUI

/// The one settings window, owned here rather than by a SwiftUI `Settings`
/// scene: SwiftUI opens an app's only scene on launch, so a menu-bar app whose
/// only scene is `Settings` greets every launch with an unasked-for window.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        let window = self.window ?? make()
        self.window = window
        // Accessory apps are not frontmost by default; without this the window
        // appears behind whatever you were using.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func make() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "OsumTimer Settings"
        window.styleMask = [.titled, .closable]
        // Kept after closing, so reopening lands where you left it and the view's
        // state survives; `onDisappear` still fires on close.
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("OsumTimerSettings")
        window.appearance = Preferences.shared.appearance.appearance
        return window
    }

    /// Set on the window rather than through `preferredColorScheme`: SwiftUI
    /// never undoes a scheme once set, so going back to System after Dark left
    /// the window dark. A nil `NSAppearance` really does follow the system.
    static func apply(_ mode: AppearanceMode) {
        window?.appearance = mode.appearance
    }
}

struct SettingsView: View {
    @Bindable private var preferences = Preferences.shared

    /// Read once: the sound folders do not change while the window is open, and
    /// re-scanning the disk on every redraw would be wasteful.
    @State private var bundledSounds = SoundCatalog.bundledNames()
    @State private var systemSounds = SoundCatalog.systemNames()

    private var preview = SoundPreview.shared

    /// The guide takes over the window rather than opening one of its own, and
    /// at the form's height, so going in and back out never resizes it.
    @State private var showingGuide = false
    @State private var formHeight: CGFloat = 0
    private var sounding: Bool { preview.playing == preferences.alarmSound }

    /// Reads the bundle, so it can only disagree with the installer if the
    /// plist does. A bundle-less `swift run` has no version at all.
    private var version: String {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "OsumTimer — development build"
        }
        return "OsumTimer \(short)"
    }

    /// White capitals on a dark grey pill: a header has to read as a different
    /// kind of thing from the rows under it — at row size it read as one more
    /// row, and as bare grey capitals it was hard to read at all.
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            // A shade lighter in dark mode, where the same grey would sink into the window.
            .background(Color(light: .init(white: 0.32, alpha: 1), dark: .init(white: 0.40, alpha: 1)), in: Capsule())
    }

    var body: some View {
        Group {
            if showingGuide {
                GuideView { showingGuide = false }
                    .frame(width: 460, height: formHeight)
            } else {
                form
            }
        }
        // The window restyles while you are looking at it, not on next open.
        .onChange(of: preferences.appearance) { _, mode in SettingsWindow.apply(mode) }
        .onDisappear {
            // A preview outliving the window would be a sound with nothing on screen
            // to stop it — the app has no other visible surface to turn it off from.
            preview.stop()
            // Opened from a panel's gear, the window is asked for settings.
            showingGuide = false
        }
    }

    private var form: some View {
        // Grouped by what a setting is about, not the order it was added in:
        // how a timer reads, how it ends, then the app around it.
        Form {
            Section {
                Toggle(isOn: $preferences.showProgressBar) {
                    Text("Show progress bar")
                    Text("Reads as “34% (15:11)” with a bar.")
                }
                Toggle(isOn: $preferences.showTotal) {
                    Text("Show total")
                    Text("Reads as “8:04 / 15:00”, or “8:04 to 3pm”.")
                }
                Picker(selection: $preferences.direction) {
                    Text("Down").tag(TimerItem.Direction.down)
                    Text("Up").tag(TimerItem.Direction.up)
                } label: {
                    Text("Count")
                    Text("To 0:00, or up to the length.")
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle(isOn: $preferences.rememberLastChoice) {
                    Text("Remember last choice")
                    Text("Flipping %, Σ or the arrow on any timer updates these, for new timers and any you reset.")
                }
            } header: {
                sectionHeader("New timers")
            }

            Section {
                LabeledContent("Sound") {
                    HStack(spacing: 6) {
                        Picker("Sound", selection: $preferences.alarmSound) {
                            // Under `swift run` there is no bundle, so no first section
                            // and no header for a list with nothing to tell apart.
                            if bundledSounds.isEmpty {
                                ForEach(systemSounds, id: \.self) { Text($0).tag($0) }
                            } else {
                                Section("Calm") {
                                    ForEach(bundledSounds, id: \.self) { Text($0).tag($0) }
                                }
                                Section("System") {
                                    ForEach(systemSounds, id: \.self) { Text($0).tag($0) }
                                }
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        // Selecting plays it, so the choice is made by ear rather than by
                        // guessing what "Sosumi" sounds like.
                        .onChange(of: preferences.alarmSound) { _, name in preview.play(name) }

                        // Stops as readily as it starts: the same button, showing what
                        // pressing it now would do.
                        Button {
                            preview.toggle(preferences.alarmSound)
                        } label: {
                            Image(systemName: sounding ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.borderless)
                        .help(sounding ? "Stop" : "Play")
                        .accessibilityLabel(sounding ? "Stop alarm sound" : "Play alarm sound")
                    }
                }
                Picker(selection: $preferences.alarmRing) {
                    ForEach(AlarmRing.allCases) { ring in
                        Text(ring.label).tag(ring)
                    }
                } label: {
                    Text("Ring for")
                    Text("Past “Once”, the sound loops until time is up or you touch the timer.")
                }
            } header: {
                sectionHeader("Alarm")
            }

            Section {
                LabeledContent {
                    Button("Open") { showingGuide = true }
                } label: {
                    Text("Guide")
                    Text("Starting, pausing, resetting, % and Σ, in pictures.")
                }
                Toggle(isOn: $preferences.showLabelsInMenuBar) {
                    Text("Show label in menu bar")
                    Text("A tagged timer reads as “Therapy 2:12”.")
                }
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                // Unavailable under `swift run`: no bundle, nothing to register.
                Toggle("Open at login", isOn: $preferences.launchAtLogin)
                    .disabled(!LoginItem.isSupported)
                    .help(LoginItem.isSupported
                        ? "Opens OsumTimer when you log in."
                        : "Only available in the packaged app.")
            } header: {
                sectionHeader("General")
            } footer: {
                Text(version)
                    .font(Design.caption)
                    .foregroundStyle(Design.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        // Everything fits; a scroller here would only ever wobble.
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { formHeight = $0 }
    }
}
