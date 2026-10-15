import Foundation

public enum Pace {
    /// Seconds per kilometre, or nil without both a distance and a time.
    public static func secondsPerKm(meters: Double?, seconds: Int?) -> Double? {
        guard let meters, let seconds, meters > 0, seconds > 0 else { return nil }
        return Double(seconds) / (meters / 1000)
    }

    /// "5:00 /km"
    public static func format(secondsPerKm: Double) -> String {
        "\(TimeEntry.format(Int(secondsPerKm.rounded()))) /km"
    }

    /// "800 m" under a kilometre, otherwise "5 km" or "5.25 km" with the locale's decimal separator.
    public static func distance(_ meters: Double, locale: Locale = .current) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        let km = (meters / 1000).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        return "\(km) km"
    }
}
