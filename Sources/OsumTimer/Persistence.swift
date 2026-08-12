import Foundation

/// Items survive a relaunch — both their order and their countdowns. Because
/// state is absolute end-dates, a restored timer is simply still correct; no
/// elapsed-time bookkeeping required.
struct Snapshot: Codable {
    var slots: [Slot] = []
    /// What was typed, not what it worked out to — see `ParsedTimer.expression`.
    var recents: [String] = []

    init(slots: [Slot] = [], recents: [String] = []) {
        self.slots = slots
        self.recents = recents
    }

    /// Recents used to be durations in seconds. Decoding leniently keeps an
    /// existing file readable: a snapshot that fails to decode takes the saved
    /// timers down with it, which is far worse than losing a few shortcuts.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slots = try container.decodeIfPresent([Slot].self, forKey: .slots) ?? []

        if let expressions = try? container.decode([String].self, forKey: .recents) {
            recents = expressions
        } else if let seconds = try? container.decode([TimeInterval].self, forKey: .recents) {
            recents = seconds.map { Parser.clock(for: $0) }
        } else {
            recents = []
        }
    }
}

struct Persistence {
    private let url: URL

    init(filename: String = "timers.json") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OsumTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base.appendingPathComponent(filename)
    }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Snapshot() }
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
