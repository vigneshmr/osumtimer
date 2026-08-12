import XCTest
@testable import OsumTimer

final class ParserTests: XCTestCase {
    private func duration(_ input: String, now: Date = Date()) -> TimeInterval? {
        try? Parser.parse(input, now: now).get().duration
    }

    func testBareNumberIsMinutes() {
        XCTAssertEqual(duration("25"), 1500)
        XCTAssertEqual(duration("90"), 5400)
    }

    func testUnitSuffixes() {
        XCTAssertEqual(duration("45m"), 2700)
        XCTAssertEqual(duration("2h"), 7200)
        XCTAssertEqual(duration("30s"), 30)
        XCTAssertEqual(duration("1.5h"), 5400)
        XCTAssertEqual(duration("3 minutes"), 180)
    }

    func testCompoundUnits() {
        XCTAssertEqual(duration("1h30m"), 5400)
        XCTAssertEqual(duration("1h 30m 15s"), 5415)
    }

    func testColonFormIsRightAnchored() {
        XCTAssertEqual(duration("1:30"), 90)
        XCTAssertEqual(duration("1:30:45"), 5445)
        XCTAssertEqual(duration("0:05"), 5)
    }

    func testColonFormRejectsOverflowedUnits() {
        XCTAssertNil(duration("1:75"))
        XCTAssertNil(duration("1:2:3:4"))
    }

    func testTagIsExtractedAndStripped() {
        let parsed = try? Parser.parse("#deepwork 25m").get()
        XCTAssertEqual(parsed?.tag, "deepwork")
        XCTAssertEqual(parsed?.duration, 1500)

        let trailing = try? Parser.parse("25m #focus").get()
        XCTAssertEqual(trailing?.tag, "focus")
        XCTAssertEqual(trailing?.duration, 1500)
    }

    func testAbsoluteTargetsUseNextOccurrence() {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 12
        components.hour = 14; components.minute = 0
        let now = Calendar.current.date(from: components)!

        XCTAssertEqual(duration("@5pm", now: now), 3 * 3600)
        XCTAssertEqual(duration("@2:30pm", now: now), 1800)
        XCTAssertEqual(duration("@18", now: now), 4 * 3600)
        XCTAssertEqual(duration("@9am #standup", now: now), 19 * 3600)
        XCTAssertEqual(duration("till 5pm", now: now), 3 * 3600)
        XCTAssertEqual(duration("until 14:30", now: now), 1800)
        // Already past today, so it means tomorrow.
        XCTAssertEqual(duration("till 9am", now: now), 19 * 3600)
    }

    func testRejections() {
        XCTAssertEqual(Parser.parse(""), .failure(.empty))
        XCTAssertEqual(Parser.parse("banana"), .failure(.unrecognized))
        XCTAssertEqual(Parser.parse("0m"), .failure(.notPositive))
        XCTAssertEqual(Parser.parse("30d"), .failure(.tooLong))
    }

    func testClockFormatting() {
        XCTAssertEqual(Parser.clock(for: 65), "1:05")
        XCTAssertEqual(Parser.clock(for: 3661), "1:01:01")
        XCTAssertEqual(Parser.clock(for: -5), "0:00")
    }

    func testEcho() {
        XCTAssertEqual(Parser.echo(for: 5400), "1 hr 30 min")
        XCTAssertEqual(Parser.echo(for: 45), "45 sec")
        XCTAssertEqual(Parser.echo(for: 1500), "25 min")
    }
}

final class TimerItemTests: XCTestCase {
    /// End dates snap to whole seconds so every timer ticks on the same
    /// boundary; starting from a whole second keeps these expectations exact.
    private let now = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded())

    func testRemainingIsDerivedFromAbsoluteEndDate() {
        let timer = TimerItem(duration: 60, now: now)
        XCTAssertEqual(timer.remaining(at: now), 60, accuracy: 0.01)
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(45)), 15, accuracy: 0.01)
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(90)), 0)
    }

    func testPauseFreezesAndResumeShiftsTheEndDate() {
        var timer = TimerItem(duration: 60, now: now)
        timer.pause(at: now.addingTimeInterval(20))
        XCTAssertTrue(timer.isPaused)

        // Time passing while paused must not consume the countdown.
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(500)), 40, accuracy: 0.01)

        timer.resume(at: now.addingTimeInterval(500))
        XCTAssertFalse(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: now.addingTimeInterval(510)), 30, accuracy: 0.01)
    }

    func testProgress() {
        let timer = TimerItem(duration: 100, now: now)
        XCTAssertEqual(timer.progress(at: now), 0, accuracy: 0.01)
        XCTAssertEqual(timer.progress(at: now.addingTimeInterval(75)), 0.75, accuracy: 0.01)
        XCTAssertEqual(timer.progress(at: now.addingTimeInterval(200)), 1, accuracy: 0.01)
    }
}
