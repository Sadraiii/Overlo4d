import Foundation

/// Which plan to train next: the one that has waited longest and whose muscles are rested.
public enum UpNext {
    public struct Candidate: Sendable, Equatable {
        public let id: UUID
        public let lastDone: Date?
        /// Primary muscles of the plan's exercises, as raw names.
        public let muscles: [String]

        public init(id: UUID, lastDone: Date?, muscles: [String]) {
            self.id = id
            self.lastDone = lastDone
            self.muscles = muscles
        }
    }

    public struct Pick: Sendable, Equatable {
        public let id: UUID
        /// Whole days since the plan was last done, nil when never.
        public let daysSince: Int?
        /// 0–1: how recovered the plan's muscles are on average.
        public let readiness: Double
        /// Muscles of the plan still recovering (under 80 %), most tired first.
        public let tired: [String]
    }

    /// - Parameter recovery: recovery progress 0–1 per muscle; muscles not listed count as rested.
    public static func pick(candidates: [Candidate], recovery: [String: Double], now: Date) -> Pick? {
        var best: (pick: Pick, score: Double)?
        for candidate in candidates {
            let muscles = Array(Set(candidate.muscles)).sorted()
            let levels = muscles.map { min(1, max(0, recovery[$0] ?? 1)) }
            let readiness = levels.isEmpty ? 1 : levels.reduce(0, +) / Double(levels.count)
            let days = candidate.lastDone.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
            // A plan never done waits as long as one left for two weeks.
            let waited = Double(min(days ?? 14, 14)) / 14
            let score = readiness * 0.55 + waited * 0.45
            let tired = muscles.filter { (recovery[$0] ?? 1) < 0.8 }.sorted { (recovery[$0] ?? 1) < (recovery[$1] ?? 1) }
            let pick = Pick(id: candidate.id, daysSince: days, readiness: readiness, tired: tired)
            // Ties keep the earlier plan, so the order of the Plans tab decides.
            if best == nil || score > best!.score + 0.0001 { best = (pick, score) }
        }
        return best?.pick
    }

    /// "Last done 5 days ago", "Last done yesterday", "Not done yet".
    public static func waitText(daysSince: Int?) -> String {
        switch daysSince {
        case nil: "Not done yet"
        case 0?: "Last done today"
        case 1?: "Last done yesterday"
        case let days?: "Last done \(days) days ago"
        }
    }
}
