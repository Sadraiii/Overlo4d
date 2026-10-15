import Foundation
import HealthKit

/// A workout from Apple Health that Tally didn't record, e.g. a run tracked on Apple Watch.
struct HealthWorkout: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let symbol: String
    /// Strength-type sessions, which can be the same session as a Tally workout.
    let isStrengthLike: Bool
    let start: Date
    let end: Date
    /// Active energy in kcal.
    let energy: Double?
    let meters: Double?
    let sourceName: String

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var interval: DateInterval { DateInterval(start: start, duration: duration) }
}

extension HealthWorkout {
    init(_ workout: HKWorkout) {
        let indoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
        let info = Self.describe(workout.workoutActivityType, indoor: indoor)
        let distanceTypes = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]
        self.init(
            id: workout.uuid,
            name: info.name,
            symbol: info.symbol,
            isStrengthLike: info.strength,
            start: workout.startDate,
            end: workout.endDate,
            energy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            meters: distanceTypes.lazy.compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }.first,
            sourceName: workout.sourceRevision.source.name
        )
    }

    private static func describe(_ type: HKWorkoutActivityType, indoor: Bool) -> (name: String, symbol: String, strength: Bool) {
        switch type {
        case .traditionalStrengthTraining: ("Strength training", "figure.strengthtraining.traditional", true)
        case .functionalStrengthTraining: ("Functional strength", "figure.strengthtraining.functional", true)
        case .highIntensityIntervalTraining: ("HIIT", "figure.highintensity.intervaltraining", true)
        case .crossTraining: ("Cross training", "figure.cross.training", true)
        case .coreTraining: ("Core training", "figure.core.training", true)
        case .mixedCardio: ("Mixed cardio", "figure.mixed.cardio", true)
        case .running: (indoor ? "Indoor run" : "Run", "figure.run", false)
        case .walking: (indoor ? "Indoor walk" : "Walk", "figure.walk", false)
        case .hiking: ("Hike", "figure.hiking", false)
        case .cycling: (indoor ? "Indoor cycle" : "Cycling", indoor ? "figure.indoor.cycle" : "figure.outdoor.cycle", false)
        case .swimming: ("Swim", "figure.pool.swim", false)
        case .rowing: ("Rowing", "figure.rower", false)
        case .elliptical: ("Elliptical", "figure.elliptical", false)
        case .stairClimbing, .stairs: ("Stairs", "figure.stair.stepper", false)
        case .yoga: ("Yoga", "figure.yoga", false)
        case .soccer: ("Football", "figure.soccer", false)
        default: ("Workout", "figure.mixed.cardio", false)
        }
    }
}
