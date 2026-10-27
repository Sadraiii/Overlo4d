import Foundation
import HealthKit
import Observation
import TallyCore

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
        HKCategoryType(.sleepAnalysis),
    ]

    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.bodyMass),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryFatTotal),
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

    /// Deletes a workout Tally saved, with the energy sample Tally added to it. True when it's gone.
    func deleteWorkout(_ id: UUID) async -> Bool {
        guard isAvailable, isConnected else { return false }
        return await Self.deleteWorkout(id: id, store: store)
    }

    /// Saves a finished workout to Health as strength training. Returns the saved workout's UUID.
    func save(_ workout: Workout) async -> UUID? {
        guard isAvailable, isConnected, savesWorkouts, workout.endedAt != nil else { return nil }
        if weights.isEmpty { weights = await Self.weights(store: store) }
        let id = await Self.saveWorkout(workout, bodyMass: weights.last?.kg, store: store)
        workoutHealth[workout.id] = nil
        return id
    }

    /// Sleep samples from every source (Watch, iPhone, other apps) since `start`.
    func sleepSegments(since start: Date) async -> [SleepSegment] {
        guard isAvailable, isConnected else { return [] }
        return await Self.sleepSegments(since: start, store: store)
    }

    /// Saves each entry's calories and macros, tagged with the entry's ID so they can be removed later.
    func saveFood(_ entries: [FoodEntry]) async {
        guard isAvailable, isConnected, !entries.isEmpty else { return }
        let items = entries.map { FoodSample(id: $0.id.uuidString, name: $0.food.name, date: $0.healthDate, nutrients: $0.nutrients) }
        await Self.saveFood(items, store: store)
    }

    /// Removes what `saveFood` saved for these entries.
    func deleteFood(_ ids: [UUID]) async {
        guard isAvailable, isConnected, !ids.isEmpty else { return }
        await Self.deleteFood(ids.map(\.uuidString), store: store)
    }

    /// Saves a body weight reading and adds it to `weights`.
    func saveWeight(_ kg: Double, date: Date) async {
        guard isAvailable, isConnected, await Self.saveWeight(kg, date: date, store: store) else { return }
        weights = (weights + [Weight(date: date, kg: kg)]).sorted { $0.date < $1.date }
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

    private nonisolated static func sleepSegments(since start: Date, store: HKHealthStore) async -> [SleepSegment] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: start, end: nil)
            )],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.compactMap { sample in
            let stage: SleepStage? = switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed: .inBed
            case .awake: .awake
            case .asleepCore: .core
            case .asleepDeep: .deep
            case .asleepREM: .rem
            case .asleepUnspecified: .asleep
            default: nil
            }
            return stage.map { SleepSegment(start: sample.startDate, end: sample.endDate, stage: $0) }
        }
    }

    struct FoodSample: Sendable {
        let id: String
        let name: String
        let date: Date
        let nutrients: Nutrients
    }

    /// Food is saved as one sample per nutrient: energy, carbs, protein and fat.
    private nonisolated static func foodQuantities(_ nutrients: Nutrients) -> [(HKQuantityTypeIdentifier, HKUnit, Double)] {
        [
            (.dietaryEnergyConsumed, .kilocalorie(), nutrients.kcal),
            (.dietaryCarbohydrates, .gram(), nutrients.carbs),
            (.dietaryProtein, .gram(), nutrients.protein),
            (.dietaryFatTotal, .gram(), nutrients.fat),
        ]
    }

    private nonisolated static func saveFood(_ items: [FoodSample], store: HKHealthStore) async {
        var samples: [HKQuantitySample] = []
        for item in items {
            let metadata: [String: Any] = [HKMetadataKeyExternalUUID: item.id, HKMetadataKeyFoodType: item.name]
            for (id, unit, value) in foodQuantities(item.nutrients) where value > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(id),
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: item.date,
                    end: item.date,
                    metadata: metadata
                ))
            }
        }
        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    private nonisolated static func deleteFood(_ ids: [String], store: HKHealthStore) async {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: ids)
        for (id, _, _) in foodQuantities(.zero) {
            // Fails with "no data" when nothing was saved for these entries, which is fine.
            _ = try? await store.deleteObjects(of: HKQuantityType(id), predicate: predicate)
        }
    }

    private nonisolated static func saveWeight(_ kg: Double, date: Date, store: HKHealthStore) async -> Bool {
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date,
            end: date
        )
        return (try? await store.save(sample)) != nil
    }

    private nonisolated static func deleteWorkout(id: UUID, store: HKHealthStore) async -> Bool {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store) else { return false }
        guard let workout = samples.first else { return true }
        do {
            // Fails with "no data" when Tally added no energy (the Watch measured it), which is fine.
            _ = try? await store.deleteObjects(
                of: HKQuantityType(.activeEnergyBurned),
                predicate: HKQuery.predicateForObjects(from: workout)
            )
            try await store.delete(workout)
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func saveWorkout(_ workout: Workout, bodyMass: Double?, store: HKHealthStore) async -> UUID? {
        guard let end = workout.endedAt else { return nil }
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
                HKMetadataKeyWorkoutBrandName: "Overload",
            ])
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout()?.uuid
        } catch {
            builder.discardWorkout()
            return nil
        }
    }
}
