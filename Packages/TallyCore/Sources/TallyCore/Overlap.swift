import Foundation

/// Decides whether two recorded workouts are the same session, e.g. a Tally workout and an Apple
/// Watch workout started a few minutes apart.
public enum Overlap {
    /// Seconds the two intervals have in common.
    public static func seconds(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
    }

    /// True when they share more than half of the shorter one. Empty intervals never match.
    public static func isSameSession(_ a: DateInterval, _ b: DateInterval) -> Bool {
        let shorter = min(a.duration, b.duration)
        guard shorter > 0 else { return false }
        return seconds(a, b) > shorter / 2
    }

    /// The candidate that is the same session as `interval`, preferring the largest overlap.
    public static func bestMatch(for interval: DateInterval, in candidates: [(id: UUID, interval: DateInterval)]) -> UUID? {
        candidates
            .filter { isSameSession(interval, $0.interval) }
            .max { seconds(interval, $0.interval) < seconds(interval, $1.interval) }?
            .id
    }
}
