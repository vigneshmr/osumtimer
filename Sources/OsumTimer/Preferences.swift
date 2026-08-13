import AppKit
import Foundation
import Observation

/// Which appearance the app's own surfaces use, independent of the system.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "inherit", which is what following the system amounts to.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// How long the alarm keeps sounding when a timer ends.
///
/// The system sounds are chimes — a second or two each — so anything longer than
/// "once" is that sound on a loop, which is what makes it an alarm you can hear
/// from another room rather than a notification you can sleep through.
enum AlarmRing: Int, CaseIterable, Identifiable {
    case once = 0
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .once: "Once"
        case .tenSeconds: "10 sec"
        case .thirtySeconds: "30 sec"
        case .oneMinute: "1 min"
        }
    }
}

/// App-wide settings. One instance, because the settings window is one window
/// however many timers open it.
///
/// Backed by `UserDefaults` rather than the timer snapshot: a preference is not
/// part of any timer, and outlives every one of them.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let showLabels = "showLabelsInMenuBar"
        static let appearance = "appearance"
        static let alarmSound = "alarmSound"
        static let alarmRing = "alarmRing"
    }

    /// Draws a tagged timer's label beside its countdown, as `Therapy 2:12`.
    var showLabelsInMenuBar: Bool {
        didSet { defaults.set(showLabelsInMenuBar, forKey: Key.showLabels) }
    }

    /// Light, dark, or whatever the system is doing. Applies to the panels and
    /// the settings window; the menu bar items are drawn by the system and keep
    /// following it, as every other status item does.
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// Sound played when any timer fires — one setting for every timer, so a
    /// sound you recognise means "a timer finished" whichever one it was.
    var alarmSound: String {
        didSet { defaults.set(alarmSound, forKey: Key.alarmSound) }
    }

    /// How long that sound keeps going. Long enough to be missed-able is the
    /// whole failure mode of a timer, so the default rings rather than chimes.
    var alarmRing: AlarmRing {
        didSet { defaults.set(alarmRing.rawValue, forKey: Key.alarmRing) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Off by default: menu bar width is scarce, and macOS hides items that
        // do not fit — a label is worth its width only if you ask for it.
        self.showLabelsInMenuBar = defaults.bool(forKey: Key.showLabels)
        // Unset, or set to something no longer recognised, means follow along.
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        // A sound that has since been deleted would fail silently at the moment
        // it mattered, so fall back to one that ships with the system.
        let saved = defaults.string(forKey: Key.alarmSound)
        self.alarmSound = saved.flatMap { NSSound(named: $0) != nil ? $0 : nil }
            ?? SoundCatalog.fallback
        // `object(forKey:)` rather than `integer(forKey:)`: unset reads as 0,
        // which is a real choice here ("Once") and not what a first run wants.
        self.alarmRing = (defaults.object(forKey: Key.alarmRing) as? Int)
            .flatMap(AlarmRing.init(rawValue:)) ?? .thirtySeconds
    }
}
