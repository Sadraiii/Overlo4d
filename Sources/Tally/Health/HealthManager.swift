import Foundation
import HealthKit
import Observation

/// Reads activity from Apple Health and saves finished workouts to it.
@MainActor
@Observable
final class HealthManager {
    struct Today: Equatable {
        var steps: Double?
        var activeEnergy: Double?
        var exerciseMinutes: Double?
    }

    /// Health data recorded during a workout (for example by an Apple Watch).
    struct WorkoutHealth: Equatable, Sendable {
        var activeEnergy: Double?
        var averageHeartRate: Double?
        var maxHeartRate: Double?

        var isEmpty: Bool { activeEnergy == nil && averageHeartRate == nil }
    }

    struct Weight: Identifiable, Equatable, Sendable {
        var id: Date { date }
        let date: Date
        let kg: Double
    }

    let isAvailable = HKHealthStore.isHealthDataAvailable()

    /// Whether the permission prompt has been shown. Read access itself can't be checked (by design of HealthKit).
    private(set) var isConnected = UserDefaults.standard.bool(forKey: "healthConnected")

    var savesWorkouts = UserDefaults.standard.object(forKey: "healthSavesWorkouts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(savesWorkouts, forKey: "healthSavesWorkouts") }
    }

    private(set) var today = Today()
    /// Body weight over the last 180 days, oldest first.
    private(set) var weights: [Weight] = []
    private var workoutHealth: [UUID: WorkoutHealth] = [:]
    /// Asked once per launch so types added in an update (e.g. distance) get their permission prompt.
    private var askedForNewTypes = false

    private let store = HKHealthStore()

    private static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyMass),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceSwimming),
    ]

    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
    ]

    func connect() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            isConnected = true
            UserDefaults.standard.set(true, forKey: "healthConnected")
            await refresh()
        } catch {
            // The user can retry from Settings.
        }
    }

    func refresh() async {
        guard isAvailable, isConnected else { return }
        if !askedForNewTypes {
            askedForNewTypes = true
            // HealthKit only shows the sheet for types it hasn't asked about before.
            try? await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        }
        let start = Calendar.current.startOfDay(for: .now)
        async let steps = Self.sum(.stepCount, unit: .count(), from: start, to: .now, store: store)
        async let energy = Self.sum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: .now, store: store)
        async let exercise = Self.sum(.appleExerciseTime, unit: .minute(), from: start, to: .now, store: store)
        async let weights = Self.weights(store: store)
        today = Today(steps: await steps, activeEnergy: await energy, exerciseMinutes: await exercise)
        self.weights = await weights
    }

    /// Energy and heart rate recorded between `start` and `end`, if Health has any. Cached by `key`.
    func health(from start: Date, to end: Date, key: UUID) async -> WorkoutHealth? {
        guard isAvailable, isConnected else { return nil }
        if let cached = workoutHealth[key] { return cached }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let energy = Self.sum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end, store: store)
        async let average = Self.statistic(.heartRate, option: .discreteAverage, unit: bpm, from: start, to: end, store: store)
        async let max = Self.statistic(.heartRate, option: .discreteMax, unit: bpm, from: start, to: end, store: store)
        let result = WorkoutHealth(activeEnergy: await energy, averageHeartRate: await average, maxHeartRate: await max)
        workoutHealth[key] = result
        return result
    }

    /// Energy and heart rate recorded between the workout's start and end, if Health has any.
    func health(for workout: Workout) async -> WorkoutHealth? {
        await health(from: workout.startedAt, to: workout.endedAt ?? .now, key: workout.id)
    }

    /// Workouts in Health since `start` that other apps (e.g. the Watch Workout app) recorded, newest first.
    func workouts(since start: Date) async -> [HealthWorkout] {
        guard isAvailable, isConnected else { return [] }
        return await Self.workouts(since: start, store: store)
    }

    // Replaced in Task 8.
    func deleteWorkout(_ id: UUID) async -> Bool { false }

    /// Saves a finished workout to Health as strength training.
    func save(_ workout: Workout) async {
        guard isAvailable, isConnected, savesWorkouts, workout.endedAt != nil else { return }
        if weights.isEmpty { weights = await Self.weights(store: store) }
        await Self.saveWorkout(workout, bodyMass: weights.last?.kg, store: store)
        workoutHealth[workout.id] = nil
    }

    // MARK: Queries

    private nonisolated static func sum(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date, store: HKHealthStore
    ) async -> Double? {
        await statistic(id, option: .cumulativeSum, unit: unit, from: start, to: end, store: store)
    }

    private nonisolated static func statistic(
        _ id: HKQuantityTypeIdentifier, option: HKStatisticsOptions, unit: HKUnit,
        from start: Date, to end: Date, store: HKHealthStore
    ) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: option
        )
        guard let statistics = try? await descriptor.result(for: store) else { return nil }
        let quantity: HKQuantity? = switch option {
        case .cumulativeSum: statistics.sumQuantity()
        case .discreteAverage: statistics.averageQuantity()
        case .discreteMax: statistics.maximumQuantity()
        default: nil
        }
        return quantity?.doubleValue(for: unit)
    }

    private nonisolated static func workouts(since start: Date, store: HKHealthStore) async -> [HealthWorkout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let own = HKSource.default()
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.filter { $0.sourceRevision.source != own }.map(HealthWorkout.init)
    }

    private nonisolated static func weights(store: HKHealthStore) async -> [Weight] {
        let since = Calendar.current.date(byAdding: .day, value: -180, to: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.bodyMass),
                predicate: HKQuery.predicateForSamples(withStart: since, end: nil)
            )],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { Weight(date: $0.endDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    private nonisolated static func saveWorkout(_ workout: Workout, bodyMass: Double?, store: HKHealthStore) async {
        guard let end = workout.endedAt else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: workout.startedAt)
            // Only estimate energy when nothing else (e.g. an Apple Watch) measured it, so rings aren't counted twice.
            let measured = await sum(.activeEnergyBurned, unit: .kilocalorie(), from: workout.startedAt, to: end, store: store) ?? 0
            if measured < 1, let bodyMass {
                // MET 5.0 for vigorous strength training: kcal = MET × kg × hours.
                let kcal = 5.0 * bodyMass * workout.duration / 3600
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: workout.startedAt,
                    end: end
                )
                try await builder.addSamples([sample])
            }
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: workout.id.uuidString,
                HKMetadataKeyWorkoutBrandName: "Tally",
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
        }
    }
}
