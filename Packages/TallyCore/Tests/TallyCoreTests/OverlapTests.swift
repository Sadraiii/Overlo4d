import Foundation
import Testing
@testable import TallyCore

private func interval(_ startMinute: Double, _ endMinute: Double) -> DateInterval {
    let base = Date(timeIntervalSinceReferenceDate: 0)
    return DateInterval(start: base.addingTimeInterval(startMinute * 60), end: base.addingTimeInterval(endMinute * 60))
}

@Suite struct OverlapTests {
    @Test func sharedSeconds() {
        #expect(Overlap.seconds(interval(0, 60), interval(30, 90)) == 1800)
        #expect(Overlap.seconds(interval(0, 60), interval(60, 90)) == 0)
        #expect(Overlap.seconds(interval(0, 60), interval(70, 90)) == 0)
    }

    @Test func sameSessionNeedsMoreThanHalfOfTheShorter() {
        // Watch started 5 minutes late and stopped 10 minutes after.
        #expect(Overlap.isSameSession(interval(0, 60), interval(5, 70)))
        // Exactly half is not enough.
        #expect(!Overlap.isSameSession(interval(0, 60), interval(30, 120)))
        // A short session fully inside a long one matches.
        #expect(Overlap.isSameSession(interval(0, 90), interval(20, 40)))
    }

    @Test func overlapIgnoresEmptyIntervals() {
        #expect(!Overlap.isSameSession(interval(10, 10), interval(0, 60)))
        #expect(!Overlap.isSameSession(interval(0, 60), interval(10, 10)))
    }

    @Test func bestMatchPicksLargestOverlap() {
        let a = UUID(), b = UUID(), c = UUID()
        let candidates = [(id: a, interval: interval(0, 40)), (id: b, interval: interval(10, 70)), (id: c, interval: interval(200, 260))]
        #expect(Overlap.bestMatch(for: interval(5, 65), in: candidates) == b)
        #expect(Overlap.bestMatch(for: interval(100, 130), in: candidates) == nil)
        #expect(Overlap.bestMatch(for: interval(0, 60), in: []) == nil)
    }
}
