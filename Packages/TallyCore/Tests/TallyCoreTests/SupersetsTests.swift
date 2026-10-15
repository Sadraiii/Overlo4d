import Foundation
import Testing
@testable import TallyCore

private let a = UUID()
private let b = UUID()

@Suite struct SupersetsTests {
    @Test func normalizedKeepsNeighboursAndClearsLoners() {
        #expect(Supersets.normalized([a, a, nil, b]) == [a, a, nil, nil])
        #expect(Supersets.normalized([a, nil, a]) == [nil, nil, nil])
        #expect(Supersets.normalized([]) == [])
    }

    @Test func positions() {
        let ids: [UUID?] = [nil, a, a, a, b]
        #expect(Supersets.position(at: 0, in: ids) == .none)
        #expect(Supersets.position(at: 1, in: ids) == .first)
        #expect(Supersets.position(at: 2, in: ids) == .middle)
        #expect(Supersets.position(at: 3, in: ids) == .last)
        #expect(Supersets.position(at: 4, in: ids) == .none)
        #expect(Supersets.position(at: 9, in: ids) == .none)
    }

    @Test func restOnlyAfterLastExerciseOfGroup() {
        let ids: [UUID?] = [a, a, nil]
        #expect(!Supersets.restsAfter(index: 0, in: ids))
        #expect(Supersets.restsAfter(index: 1, in: ids))
        #expect(Supersets.restsAfter(index: 2, in: ids))
        // A loner left over from a removed partner rests normally.
        #expect(Supersets.restsAfter(index: 0, in: [a, nil]))
    }

    @Test func linkMovesOtherNextToAnchor() {
        let result = Supersets.link(0, with: 2, in: [nil, nil, nil], newID: a)
        #expect(result.order == [0, 2, 1])
        #expect(result.ids == [a, a, nil])
    }

    @Test func linkAppendsAfterExistingGroup() {
        let result = Supersets.link(0, with: 3, in: [a, a, nil, nil], newID: b)
        #expect(result.order == [0, 1, 3, 2])
        #expect(result.ids == [a, a, a, nil])
    }

    @Test func linkMovingOutOfAGroupClearsTheLeftoverLoner() {
        // Both are grouped: exercise 2 leaves group b (exercises 2 and 3) to join group a.
        let result = Supersets.link(0, with: 2, in: [a, a, b, b], newID: UUID())
        #expect(result.order == [0, 1, 2, 3])
        #expect(result.ids == [a, a, a, nil])
    }

    @Test func linkJoinsTheOtherExercisesGroupWhenTheAnchorHasNone() {
        // Exercise 0 isn't grouped; exercise 1 is in group a with 2, so 0 joins that group.
        let result = Supersets.link(0, with: 1, in: [nil, a, a], newID: b)
        #expect(result.order == [1, 2, 0])
        #expect(result.ids == [a, a, a])
    }

    @Test func linkWithItselfChangesNothing() {
        let result = Supersets.link(1, with: 1, in: [nil, a], newID: b)
        #expect(result.order == [0, 1])
        #expect(result.ids == [nil, a])
    }

    @Test func renewedKeepsGroupsWithNewIDs() {
        let fresh = [UUID(), UUID()]
        var next = 0
        let result = Supersets.renewed([a, a, nil, b, b]) {
            defer { next += 1 }
            return fresh[next]
        }
        #expect(result == [fresh[0], fresh[0], nil, fresh[1], fresh[1]])
    }
}
