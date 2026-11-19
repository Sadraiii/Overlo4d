import Foundation

/// Text for the number fields in set rows, and the number typed back.
///
/// The field keeps its own text and writes the number back when it changes. Formatting and
/// parsing must agree: if the text a number is shown as reads back as a different number, the
/// field and the workout keep rewriting each other. So: no grouping separators, either decimal
/// mark read back, and at most two decimals.
public enum NumberInput {
    /// "62.5" or "62,5" (with `decimalSeparator` ","), "100", "" for nil. Never "1,000" or "1 000".
    public static func text(_ value: Double?, decimalSeparator: String = ".") -> String {
        guard let value, value.isFinite else { return "" }
        let rounded = (value * 100).rounded() / 100
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        if text == "-0" { text = "0" }
        return decimalSeparator == "." ? text : text.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// The number in typed text: either decimal mark, spaces ignored. Nil when empty or not a number.
    public static func double(_ text: String) -> Double? {
        let cleaned = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// Whole numbers (reps): "8"; nil when empty or not a whole number.
    public static func int(_ text: String) -> Int? {
        Int(text.filter { !$0.isWhitespace })
    }

    /// Whether the field should write `typed` back to the model holding `stored`. False when the text
    /// is just how `stored` is shown (a stored 61.234 shows as "61.23" and must not become 61.23),
    /// so showing a value never changes it.
    public static func shouldWrite(_ typed: String, over stored: Double?, decimalSeparator: String = ".") -> Bool {
        if typed == text(stored, decimalSeparator: decimalSeparator) { return false }
        return double(typed) != stored
    }
}
