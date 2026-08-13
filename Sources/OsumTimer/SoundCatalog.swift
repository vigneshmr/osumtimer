import AppKit

/// The sounds available as an alarm tone.
///
/// macOS keeps these as loose files in three well-known directories, and
/// `NSSound(named:)` resolves a bare name across all of them — so nothing has to
/// be bundled, and anything dropped into `~/Library/Sounds` shows up on its own.
enum SoundCatalog {
    /// Short, bright, and not a notification chime — what the app used before
    /// the sound was selectable. Lives here rather than on `Preferences` so the
    /// alarm path can reach it without hopping to the main actor.
    static let fallback = "Glass"

    private static let directories = [
        "\(NSHomeDirectory())/Library/Sounds",  // yours, and first in line
        "/Library/Sounds",                      // installed for everyone
        "/System/Library/Sounds",               // the fourteen that ship with macOS
    ]

    private static let playable: Set<String> = ["aiff", "aif", "wav", "m4a", "caf", "mp3"]

    /// Sound names, alphabetical, without duplicates or file extensions.
    static func names() -> [String] {
        var seen = Set<String>()
        var found: [String] = []

        for directory in directories {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for file in contents {
                let url = URL(fileURLWithPath: file)
                guard playable.contains(url.pathExtension.lowercased()) else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                // A name that AppKit cannot resolve would be a dead entry in the
                // list, so only offer what will actually play.
                guard !seen.contains(name), NSSound(named: name) != nil else { continue }
                seen.insert(name)
                found.append(name)
            }
        }

        return found.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Plays a sound once, for previewing a choice. Stops whatever it was
    /// playing first, so clicking down a list does not stack sounds on top of
    /// each other.
    @MainActor
    static func preview(_ name: String) {
        current?.stop()
        let sound = NSSound(named: name)
        current = sound
        sound?.play()
    }

    @MainActor private static var current: NSSound?
}
