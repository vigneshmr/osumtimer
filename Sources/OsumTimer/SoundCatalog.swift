import AppKit
import Observation

/// The sounds available as an alarm tone.
///
/// macOS keeps these as loose files in two system-wide directories, and
/// `NSSound(named:)` resolves a bare name across both of them — so nothing has
/// to be bundled. `~/Library/Sounds` is deliberately not scanned: under the App
/// Sandbox `NSHomeDirectory()` points into the app's container, so the lookup
/// would find nothing anyway.
enum SoundCatalog {
    /// Short, bright, and not a notification chime. Lives here rather than on
    /// `Preferences` so the alarm path can reach it without hopping to the main
    /// actor.
    static let fallback = "Pop"

    private static let directories = [
        "/Library/Sounds",         // installed for everyone
        "/System/Library/Sounds",  // the fourteen that ship with macOS
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

}

/// The sound being auditioned in Settings, if any.
///
/// A preview is one sound at a time and always interruptible: whatever starts a
/// new one stops the old one, and the window closing stops it outright — a sound
/// you cannot see the source of is a sound you cannot turn off.
@MainActor
@Observable
final class SoundPreview {
    static let shared = SoundPreview()

    /// The name currently sounding. Drives the button's play/stop face, so it is
    /// cleared when the sound ends on its own as well as when it is stopped.
    private(set) var playing: String?

    private var sound: NSSound?
    private var end: DispatchWorkItem?

    private init() {}

    /// What the button does: press it while a sound is playing and it stops.
    func toggle(_ name: String) {
        if playing == name { stop() } else { play(name) }
    }

    func play(_ name: String) {
        stop()
        guard let sound = NSSound(named: name) else { return }
        self.sound = sound
        playing = name
        sound.play()

        // NSSound reports when it finishes only through a delegate, which means
        // an NSObject; its own duration says the same thing without one. Being a
        // frame out only means the button's face changes a frame late.
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        end = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, sound.duration), execute: work)
    }

    func stop() {
        end?.cancel()
        end = nil
        sound?.stop()
        sound = nil
        playing = nil
    }
}
