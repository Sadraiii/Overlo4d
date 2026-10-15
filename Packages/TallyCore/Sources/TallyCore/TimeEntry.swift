import Foundation

/// Timer-style time entry: digits fill from the right, so typing 2, 5, 0, 0 gives 25:00.
public enum TimeEntry {
    public static let maxDigits = 6

    /// Only the digits of `text`, without leading zeros, at most `maxDigits`.
    public static func cleaned(_ text: String) -> String {
        let digits = text.filter { $0.isASCII && $0.isNumber }.drop { $0 == "0" }
        return String(digits.prefix(maxDigits))
    }

    /// Seconds for typed digits: the last two are seconds, the two before minutes, the rest hours.
    /// Values over 59 are allowed while typing ("90" is 90 seconds).
    public static func seconds(fromDigits digits: String) -> Int? {
        guard let value = Int(digits), value > 0 else { return nil }
        return (value / 10_000) * 3600 + (value / 100 % 100) * 60 + value % 100
    }

    /// The digits that show `seconds` as h:mm:ss or m:ss.
    public static func digits(fromSeconds seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        return String(seconds / 3600 * 10_000 + seconds % 3600 / 60 * 100 + seconds % 60)
    }

    /// Digits with colons, as shown while typing: "5" → "0:05", "2500" → "25:00", "12500" → "1:25:00".
    public static func display(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }
        var rest = Substring(String(repeating: "0", count: max(0, 3 - digits.count)) + digits)
        var groups: [Substring] = []
        while rest.count > 2 {
            groups.insert(rest.suffix(2), at: 0)
            rest = rest.dropLast(2)
        }
        groups.insert(rest, at: 0)
        return groups.joined(separator: ":")
    }

    /// "0:00", "1:05", "1:02:03".
    public static func format(_ seconds: Int) -> String {
        seconds > 0 ? display(digits(fromSeconds: seconds)) : "0:00"
    }
}
