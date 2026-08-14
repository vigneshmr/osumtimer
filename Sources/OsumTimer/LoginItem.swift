import Foundation
import ServiceManagement

/// Opening the app at login, via the modern `SMAppService` route — no helper
/// bundle, no login item plist, just the app registering itself.
///
/// Only works for a real `.app`: run from `swift run` there is no bundle for
/// launchd to register, so every call is a no-op rather than an error the user
/// would have no way to act on.
enum LoginItem {
    /// False under `swift run`, where there is no `.app` to register — the
    /// setting is not "off" there so much as not a thing that can be asked for.
    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Registration can fail — an unsigned build, or the user having flipped the
    /// app off in System Settings > General > Login Items, which sticks as
    /// `.requiresApproval`. Returns what the state actually is afterwards, so the
    /// toggle shows the truth rather than what we asked for.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                // Registering while already enabled throws, so ask first.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return isEnabled
        }
        return isEnabled
    }
}
