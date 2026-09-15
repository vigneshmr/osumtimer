import Foundation

/// One menu bar item, for its whole life.
///
/// A slot exists before it has a duration: you get an empty item, type into it,
/// and that same item becomes the countdown. `timer == nil` is the draft state.
/// Slots keep their creation order so an item never jumps around the menu bar.
struct Slot: Identifiable, Codable, Equatable {
    let id: UUID
    var timer: TimerItem?
    /// Text sitting in this slot's editor. Held here rather than in the view
    /// because the popover rebuilds its content every time it opens — anything
    /// kept in view state is lost the moment you click away.
    var draft: String = ""

    init(id: UUID = UUID(), timer: TimerItem? = nil, draft: String = "") {
        self.id = id
        self.timer = timer
        self.draft = draft
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
    /// Set when this timer was given a time of day rather than a length. Reset
    /// resolves it again: "@5pm" means five o'clock every time, while the length
    /// it worked out to when you set it goes stale the moment the clock moves.
    var target: ClockTarget?
    /// The words this timer was created from, kept so reset can hand them back
    /// to the editor.
    var input: String?
    /// How the countdown reads, in the bar and in the panel. Per timer, not an
    /// app setting: a 2h block wants "34%" — how much is left, at a glance —
    /// while a 3 minute egg wants the seconds.
    var display: DisplayMode = .clock

    enum DisplayMode: String, Codable {
        case clock, percent
    }

    private enum CodingKeys: String, CodingKey {
        case id, tag, duration, endsAt, pausedRemaining, createdAt, target, input, display
    }

    /// `display` arrived after timers were already on disk; a file without it
    /// is a clock timer, not an unreadable one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
        pausedRemaining = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        target = try c.decodeIfPresent(ClockTarget.self, forKey: .target)
        input = try c.decodeIfPresent(String.self, forKey: .input)
        display = try c.decodeIfPresent(DisplayMode.self, forKey: .display) ?? .clock
    }

    init(
        duration: TimeInterval,
        tag: String? = nil,
        target: ClockTarget? = nil,
        input: String? = nil,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.tag = tag
        self.duration = duration
        self.endsAt = Self.onSecond(now.addingTimeInterval(duration))
        self.pausedRemaining = nil
        self.createdAt = now
        self.target = target
        self.input = input
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

    /// How far along, as a whole percentage climbing from 0 to 100. Rounded
    /// down: a timer with any time on it never reads 100%, and one just started
    /// reads 0%, not 1%.
    func percentElapsed(at now: Date = Date()) -> Int {
        Int((progress(at: now) * 100).rounded(.down))
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
    ///
    /// A timer set to a time of day resets to that time as it stands now, not to
    /// the length it once was — resetting a "@5pm" timer at 4:30 gives half an
    /// hour, not the two hours it ran for when you set it at three.
    mutating func restart(at now: Date = Date()) {
        if let target, let interval = target.interval(from: now) {
            duration = interval
        }
        pausedRemaining = duration
        endsAt = nil
    }
}
