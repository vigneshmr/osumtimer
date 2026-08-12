import Foundation

/// Items survive a relaunch — both their order and their countdowns. Because
/// state is absolute end-dates, a restored timer is simply still correct; no
/// elapsed-time bookkeeping required.
struct Snapshot: Codable {
    var slots: [Slot] = []
    var recents: [TimeInterval] = []
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
