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

    func testEmptySnapshotStillYieldsOneSlot() {
        XCTAssertEqual(store(Snapshot()).slots.count, 1)
    }
}
