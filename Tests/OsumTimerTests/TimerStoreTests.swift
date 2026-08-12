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
