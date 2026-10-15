import Foundation
import Testing
@testable import TallyCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func span(daysAgo: Double, minutes: Double = 60) -> DateInterval {
    DateInterval(start: now.addingTimeInterval(-daysAgo * 86_400), duration: minutes * 60)
}

@Suite struct HealthLinkingTests {
    @Test func linksOlderSessionsToo() {
        let session = UUID(), watch = UUID()
        let plan = HealthLinking.plan(
            sessions: [LinkableSession(id: session, interval: span(daysAgo: 60))],
            candidates: [(id: watch, interval: span(daysAgo: 60, minutes: 70))],
            now: now
        )
        #expect(plan.links == [session: watch])
        #expect(plan.deletions.isEmpty)
    }

    @Test func eachHealthWorkoutLinksOnce() {
        let first = UUID(), second = UUID(), watch = UUID(), taken = UUID()
        let plan = HealthLinking.plan(
            sessions: [
                LinkableSession(id: first, interval: span(daysAgo: 1)),
                LinkableSession(id: second, interval: span(daysAgo: 1)),
                LinkableSession(id: UUID(), interval: span(daysAgo: 5), linkedHealthID: taken),
            ],
            candidates: [(id: watch, interval: span(daysAgo: 1)), (id: taken, interval: span(daysAgo: 5))],
            now: now
        )
        #expect(plan.links == [first: watch])
    }

    @Test func deletesOnlyRecentSavedCopiesOfLinkedSessions() {
        let recentCopy = UUID(), oldCopy = UUID(), unlinkedCopy = UUID(), alreadyLinkedCopy = UUID()
        let plan = HealthLinking.plan(
            sessions: [
                LinkableSession(id: UUID(), interval: span(daysAgo: 1), savedHealthID: recentCopy),
                LinkableSession(id: UUID(), interval: span(daysAgo: 10), savedHealthID: oldCopy),
                LinkableSession(id: UUID(), interval: span(daysAgo: 2), savedHealthID: unlinkedCopy),
                LinkableSession(id: UUID(), interval: span(daysAgo: 2), linkedHealthID: UUID(), savedHealthID: alreadyLinkedCopy),
            ],
            candidates: [(id: UUID(), interval: span(daysAgo: 1)), (id: UUID(), interval: span(daysAgo: 10))],
            now: now
        )
        #expect(Set(plan.deletions) == [recentCopy, alreadyLinkedCopy])
    }
}
