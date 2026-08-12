import Foundation

/// The result of interpreting a line of user input.
struct ParsedTimer: Equatable {
    var duration: TimeInterval
    var tag: String?
    /// Human-readable echo of what we understood, shown live under the field.
    var echo: String
}

enum ParseError: Error, Equatable {
    case empty
    case unrecognized
    case notPositive
    case tooLong
}

/// Turns "45m", "1.5h", "1:30:45", "till 5pm", "#deepwork 25" into a duration.
///
/// Rules are tried in order; the first that consumes the whole input wins.
/// A bare number means minutes, because that is what people type most.
enum Parser {
    static let maxDuration: TimeInterval = 60 * 60 * 24 * 7

    static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Result<ParsedTimer, ParseError> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .failure(.empty) }

        let tag = extractTag(from: &text)
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .failure(.unrecognized) }

        let duration: TimeInterval? =
            absoluteTarget(text, now: now, calendar: calendar)
            ?? colonForm(text)
            ?? unitForm(text)
            ?? bareMinutes(text)

        guard let duration else { return .failure(.unrecognized) }
        guard duration > 0 else { return .failure(.notPositive) }
        guard duration <= maxDuration else { return .failure(.tooLong) }

        return .success(ParsedTimer(duration: duration, tag: tag, echo: echo(for: duration)))
    }

    // MARK: - Rules

    /// `#deepwork 25m` — the tag is stripped wherever it appears.
    private static func extractTag(from text: inout String) -> String? {
        guard let hash = text.firstIndex(of: "#") else { return nil }
        let after = text.index(after: hash)
        let end = text[after...].firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
        let tag = String(text[after..<end])
        text.removeSubrange(hash..<end)
        text = text.trimmingCharacters(in: .whitespaces)
        return tag.isEmpty ? nil : tag
    }

    /// `@2pm`, `till 5pm`, `until 14:00`, `to 9:30am`
    private static func absoluteTarget(_ text: String, now: Date, calendar: Calendar) -> TimeInterval? {
        let prefixes = ["@", "till ", "til ", "until ", "to "]
        guard let prefix = prefixes.first(where: { text.hasPrefix($0) }) else { return nil }
        var clock = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)

        var isPM: Bool?
        if clock.hasSuffix("pm") { isPM = true; clock = String(clock.dropLast(2)) }
        else if clock.hasSuffix("am") { isPM = false; clock = String(clock.dropLast(2)) }
        clock = clock.trimmingCharacters(in: .whitespaces)

        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), var hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0..<60).contains(minute), (0...23).contains(hour) else { return nil }

        if let isPM {
            guard (1...12).contains(hour) else { return nil }
            if isPM, hour != 12 { hour += 12 }
            if !isPM, hour == 12 { hour = 0 }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var target = calendar.date(from: components) else { return nil }
        // Always mean the *next* occurrence of that clock time.
        if target <= now { target = target.addingTimeInterval(86_400) }
        return target.timeIntervalSince(now)
    }

    /// `1:30` (m:s) and `1:30:45` (h:m:s) — right-anchored, like a stopwatch reads.
    private static func colonForm(_ text: String) -> TimeInterval? {
        guard text.contains(":") else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        // Every field but the leading one is a 0..<60 unit.
        guard numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }

        return numbers.count == 2
            ? TimeInterval(numbers[0] * 60 + numbers[1])
            : TimeInterval(numbers[0] * 3600 + numbers[1] * 60 + numbers[2])
    }

    /// `45m`, `2h`, `30s`, `1.5h`, and compounds like `1h30m`.
    private static func unitForm(_ text: String) -> TimeInterval? {
        var total: TimeInterval = 0
        var matched = false
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace { index = text.index(after: index); continue }

            // Number.
            let numberStart = index
            while index < text.endIndex, text[index].isNumber || text[index] == "." {
                index = text.index(after: index)
            }
            guard numberStart < index, let value = Double(text[numberStart..<index]) else { return nil }

            // Unit — may be separated from its number, as in "3 minutes".
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            let unitStart = index
            while index < text.endIndex, text[index].isLetter { index = text.index(after: index) }
            let unit = String(text[unitStart..<index])

            let multiplier: TimeInterval
            switch unit {
            case "s", "sec", "secs", "second", "seconds": multiplier = 1
            case "m", "min", "mins", "minute", "minutes": multiplier = 60
            case "h", "hr", "hrs", "hour", "hours": multiplier = 3600
            case "d", "day", "days": multiplier = 86_400
            default: return nil
            }

            total += value * multiplier
            matched = true
        }

        return matched ? total.rounded() : nil
    }

    /// A bare number is minutes: `25` means a 25 minute timer.
    private static func bareMinutes(_ text: String) -> TimeInterval? {
        guard let value = Double(text) else { return nil }
        return (value * 60).rounded()
    }

    // MARK: - Echo

    /// "1 hr 30 min" — deliberately terse, this sits under the input at 11pt.
    static func echo(for duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        var pieces: [String] = []
        if days > 0 { pieces.append("\(days) day\(days == 1 ? "" : "s")") }
        if hours > 0 { pieces.append("\(hours) hr") }
        if minutes > 0 { pieces.append("\(minutes) min") }
        if seconds > 0, days == 0, hours == 0 { pieces.append("\(seconds) sec") }
        return pieces.isEmpty ? "0 sec" : pieces.joined(separator: " ")
    }

    /// `12:34` / `1:02:03` — the menu bar and row format. Always right-anchored.
    static func clock(for remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
