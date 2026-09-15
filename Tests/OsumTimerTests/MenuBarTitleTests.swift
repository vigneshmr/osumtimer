import AppKit
import XCTest
@testable import OsumTimer

/// The menu bar item sizes itself to its title, so a countdown that loses a
/// character moves the item — and the panel anchored to it. The padding is only
/// worth anything if it measures exactly, in the font the item actually uses.
@MainActor
final class MenuBarTitleTests: XCTestCase {
    private let font = NSFont.monospacedDigitSystemFont(ofSize: Design.menuBarSize, weight: .medium)

    private func width(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    private func assertSameWidth(_ title: String, _ widest: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(width(StatusItemController.padded(title, to: widest)), width(widest),
                       accuracy: 0.01, file: file, line: line)
    }

    func testLosingADigitKeepsTheWidth() {
        assertSameWidth("9:59", "10:00")
        assertSameWidth("0:59", "1:00")
    }

    func testLosingTheHoursKeepsTheWidth() {
        assertSameWidth("59:59", "1:00:00")
        assertSameWidth("9:59", "1:00:00")
    }

    func testEveryStepOfALongCountdownIsOneWidth() {
        let widest = Parser.clock(for: 3600)
        for remaining in stride(from: 3600.0, through: 0, by: -1) {
            assertSameWidth(Parser.clock(for: remaining), widest)
        }
    }

    /// In percent mode both numbers move: "0% (25:00 left)" through
    /// "100% (0:00 left)" all measure the same.
    func testEveryPercentIsOneWidth() {
        let widest = "100% (\(Parser.clock(for: 1500)) left)"
        for remaining in stride(from: 1500.0, through: 0, by: -15) {
            let percent = Int((1 - remaining / 1500) * 100)
            assertSameWidth("\(percent)% (\(Parser.clock(for: remaining)) left)", widest)
        }
    }

    func testFullWidthTitleIsLeftAlone() {
        XCTAssertEqual(StatusItemController.padded("10:00", to: "10:00"), "10:00")
    }
}
