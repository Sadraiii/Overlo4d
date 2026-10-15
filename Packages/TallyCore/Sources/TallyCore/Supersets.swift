import Foundation

/// Superset links for an ordered list of exercises. Each exercise has an optional group ID;
/// neighbours with the same ID form one superset.
public enum Supersets {
    /// Where an exercise sits in its superset, for drawing the group bar.
    public enum Position: Equatable, Sendable {
        case none, first, middle, last
    }

    /// Clears IDs that no longer link at least two neighbouring exercises.
    public static func normalized(_ ids: [UUID?]) -> [UUID?] {
        ids.indices.map { position(at: $0, in: ids) == .none ? nil : ids[$0] }
    }

    public static func position(at index: Int, in ids: [UUID?]) -> Position {
        guard ids.indices.contains(index), let id = ids[index] else { return .none }
        let before = index > 0 && ids[index - 1] == id
        let after = index + 1 < ids.count && ids[index + 1] == id
        switch (before, after) {
        case (false, false): return .none
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        }
    }

    /// Whether finishing a set of the exercise at `index` should start the rest timer: only when
    /// the next exercise isn't in the same superset.
    public static func restsAfter(index: Int, in ids: [UUID?]) -> Bool {
        let position = position(at: index, in: ids)
        return position == .none || position == .last
    }

    /// Puts the exercises at `anchor` and `other` in one superset. `other` joins the anchor's group
    /// and moves to just after it; when only `other` is in a superset, the anchor joins that one
    /// instead. Returns the new order (indices into the original list) and the IDs in that order.
    public static func link(_ anchor: Int, with other: Int, in ids: [UUID?], newID: UUID = UUID()) -> (order: [Int], ids: [UUID?]) {
        guard anchor != other, ids.indices.contains(anchor), ids.indices.contains(other) else {
            return (Array(ids.indices), ids)
        }
        let joinsOther = ids[anchor] == nil && ids[other] != nil
        let (target, moving) = joinsOther ? (other, anchor) : (anchor, other)
        let groupID = ids[target] ?? newID
        var updated = ids
        updated[target] = groupID
        updated[moving] = groupID

        var order = Array(ids.indices).filter { $0 != moving }
        guard var end = order.firstIndex(of: target) else { return (Array(ids.indices), ids) }
        // Walk to the end of the target's original group (the moved exercise is already out).
        while end + 1 < order.count, let targetID = ids[target], ids[order[end + 1]] == targetID {
            end += 1
        }
        order.insert(moving, at: end + 1)
        return (order, normalized(order.map { updated[$0] }))
    }

    /// The same groups with new IDs, for copying exercises into another workout or plan.
    public static func renewed(_ ids: [UUID?], makeID: () -> UUID = { UUID() }) -> [UUID?] {
        var mapping: [UUID: UUID] = [:]
        return ids.map { id in
            guard let id else { return nil }
            if let new = mapping[id] { return new }
            let new = makeID()
            mapping[id] = new
            return new
        }
    }
}
