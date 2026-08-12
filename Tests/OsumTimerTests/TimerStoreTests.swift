import XCTest
@testable import OsumTimer

@MainActor
final class TimerStoreTests: XCTestCase {
    private var scratchFiles: [String] = []

    /// A store backed by a throwaway file, preloaded with `snapshot`.
    private func store(_ snapshot: Snapshot) -> TimerStore {
        let filename = "test-\(UUID().uuidString).json"
        scratchFiles.append(filename)
        let persistence = Persistence(filename: filename)
        persistence.save(snapshot)
        return TimerStore(store: persistence)
    }

    override func tearDown() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OsumTimer", isDirectory: true)
        for file in scratchFiles {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(file))
        }
        scratchFiles = []
        super.tearDown()
    }

    /// A live timer is itself a way to make new timers, so drafts all go.
    func testDraftsAreDroppedWhenATimerSurvives() {
        let live = Slot(timer: TimerItem(duration: 600))
        let loaded = store(Snapshot(slots: [Slot(), Slot(), live, Slot()]))

        XCTAssertEqual(loaded.slots.map(\.id), [live.id])
    }

    /// With nothing else left, drafts coalesce to one rather than to none.
    func testDraftsCoalesceToOneWhenNoTimerSurvives() {
        let first = Slot()
        let loaded = store(Snapshot(slots: [first, Slot(), Slot()]))

        XCTAssertEqual(loaded.slots.map(\.id), [first.id])
    }

    func testSingleDraftIsUntouched() {
        let draft = Slot()
        let loaded = store(Snapshot(slots: [draft]))

        XCTAssertEqual(loaded.slots.map(\.id), [draft.id])
    }

    /// An expired countdown is reset to a draft, but it was not a draft on disk:
    /// it keeps its item, and counts as the survivor that displaces real drafts.
    func testExpiredTimerKeepsItsItemAndDisplacesDrafts() {
        let stale = Slot(timer: TimerItem(duration: 60, now: Date(timeIntervalSinceNow: -600)))
        let loaded = store(Snapshot(slots: [Slot(), stale]))

        XCTAssertEqual(loaded.slots.map(\.id), [stale.id])
        XCTAssertNil(loaded.slots[0].timer)
    }

    /// Timers started at any sub-second phase share one rollover boundary, so
    /// their menu bar digits change together.
    func testEndDatesSnapToWholeSeconds() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000.0)
        for offset in [0.0, 0.13, 0.4, 0.61, 0.99] {
            let timer = TimerItem(duration: 600, now: base.addingTimeInterval(offset))
            let end = try! XCTUnwrap(timer.endsAt).timeIntervalSinceReferenceDate
            XCTAssertEqual(end, end.rounded(), accuracy: 0.0001, "offset \(offset) left a fractional end date")
        }
    }

    /// Snapping must never round a timer up: a 25:00 timer reads "25:00" the
    /// instant it starts, from any sub-second phase.
    func testTimerNeverRendersASecondTooHigh() {
        for offset in [0.0, 0.13, 0.4, 0.61, 0.99] {
            let now = Date(timeIntervalSinceReferenceDate: 1_000 + offset)
            let timer = TimerItem(duration: 1500, now: now)
            XCTAssertEqual(Parser.clock(for: timer.remaining(at: now)), "25:00", "offset \(offset)")
        }
    }

    /// Reset returns the full duration and holds it there — no ticking, and no
    /// end date left behind that could still fire.
    func testResetRewindsAndStops() {
        var timer = TimerItem(duration: 600, now: Date(timeIntervalSinceReferenceDate: 1_000))
        timer.restart()

        XCTAssertTrue(timer.isPaused)
        XCTAssertNil(timer.endsAt)
        // Whenever you look at it afterwards, it still reads the full duration.
        XCTAssertEqual(timer.remaining(at: Date(timeIntervalSinceReferenceDate: 5_000)), 600)
        XCTAssertFalse(timer.hasFired(at: Date(timeIntervalSinceReferenceDate: 99_000)))
    }

    /// A reset timer reads "ready", not "paused" — paused means stopped partway.
    func testResetIsReadyButPausedPartwayIsNot() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var timer = TimerItem(duration: 600, now: start)

        timer.pause(at: start.addingTimeInterval(120))
        XCTAssertFalse(timer.isReady)

        timer.restart()
        XCTAssertTrue(timer.isReady)

        timer.resume(at: start.addingTimeInterval(300))
        XCTAssertFalse(timer.isReady, "a running timer is never ready")
    }

    /// "@5pm" means five o'clock whenever you reset it, not the gap it once was.
    func testResetOnAnAbsoluteTargetResolvesTheTimeAgain() {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            var components = DateComponents()
            components.year = 2026; components.month = 8; components.day = 12
            components.hour = hour; components.minute = minute
            return Calendar.current.date(from: components)!
        }

        // Set at 3pm for 5pm: two hours.
        let parsed = try! Parser.parse("@5pm", now: at(15)).get()
        XCTAssertEqual(parsed.duration, 2 * 3600)
        var timer = TimerItem(duration: parsed.duration, target: parsed.target, now: at(15))

        // Reset at 4:30 means half an hour, not two.
        timer.restart(at: at(16, 30))
        XCTAssertEqual(timer.remaining(at: at(16, 30)), 1800, accuracy: 1)

        // Past it, the next occurrence is tomorrow.
        timer.restart(at: at(18))
        XCTAssertEqual(timer.remaining(at: at(18)), 23 * 3600, accuracy: 1)
    }

    /// A plain duration is unaffected: it resets to the length it was given.
    func testResetOnAPlainDurationKeepsItsLength() {
        var timer = TimerItem(duration: 600, now: Date(timeIntervalSinceReferenceDate: 1_000))
        timer.restart(at: Date(timeIntervalSinceReferenceDate: 9_999))

        XCTAssertEqual(timer.remaining(at: Date(timeIntervalSinceReferenceDate: 9_999)), 600)
    }

    /// Reset on an "@3pm" timer hands the words back rather than leaving a
    /// stopped timer counting the distance to tomorrow's 3pm.
    func testResetOnATargetTimerReturnsItToADraft() {
        let loaded = store(Snapshot(slots: [Slot()]))
        let id = loaded.slots[0].id
        let parsed = try! Parser.parse("@3pm #focus").get()
        loaded.start(id, with: parsed)
        XCTAssertNotNil(loaded.slots[0].timer)

        loaded.restart(id)

        XCTAssertNil(loaded.slots[0].timer, "the countdown is gone")
        XCTAssertEqual(loaded.slots[0].draft, "@3pm #focus", "its words are waiting in the editor")
    }

    /// The draft survives the panel closing, which is why it lives in the store.
    func testDraftIsKeptOnTheSlot() {
        let loaded = store(Snapshot(slots: [Slot()]))
        let id = loaded.slots[0].id

        loaded.setDraft(id, "@5pm")
        XCTAssertEqual(loaded.slots[0].draft, "@5pm")

        loaded.setDraft(id, "")
        XCTAssertEqual(loaded.slots[0].draft, "")
    }

    func testResumeAfterResetSnapsToAWholeSecond() {
        var timer = TimerItem(duration: 600, now: Date(timeIntervalSinceReferenceDate: 1_000.3))
        timer.restart()
        timer.resume(at: Date(timeIntervalSinceReferenceDate: 2_200.83))

        let end = try! XCTUnwrap(timer.endsAt).timeIntervalSinceReferenceDate
        XCTAssertEqual(end, end.rounded(), accuracy: 0.0001)
        XCTAssertFalse(timer.isPaused)
    }

    /// Deleting the last timer reuses its slot, so the menu bar item stays put
    /// rather than being torn down and rebuilt.
    func testRemovingTheLastSlotEmptiesItInPlace() {
        let only = Slot(timer: TimerItem(duration: 600))
        let loaded = store(Snapshot(slots: [only]))

        loaded.remove(only.id)

        XCTAssertEqual(loaded.slots.map(\.id), [only.id])
        XCTAssertNil(loaded.slots[0].timer)
    }

    func testRemovingOneOfSeveralDropsItEntirely() {
        let first = Slot(timer: TimerItem(duration: 600))
        let second = Slot(timer: TimerItem(duration: 900))
        let loaded = store(Snapshot(slots: [first, second]))

        loaded.remove(first.id)

        XCTAssertEqual(loaded.slots.map(\.id), [second.id])
    }

    func testEmptySnapshotStillYieldsOneSlot() {
        XCTAssertEqual(store(Snapshot()).slots.count, 1)
    }
}
