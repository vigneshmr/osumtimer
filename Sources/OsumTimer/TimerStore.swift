import Foundation
import Observation

/// Single source of truth for every countdown, plus the one tick that drives the UI.
///
/// One shared 1s tick recomputes all rows. Firing does not ride on that tick —
/// each timer gets its own precise wake-up so alerts are never up to a second late.
@Observable
@MainActor
final class TimerStore {
    private(set) var timers: [TimerItem] = []
    private(set) var recents: [TimeInterval] = []

    /// Bumped once per second so views recompute; the actual clock is `Date()`.
    private(set) var tick: Date = Date()

    private var displayTimer: Foundation.Timer?
    private var fireTimers: [UUID: DispatchSourceTimer] = [:]
    private let notifier: Notifier
    private let store: Persistence

    init(notifier: Notifier = Notifier(), store: Persistence = Persistence()) {
        self.notifier = notifier
        self.store = store

        let snapshot = store.load()
        // Anything that expired while we were closed is stale — don't alarm on launch.
        self.timers = snapshot.timers.filter { !$0.hasFired() }
        self.recents = snapshot.recents

        startDisplayTick()
        for timer in timers { scheduleFire(timer) }
    }

    /// Sorted for display: soonest to fire first, paused timers last.
    var sorted: [TimerItem] {
        timers.sorted { lhs, rhs in
            if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
            return lhs.remaining(at: tick) < rhs.remaining(at: tick)
        }
    }

    /// The timer the menu bar shows.
    var leading: TimerItem? { sorted.first { !$0.isPaused } ?? sorted.first }

    // MARK: - Commands

    @discardableResult
    func add(_ parsed: ParsedTimer) -> TimerItem {
        let timer = TimerItem(duration: parsed.duration, tag: parsed.tag)
        timers.append(timer)
        rememberRecent(parsed.duration)
        scheduleFire(timer)
        persist()
        return timer
    }

    func remove(_ id: UUID) {
        cancelFire(id)
        timers.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        for timer in timers { cancelFire(timer.id) }
        timers.removeAll()
        persist()
    }

    func togglePause(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        if timers[index].isPaused {
            timers[index].resume()
            scheduleFire(timers[index])
        } else {
            timers[index].pause()
            cancelFire(id)
        }
        persist()
    }

    func restart(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].restart()
        scheduleFire(timers[index])
        persist()
    }

    // MARK: - Ticking

    private func startDisplayTick() {
        let timer = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
        // .common keeps the countdown moving while a menu or resize is tracking.
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func scheduleFire(_ timer: TimerItem) {
        cancelFire(timer.id)
        guard let endsAt = timer.endsAt else { return }
        let delay = max(0, endsAt.timeIntervalSinceNow)

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + delay, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.fire(timer.id) }
        }
        source.resume()
        fireTimers[timer.id] = source
    }

    private func cancelFire(_ id: UUID) {
        fireTimers.removeValue(forKey: id)?.cancel()
    }

    private func fire(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        cancelFire(id)
        notifier.fire(tag: timer.tag, duration: timer.duration)
        // The row stays, reading 0:00, until dismissed — a timer that vanishes
        // the instant it fires leaves you unsure whether it ever ran.
        tick = Date()
    }

    private func rememberRecent(_ duration: TimeInterval) {
        recents.removeAll { $0 == duration }
        recents.insert(duration, at: 0)
        recents = Array(recents.prefix(4))
    }

    private func persist() {
        store.save(.init(timers: timers, recents: recents))
    }
}
