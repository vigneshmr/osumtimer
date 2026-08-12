import Foundation

/// One menu bar item, for its whole life.
///
/// A slot exists before it has a duration: you get an empty item, type into it,
/// and that same item becomes the countdown. `timer == nil` is the draft state.
/// Slots keep their creation order so an item never jumps around the menu bar.
struct Slot: Identifiable, Codable, Equatable {
    let id: UUID
    var timer: TimerItem?

    init(id: UUID = UUID(), timer: TimerItem? = nil) {
        self.id = id
        self.timer = timer
    }

    var isDraft: Bool { timer == nil }
}

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
        self.endsAt = Self.onSecond(now.addingTimeInterval(duration))
        self.pausedRemaining = nil
        self.createdAt = now
    }

    /// End dates are snapped to a whole second so every timer's display rolls
    /// over on the same boundary — two timers started 400ms apart would
    /// otherwise flip their digits 400ms apart.
    ///
    /// Down, not to nearest: the label rounds remaining time up, so an end date
    /// even slightly past `now + duration` renders a 25:00 timer as "25:01".
    /// The cost is firing up to a second early, which no one can perceive; a
    /// wrong number on screen at the moment you set the timer is obvious.
    private static func onSecond(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    var isPaused: Bool { pausedRemaining != nil }

    /// Held at its full duration: reset, or never started. Mechanically paused,
    /// but "paused" describes a timer stopped partway — this one has not run.
    var isReady: Bool { pausedRemaining == duration }

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
        endsAt = Self.onSecond(now.addingTimeInterval(pausedRemaining))
        self.pausedRemaining = nil
    }

    /// Back to the full duration and held there: reset puts the timer where it
    /// started, it does not start it. Pressing play is the separate decision.
    mutating func restart() {
        pausedRemaining = duration
        endsAt = nil
    }
}
