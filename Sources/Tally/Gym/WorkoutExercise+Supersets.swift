import Foundation
import TallyCore

extension Array where Element == WorkoutExercise {
    var supersetIDs: [UUID?] { map(\.supersetID) }

    func supersetPosition(of id: WorkoutExercise.ID) -> Supersets.Position {
        guard let index = firstIndex(where: { $0.id == id }) else { return .none }
        return Supersets.position(at: index, in: supersetIDs)
    }

    /// Clears superset links that no longer join two neighbouring exercises.
    mutating func normalizeSupersets() {
        let ids = Supersets.normalized(supersetIDs)
        for index in indices { self[index].supersetID = ids[index] }
    }

    /// Puts `other` in a superset with `anchor`, moving it next to the anchor's group.
    mutating func linkSuperset(_ anchor: WorkoutExercise.ID, with other: WorkoutExercise.ID) {
        guard let anchorIndex = firstIndex(where: { $0.id == anchor }),
              let otherIndex = firstIndex(where: { $0.id == other }) else { return }
        let result = Supersets.link(anchorIndex, with: otherIndex, in: supersetIDs)
        var reordered = result.order.map { self[$0] }
        for index in reordered.indices { reordered[index].supersetID = result.ids[index] }
        self = reordered
    }

    /// Takes an exercise out of its superset and places it just after the group.
    mutating func unlinkSuperset(_ id: WorkoutExercise.ID) {
        guard let index = firstIndex(where: { $0.id == id }), let group = self[index].supersetID else { return }
        var end = index
        while end + 1 < count, self[end + 1].supersetID == group { end += 1 }
        var exercise = remove(at: index)
        exercise.supersetID = nil
        insert(exercise, at: end)
        normalizeSupersets()
    }

    /// Exercises that `id` can join in a superset: every other exercise not already in its group.
    func supersetCandidates(for id: WorkoutExercise.ID) -> [WorkoutExercise] {
        let group = first { $0.id == id }?.supersetID
        return filter { $0.id != id && (group == nil || $0.supersetID != group) }
    }

    /// The same exercises with new superset IDs, so a copy doesn't share groups with the original.
    func withRenewedSupersets() -> [WorkoutExercise] {
        let ids = Supersets.renewed(supersetIDs)
        var copy = self
        for index in copy.indices { copy[index].supersetID = ids[index] }
        return copy
    }
}
