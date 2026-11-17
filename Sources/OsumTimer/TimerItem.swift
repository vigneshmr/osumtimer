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
    /// The ⋯ choices of the last timer this slot held, kept while it holds
    /// none — cleared, or reset back to its words — so the next timer typed
    /// here picks up where that one left off. They belong to this item, never
    /// to new ones.
    var options: TimerItem.Options?

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

    /// Which way the clock reads: time left, falling to 0:00, or time gone,
    /// climbing to the full duration. The timer underneath is the same either
    /// way — it still ends at `endsAt` — and so is the ring.
    var direction: Direction = .down

    /// Whether the clock says what it is out of: "8:04 / 15:00", or
    /// "8:04 to 3pm". Per timer, like `display`, and independent of it.
    var showTotal: Bool = false

    /// Interval mode: the run cut into named segments, in order. nil is off.
    /// Each segment holds only where it starts, in elapsed seconds; it ends
    /// where the next one starts, and the last ends at the timer's own elapsed
    /// time — so pausing, stopping and finishing need no bookkeeping here.
    var intervals: [Interval]?

    /// Ended by hand, before the buzzer. Frozen like a pause, but over: the
    /// panel shows the intervals, and only reset or clear go on from here.
    var stopped: Bool = false

    /// Interval mode's chime: a tone every this many seconds into the segment
    /// running now. Starting the next segment starts the count again. nil is
    /// silent.
    var chimeEvery: TimeInterval?

    /// Everything set from the ⋯ menu: how the timer reads, and interval
    /// mode. Carried across reset and across a new duration in the same slot.
    struct Options: Codable, Equatable {
        var display: DisplayMode
        var direction: Direction
        var showTotal: Bool
        var intervals: Bool
        var chimeEvery: TimeInterval?
    }

    var options: Options {
        get { Options(display: display, direction: direction, showTotal: showTotal,
                      intervals: intervals != nil, chimeEvery: chimeEvery) }
        set {
            display = newValue.display
            direction = newValue.direction
            showTotal = newValue.showTotal
            intervals = newValue.intervals ? (intervals ?? [Interval(name: "", start: 0)]) : nil
            chimeEvery = newValue.intervals ? newValue.chimeEvery : nil
        }
    }

    struct Interval: Codable, Equatable {
        var name: String
        var start: TimeInterval
    }

    enum DisplayMode: String, Codable {
        case clock, percent
    }

    enum Direction: String, Codable, CaseIterable, Identifiable {
        case down, up

        var id: String { rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id, tag, duration, endsAt, pausedRemaining, createdAt, target, input, display, direction, showTotal
        case intervals, stopped, chimeEvery
    }

    /// `display`, `direction` and `showTotal` arrived after timers were already
    /// on disk; a file without them is a clock counting down, not an unreadable
    /// one.
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
        direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? .down
        showTotal = try c.decodeIfPresent(Bool.self, forKey: .showTotal) ?? false
        intervals = try c.decodeIfPresent([Interval].self, forKey: .intervals)
        stopped = try c.decodeIfPresent(Bool.self, forKey: .stopped) ?? false
        chimeEvery = try c.decodeIfPresent(TimeInterval.self, forKey: .chimeEvery)
    }

    init(
        duration: TimeInterval,
        tag: String? = nil,
        target: ClockTarget? = nil,
        input: String? = nil,
        display: DisplayMode = .clock,
        direction: Direction = .down,
        showTotal: Bool = false,
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
        self.display = display
        self.direction = direction
        self.showTotal = showTotal
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

    /// The seconds the clock shows, in this timer's direction. Counting up is
    /// taken off the whole-second remainder, so both directions roll over on
    /// the same tick and a timer just set reads 0:00, not 0:01.
    func clockValue(at now: Date = Date()) -> TimeInterval {
        let remaining = remaining(at: now)
        switch direction {
        case .down: return remaining
        case .up: return max(0, duration.rounded(.up) - remaining.rounded(.up))
        }
    }

    /// A clock reading with what it is out of: "8:04 / 15:00", or for a timer
    /// set to a time of day, "8:04 to 3pm" — the length it worked out to is
    /// not what was asked for. Without `showTotal`, just the clock.
    func clock(_ value: TimeInterval, showTotal: Bool? = nil) -> String {
        let showTotal = showTotal ?? self.showTotal
        let clock = Parser.clock(for: value)
        guard showTotal else { return clock }
        if let target { return "\(clock) to \(target.shortLabel())" }
        return "\(clock) / \(Parser.clock(for: duration))"
    }

    /// Whole seconds run so far, on the same tick as the clock.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        max(0, duration.rounded(.up) - remaining(at: now).rounded(.up))
    }

    /// Over, one way or the other: the buzzer went, or it was stopped.
    func isOver(at now: Date = Date()) -> Bool { stopped || hasFired(at: now) }

    /// How many chimes the running segment has earned by now — 0 until the
    /// first. nil when nothing should chime: no chime set, or not counting.
    func chimesDue(at now: Date = Date()) -> Int? {
        guard let every = chimeEvery, every > 0, let start = intervals?.last?.start,
              !isPaused, !isOver(at: now) else { return nil }
        return Int(((elapsed(at: now) - start) / every).rounded(.down))
    }

    /// Each segment with its length; the last one runs to now.
    func segments(at now: Date = Date()) -> [(name: String, length: TimeInterval)] {
        guard let intervals else { return [] }
        let end = elapsed(at: now)
        return intervals.enumerated().map { index, interval in
            let next = index + 1 < intervals.count ? intervals[index + 1].start : end
            return (interval.name, max(0, next - interval.start))
        }
    }

    /// The segments as a Markdown table, ready to paste. Unnamed ones are
    /// numbered, so the table never has a blank cell.
    func intervalsMarkdown(at now: Date = Date()) -> String {
        let segments = segments(at: now)
        var lines = ["## \(tag.map { "#\($0)" } ?? "Intervals")", "", "| # | Interval | Time |", "|---|---|---|"]
        for (index, segment) in segments.enumerated() {
            let name = segment.name.trimmingCharacters(in: .whitespaces)
            let cell = (name.isEmpty ? "Interval \(index + 1)" : name).replacingOccurrences(of: "|", with: "\\|")
            lines.append("| \(index + 1) | \(cell) | \(Parser.clock(for: segment.length)) |")
        }
        lines.append("| | **Total** | **\(Parser.clock(for: elapsed(at: now)))** |")
        return lines.joined(separator: "\n")
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
        stopped = false
        if intervals != nil { intervals = [Interval(name: "", start: 0)] }
    }
}
