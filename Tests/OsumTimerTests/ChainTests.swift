import XCTest
@testable import OsumTimer

final class ChainTests: XCTestCase {
    private func parse(_ input: String) -> ParsedTimer? { try? Parser.parse(input).get() }

    func testCommasMakeAChain() {
        let parsed = parse("12m,12m,")
        XCTAssertEqual(parsed?.chain, [720, 720])
        XCTAssertEqual(parsed?.duration, 720)
        XCTAssertEqual(parsed?.repeats, false)
        XCTAssertEqual(parse("25, 5m, 1:30")?.chain, [1500, 300, 90])
    }

    func testRepeatLoops() {
        let parsed = parse("12m,repeat")
        XCTAssertEqual(parsed?.chain, [720])
        XCTAssertEqual(parsed?.repeats, true)
        XCTAssertEqual(parsed?.echo, "12 min, repeating")
        XCTAssertEqual(parse("#pomo 25m, 5m, repeat")?.tag, "pomo")
        XCTAssertEqual(parse("25m, 5m, repeat,")?.repeats, true)
    }

    func testOneStepWithATrailingCommaIsAPlainTimer() {
        XCTAssertNil(parse("12m,")?.chain)
        XCTAssertEqual(parse("12m,")?.duration, 720)
    }

    func testBadChainsAreRejected() {
        XCTAssertNil(parse("repeat"))
        XCTAssertNil(parse("12m,,12m"))
        XCTAssertNil(parse("repeat,12m"))
        XCTAssertNil(parse("12m,@5pm"))
        XCTAssertNil(parse("12m,banana"))
    }

    private func chain(_ steps: [TimeInterval], repeats: Bool, now: Date) -> TimerItem {
        var timer = TimerItem(duration: steps[0], now: now)
        timer.chain = steps
        timer.repeats = repeats
        return timer
    }

    func testAdvanceStartsFromWhereTheStepEnded() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var timer = chain([60, 120], repeats: false, now: start)
        XCTAssertTrue(timer.hasNextStep)
        timer.advance(at: start.addingTimeInterval(90))
        XCTAssertEqual(timer.step, 1)
        XCTAssertEqual(timer.duration, 120)
        XCTAssertEqual(timer.endsAt, start.addingTimeInterval(180))
        XCTAssertFalse(timer.hasNextStep)
        XCTAssertEqual(timer.stepLabel, "2/2")
    }

    func testRepeatWrapsAndCountsRounds() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var timer = chain([60], repeats: true, now: start)
        timer.advance()
        timer.advance()
        XCTAssertEqual(timer.step, 0)
        XCTAssertEqual(timer.round, 3)
        XCTAssertEqual(timer.stepLabel, "↻3")
    }

    func testCatchUpLandsOnTheStepRunningNow() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var timer = chain([60, 30], repeats: true, now: start)
        // 10 full rounds of 90s, then 70s in: second step, 20s left.
        timer.catchUp(to: start.addingTimeInterval(970))
        XCTAssertEqual(timer.step, 1)
        XCTAssertEqual(timer.round, 11)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(970)), 20)

        var once = chain([60, 30], repeats: false, now: start)
        once.catchUp(to: start.addingTimeInterval(500))
        XCTAssertEqual(once.step, 1)
        XCTAssertTrue(once.hasFired(at: start.addingTimeInterval(500)))
    }

    func testResetGoesBackToTheFirstStep() {
        var timer = chain([60, 30], repeats: true, now: Date())
        timer.advance()
        timer.advance()
        timer.restart()
        XCTAssertEqual(timer.step, 0)
        XCTAssertEqual(timer.round, 1)
        XCTAssertEqual(timer.duration, 60)
        XCTAssertTrue(timer.isReady)
    }

    func testChainSurvivesEncoding() throws {
        var timer = chain([60, 30], repeats: true, now: Date())
        timer.advance()
        let decoded = try JSONDecoder().decode(TimerItem.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(decoded, timer)
    }
}
