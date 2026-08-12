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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Off by default: menu bar width is scarce, and macOS hides items that
        // do not fit — a label is worth its width only if you ask for it.
        self.showLabelsInMenuBar = defaults.bool(forKey: Key.showLabels)
        // Unset, or set to something no longer recognised, means follow along.
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }
}
