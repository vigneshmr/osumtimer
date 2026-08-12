import Foundation
import Observation

/// Single source of truth. One slot in, one menu bar item out — always.
///
/// One shared 1s tick recomputes every label. Firing does not ride that tick:
/// each live timer gets its own precise wake-up, so alerts are never late.
@Observable
@MainActor
final class TimerStore {
    /// Creation order, never re-sorted — a menu bar item that moves is a menu
    /// bar item you have to hunt for.
    private(set) var slots: [Slot] = []
    private(set) var recents: [TimeInterval] = []

    /// Bumped once per second so views recompute; the real clock is `Date()`.
    private(set) var tick: Date = Date()

    private var displayTimer: Foundation.Timer?
    private var fireTimers: [UUID: DispatchSourceTimer] = [:]
    private let notifier: Notifier
    private let store: Persistence

    init(notifier: Notifier = Notifier(), store: Persistence = Persistence()) {
        self.notifier = notifier
        self.store = store

        let snapshot = store.load()
        // Untouched drafts carry no information, so they are dropped on launch:
        // all of them when some real timer survives — any item can spawn another,
        // so a draft earns its menu bar width only when nothing else is there —
        // otherwise all but the first, leaving exactly one way back in.
        // "Draft" means draft as saved: a slot whose countdown expired below
        // still keeps its item, so a finished timer stays visible.
        let hasTimer = snapshot.slots.contains { !$0.isDraft }
        var keptDraft = false
        let deduped = snapshot.slots.filter { slot in
            guard slot.isDraft else { return true }
            if hasTimer || keptDraft { return false }
            keptDraft = true
            return true
        }
        // A timer that expired while we were closed is stale: keep the item,
        // drop its countdown, so the app never alarms about yesterday on launch.
        self.slots = deduped.map { slot in
            var slot = slot
            if let timer = slot.timer, timer.hasFired() { slot.timer = nil }
            return slot
        }
        self.recents = snapshot.recents
        // There is always at least one item, or the app has no way back in.
        if slots.isEmpty { slots = [Slot()] }

        startDisplayTick()
        for slot in slots { scheduleFire(slot) }
    }

    func slot(_ id: UUID) -> Slot? { slots.first { $0.id == id } }

    // MARK: - Slot lifecycle

    /// The "+ Add timer" command: a new, empty menu bar item.
    @discardableResult
    func addSlot() -> UUID {
        let slot = Slot()
        slots.append(slot)
        persist()
        return slot.id
    }

    /// Turns a draft into a countdown — the same item, now ticking.
    func start(_ id: UUID, with parsed: ParsedTimer) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        slots[index].timer = TimerItem(
            duration: parsed.duration, tag: parsed.tag, target: parsed.target, input: parsed.input
        )
        // Advance the shared clock with it, or views compare a brand-new end date
        // against a tick up to a second old and round up to 25:01 for a 25:00 timer.
        tick = Date()
        rememberRecent(parsed.duration)
        scheduleFire(slots[index])
        persist()
    }

    /// Removes the item entirely. The last one is emptied in place instead of
    /// vanishing, so the app is never left with no menu bar presence.
    ///
    /// Emptied, not replaced: tearing down the status item and building a new
    /// one makes the menu bar flicker and can land the item somewhere else.
    /// Reusing the slot keeps the same item exactly where it was.
    func remove(_ id: UUID) {
        cancelFire(id)
        if slots.count == 1, slots[0].id == id {
            slots[0].timer = nil
            persist()
            return
        }
        slots.removeAll { $0.id == id }
        if slots.isEmpty { slots = [Slot()] }
        persist()
    }

    /// Empties the item back to its input state, keeping its place in the bar.
    func clear(_ id: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        cancelFire(id)
        slots[index].timer = nil
        persist()
    }

    // MARK: - Timer commands

    func togglePause(_ id: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == id }), slots[index].timer != nil else { return }
        if slots[index].timer!.isPaused {
            slots[index].timer!.resume()
            scheduleFire(slots[index])
        } else {
            slots[index].timer!.pause()
            cancelFire(id)
        }
        persist()
    }

    /// Reset: full duration again, and paused. The pending alarm goes with it —
    /// a reset timer is not counting down, so it must not fire.
    ///
    /// A timer written as a time of day resets to its own words instead: the
    /// slot goes back to being a draft holding "@3pm", ready to start again.
    /// Rewinding it in place would leave a stopped timer showing the distance to
    /// the *next* 3pm, which after 3pm is most of a day — a number nobody asked
    /// for and could not have meant.
    func restart(_ id: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == id }), let timer = slots[index].timer else { return }
        cancelFire(id)

        if timer.target != nil, let input = timer.input, !input.isEmpty {
            slots[index].timer = nil
            slots[index].draft = input
        } else {
            slots[index].timer!.restart()
        }
        persist()
    }

    /// Keeps what is being typed with the slot, so it survives the panel closing.
    func setDraft(_ id: UUID, _ text: String) {
        guard let index = slots.firstIndex(where: { $0.id == id }), slots[index].draft != text else { return }
        slots[index].draft = text
        persist()
    }

    // MARK: - Ticking

    private func startDisplayTick() {
        // Fire just after each whole second, matching the boundary every timer's
        // end date is snapped to, so all countdowns change digit together — and
        // a hair late rather than a hair early, or a label can repaint on the
        // wrong side of its own rollover and show the same second twice.
        let nextSecond = Date().timeIntervalSinceReferenceDate.rounded(.down) + 1.01
        let timer = Foundation.Timer(
            fire: Date(timeIntervalSinceReferenceDate: nextSecond),
            interval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
        // .common keeps countdowns moving while a menu or resize is tracking.
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func scheduleFire(_ slot: Slot) {
        cancelFire(slot.id)
        guard let endsAt = slot.timer?.endsAt else { return }

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + max(0, endsAt.timeIntervalSinceNow), leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.fire(slot.id) }
        }
        source.resume()
        fireTimers[slot.id] = source
    }

    private func cancelFire(_ id: UUID) {
        fireTimers.removeValue(forKey: id)?.cancel()
    }

    private func fire(_ id: UUID) {
        guard let timer = slot(id)?.timer else { return }
        cancelFire(id)
        notifier.fire(tag: timer.tag, duration: timer.duration)
        // The item stays, reading 0:00, until you deal with it — an item that
        // clears itself leaves you unsure whether it ever ran.
        tick = Date()
    }

    private func rememberRecent(_ duration: TimeInterval) {
        recents.removeAll { $0 == duration }
        recents.insert(duration, at: 0)
        recents = Array(recents.prefix(4))
    }

    private func persist() {
        store.save(.init(slots: slots, recents: recents))
    }
}
