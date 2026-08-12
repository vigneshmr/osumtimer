import Foundation

/// One countdown.
///
/// State is an absolute `endsAt` date rather than a decrementing counter, so the
/// timer stays correct across sleep, wake, clock changes and app relaunch.
/// A paused timer drops `endsAt` and holds the frozen remainder instead.
struct TimerItem: Identifiable, Codable, Equatable {
    let id: UUID
    var tag: String?
    var duration: TimeInterval
    var endsAt: Date?
    var pausedRemaining: TimeInterval?
    var createdAt: Date

    init(duration: TimeInterval, tag: String? = nil, now: Date = Date()) {
        self.id = UUID()
        self.tag = tag
        self.duration = duration
        self.endsAt = now.addingTimeInterval(duration)
        self.pausedRemaining = nil
        self.createdAt = now
    }

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    func hasFired(at now: Date = Date()) -> Bool {
        !isPaused && remaining(at: now) <= 0
    }

    /// 0 at the start, 1 at the buzzer. Drives the ring.
    func progress(at now: Date = Date()) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    mutating func pause(at now: Date = Date()) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    mutating func resume(at now: Date = Date()) {
        guard let pausedRemaining else { return }
        endsAt = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    mutating func restart(at now: Date = Date()) {
        pausedRemaining = nil
        endsAt = now.addingTimeInterval(duration)
    }
}
