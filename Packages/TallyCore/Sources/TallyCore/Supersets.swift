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

    /// What a group of this many exercises is called.
    public static func groupName(size: Int) -> String {
        switch size {
        case ...2: "Superset"
        case 3: "Giant set"
        default: "Circuit"
        }
    }

    /// The indices of the exercises grouped with the one at `index` (itself included), in order.
    public static func members(of index: Int, in ids: [UUID?]) -> [Int] {
        guard ids.indices.contains(index), let id = ids[index], position(at: index, in: ids) != .none else { return [] }
        var start = index, end = index
        while start > 0, ids[start - 1] == id { start -= 1 }
        while end + 1 < ids.count, ids[end + 1] == id { end += 1 }
        return Array(start...end)
    }

    /// A letter per group in list order (A, B, C…), nil for exercises on their own.
    public static func letters(_ ids: [UUID?]) -> [String?] {
        var letters: [UUID: String] = [:]
        return ids.indices.map { index in
            guard let id = ids[index], position(at: index, in: ids) != .none else { return nil }
            if let letter = letters[id] { return letter }
            let scalar = UnicodeScalar(UInt8(65 + letters.count % 26))
            let letter = String(Character(scalar))
            letters[id] = letter
            return letter
        }
    }

    /// Which exercise to do after finishing a set of the one at `index`. `remaining` holds the sets
    /// still to do per exercise. Inside a group the next member with sets left comes first (wrapping
    /// round to the start); otherwise the same exercise until it's done, then the next one down the
    /// list with sets left, then any earlier one. Nil when everything is done.
    public static func next(after index: Int, in ids: [UUID?], remaining: [Int]) -> Int? {
        guard ids.indices.contains(index), remaining.count == ids.count else { return nil }
        let group = members(of: index, in: ids)
        if let place = group.firstIndex(of: index) {
            let rotated = Array(group[(place + 1)...]) + Array(group[...place])
            if let next = rotated.first(where: { remaining[$0] > 0 }) { return next }
        } else if remaining[index] > 0 {
            return index
        }
        let after = ids.indices.filter { $0 > index && remaining[$0] > 0 }
        return after.first ?? ids.indices.first { remaining[$0] > 0 }
    }
}
