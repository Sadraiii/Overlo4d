import Foundation

/// A Tally workout as the Health sync sees it.
public struct LinkableSession: Sendable, Equatable {
    public var id: UUID
    public var interval: DateInterval
    /// The Health workout this session is already merged with.
    public var linkedHealthID: UUID?
    /// The workout Tally itself saved to Health for this session.
    public var savedHealthID: UUID?

    public init(id: UUID, interval: DateInterval, linkedHealthID: UUID? = nil, savedHealthID: UUID? = nil) {
        self.id = id
        self.interval = interval
        self.linkedHealthID = linkedHealthID
        self.savedHealthID = savedHealthID
    }
}

public struct HealthLinkPlan: Sendable, Equatable {
    /// New links: Tally session ID → Health workout ID.
    public var links: [UUID: UUID]
    /// Tally's own Health copies that are now duplicates and should be deleted.
    public var deletions: [UUID]
}

public enum HealthLinking {
    /// Links every unlinked session to the strength workout it overlaps, using each Health workout
    /// once. Only copies Tally saved for sessions started within `deleteWindow` are deleted, so
    /// older Health data is never removed.
    public static func plan(
        sessions: [LinkableSession],
        candidates: [(id: UUID, interval: DateInterval)],
        now: Date,
        deleteWindow: TimeInterval = 3 * 86_400
    ) -> HealthLinkPlan {
        var taken = Set(sessions.compactMap(\.linkedHealthID))
        var links: [UUID: UUID] = [:]
        for session in sessions.sorted(by: { $0.interval.start < $1.interval.start }) where session.linkedHealthID == nil {
            let free = candidates.filter { !taken.contains($0.id) }
            if let match = Overlap.bestMatch(for: session.interval, in: free) {
                links[session.id] = match
                taken.insert(match)
            }
        }
        let recent = now.addingTimeInterval(-deleteWindow)
        let deletions = sessions.compactMap { session -> UUID? in
            let isLinked = session.linkedHealthID != nil || links[session.id] != nil
            return isLinked && session.interval.start >= recent ? session.savedHealthID : nil
        }
        return HealthLinkPlan(links: links, deletions: deletions)
    }
}
