import Foundation
import HealthKit
import Combine

// MARK: - HealthKitManager

final class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()

    // MARK: - Published

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: [String: HKAuthorizationStatus] = [:]

    // Latest recovery metrics
    @Published var latestSleepHours: Double?
    @Published var latestSpO2Avg: Double?
    @Published var latestRestingHR: Int?
    @Published var latestHRVAvg: Int?
    @Published var latestVo2Max: Double?

    @Published var moveCalories: Double = 0
    @Published var moveGoal: Double = 500
    @Published var exerciseMinutes: Double = 0
    @Published var exerciseGoal: Double = 30
    @Published var standHours: Double = 0
    @Published var standGoal: Double = 12
    @Published var recentWorkouts: [SyncedWorkout] = []
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false

    // MARK: - HealthKit Store

    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var backgroundDeliveryEnabled = false

    // MARK: - Types to Read

    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []

        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(spo2)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        if let vo2Max = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            types.insert(vo2Max)
        }
        types.insert(HKObjectType.workoutType())
        types.insert(HKObjectType.activitySummaryType())
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let cycling = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            types.insert(cycling)
        }
        if let exerciseTime = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseTime)
        }
        if let stand = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            types.insert(stand)
        }

        return types
    }()

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)

        await MainActor.run {
            isAuthorized = true
            updateAuthorizationStatus()
        }

        // Enable background delivery
        try await enableBackgroundDelivery()
    }

    private func updateAuthorizationStatus() {
        for type in readTypes {
            let status = healthStore.authorizationStatus(for: type)
            let key = type.identifier
            authorizationStatus[key] = status
        }
    }

    // MARK: - Background Delivery

    private func enableBackgroundDelivery() async throws {
        guard !backgroundDeliveryEnabled else { return }

        // Background delivery is not fully supported on iOS Simulator
        #if targetEnvironment(simulator)
        print("HealthKit: Skipping background delivery on simulator")
        backgroundDeliveryEnabled = true
        return
        #else
        for type in readTypes {
            guard let sampleType = type as? HKSampleType else { continue }

            do {
                try await healthStore.enableBackgroundDelivery(
                    for: sampleType,
                    frequency: .immediate
                )
            } catch {
                // Some types don't support background delivery — skip them
                print("HealthKit: Background delivery not supported for \(sampleType.identifier): \(error.localizedDescription)")
            }
        }

        backgroundDeliveryEnabled = true
        setupObserverQueries()
        #endif
    }

    private func setupObserverQueries() {
        // Observer queries fire when new health data arrives
        for type in readTypes {
            guard let sampleType = type as? HKSampleType else { continue }

            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                if let error = error {
                    print("HKObserverQuery error: \(error.localizedDescription)")
                    completionHandler()
                    return
                }

                // New data arrived — sync it
                self?.syncNewData(for: type)

                completionHandler()
            }

            healthStore.execute(query)
            observerQueries.append(query)
        }
    }

    private func syncNewData(for type: HKObjectType) {
        if type == HKObjectType.workoutType() {
            Task { await syncAllToBackend() }
            return
        }

        guard let quantityType = type as? HKQuantityType else { return }

        switch quantityType.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            Task { await fetchLatestHeartRate() }
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            Task { await fetchLatestHRV() }
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            Task { await fetchLatestRestingHR() }
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            Task { await fetchLatestSpO2() }
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            Task { await fetchLatestVo2Max() }
        default:
            break
        }
    }

    // MARK: - Fetch Latest Metrics

    func fetchLatestHeartRate() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestRestingHR = Int(metric)
            }
        }
    }

    func fetchLatestHRV() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestHRVAvg = Int(metric)
            }
        }
    }

    func fetchLatestRestingHR() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestRestingHR = Int(metric)
            }
        }
    }

    func fetchLatestSpO2() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestSpO2Avg = metric
            }
        }
    }

    func fetchLatestVo2Max() async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return }
        let metric = await fetchLatestQuantity(type)
        if let metric = metric {
            await MainActor.run {
                self.latestVo2Max = metric
            }
        }
    }

    private func fetchLatestQuantity(_ type: HKQuantityType) async -> Double? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-86400), // last 24 hours
            end: Date(),
            options: .strictStartDate
        )

        let hkUnit = unit(for: type)
        let store = healthStore
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil,
                      let sample = samples?.first as? HKQuantity else {
                    continuation.resume(returning: nil)
                    return
                }

                let value = sample.doubleValue(for: hkUnit)
                continuation.resume(returning: value)
            }

            store.execute(query)
        }
    }

    private func unit(for type: HKQuantityType) -> HKUnit {
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return .secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return .count().unitDivided(by: .count())
        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            return .literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .second().unitMultiplied(by: .minute())))
        default:
            return .count()
        }
    }

    // MARK: - Sleep Data

    func fetchSleepData(for date: Date) async -> SleepData? {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        let store = healthStore
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard error == nil, let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                var totalSleep: TimeInterval = 0
                var deepSleep: TimeInterval = 0
                var remSleep: TimeInterval = 0
                var awake: TimeInterval = 0

                for sample in samples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        totalSleep += duration
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        totalSleep += duration
                        deepSleep += duration
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        totalSleep += duration
                        remSleep += duration
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += duration
                    default:
                        break
                    }
                }

                let result = SleepData(
                    totalHours: totalSleep / 3600,
                    deepHours: deepSleep / 3600,
                    remHours: remSleep / 3600,
                    awakeMinutes: Int(awake / 60)
                )
                continuation.resume(returning: result)
            }

            store.execute(query)
        }
    }

    // MARK: - Recovery Metrics Sync

    func syncRecoveryMetrics(athleteId: String, sessionId: String?, for date: Date) async {
        let sleep = await fetchSleepData(for: date)

        await fetchLatestHeartRate()
        await fetchLatestHRV()
        await fetchLatestRestingHR()
        await fetchLatestSpO2()
        await fetchLatestVo2Max()

        await MainActor.run {
            self.latestSleepHours = sleep?.totalHours
            let recoveryScore = Self.computeRecoveryScore(
                hrv: self.latestHRVAvg ?? 50,
                restingHR: self.latestRestingHR ?? 70,
                sleepHours: sleep?.totalHours ?? 0
            )
            let fatigueScore = Self.computeFatigueScore(
                sleepHours: sleep?.totalHours ?? 0,
                restingHR: self.latestRestingHR ?? 70,
                hrv: self.latestHRVAvg ?? 50
            )
            let readinessScore = Self.computeReadinessScore(
                recoveryScore: recoveryScore,
                fatigueScore: fatigueScore
            )

            // Send to backend
            BackendSyncService.shared.syncRecoveryMetrics(
                athleteId: athleteId,
                sessionId: sessionId,
                date: date,
                sleepHours: sleep?.totalHours,
                sleepDeepHours: sleep?.deepHours,
                sleepRemHours: sleep?.remHours,
                sleepAwakeMinutes: sleep?.awakeMinutes,
                spo2Avg: self.latestSpO2Avg,
                spo2Min: nil,
                restingHR: self.latestRestingHR,
                hrvAvg: self.latestHRVAvg,
                vo2Max: self.latestVo2Max,
                recoveryScore: recoveryScore,
                fatigueScore: fatigueScore,
                readinessScore: readinessScore
            )
        }
    }

    // MARK: - Score Calculations

    private static func computeRecoveryScore(hrv: Int, restingHR: Int, sleepHours: Double) -> Double {
        // Simple baseline recovery score (0-100)
        // HRV contribution: higher is better (normalized to 0-50 range)
        let hrvScore = min(Double(hrv) / 100.0 * 50, 50)
        // Resting HR contribution: lower is better
        let hrScore = max(0, (80 - Double(restingHR)) / 80.0 * 25)
        // Sleep contribution: 7-9 hours is optimal
        let optimalSleep = min(sleepHours, 9) / 9.0
        let sleepScore = optimalSleep * 25

        return min(hrvScore + hrScore + sleepScore, 100)
    }

    private static func computeFatigueScore(sleepHours: Double, restingHR: Int, hrv: Int) -> Double {
        // Fatigue is inverse of recovery
        let recovery = computeRecoveryScore(hrv: hrv, restingHR: restingHR, sleepHours: sleepHours)
        return 100 - recovery
    }

    private static func computeReadinessScore(recoveryScore: Double, fatigueScore: Double) -> Double {
        return (recoveryScore + (100 - fatigueScore)) / 2.0
    }

    // MARK: - Background Task

    func scheduleBackgroundRefresh(athleteId: String) {
        // Periodic HealthKit sync is driven by observer queries.
    }

    // MARK: - Apple Workout + Activity Rings → backend

    func syncAllToBackend() async {
        let membership = TeamMembershipStore.shared
        await MainActor.run { isSyncing = true }
        await fetchTodayActivityRings()
        await fetchRecentWorkouts()
        await syncRecoveryMetrics(athleteId: membership.athleteId, sessionId: nil, for: Date())

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let move = await MainActor.run { moveCalories }
        let moveG = await MainActor.run { moveGoal }
        let ex = await MainActor.run { exerciseMinutes }
        let exG = await MainActor.run { exerciseGoal }
        let stand = await MainActor.run { standHours }
        let standG = await MainActor.run { standGoal }
        let workouts = await MainActor.run { recentWorkouts }

        await BackendSyncService.shared.syncActivityRings([
            "athlete_id": membership.athleteId,
            "date": dateFormatter.string(from: Date()),
            "move_kcal": move,
            "move_goal": moveG,
            "exercise_min": ex,
            "exercise_goal": exG,
            "stand_hours": stand,
            "stand_goal": standG,
        ])

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        for workout in workouts {
            var payload: [String: Any] = [
                "athlete_id": membership.athleteId,
                "healthkit_uuid": workout.uuid,
                "workout_type": workout.activityType,
                "started_at": iso.string(from: workout.start),
                "ended_at": iso.string(from: workout.end),
                "duration_seconds": Int(workout.duration),
                "total_calories": workout.calories,
                "total_distance": workout.distanceMeters,
            ]
            if let avg = workout.avgHeartRate { payload["avg_hr"] = avg }
            if let maxHR = workout.maxHeartRate { payload["max_hr"] = maxHR }
            await BackendSyncService.shared.syncHealthKitWorkout(payload)
        }

        await MainActor.run {
            isSyncing = false
            lastSyncDate = Date()
            TeamMembershipStore.shared.lastWorkoutSyncDate = Date()
        }
    }

    func fetchTodayActivityRings() async {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.era, .year, .month, .day], from: Date())
        components.calendar = calendar
        let predicate = HKQuery.predicateForActivitySummaries(with: components)
        let store = healthStore

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish = {
                if !resumed {
                    resumed = true
                    continuation.resume()
                }
            }
            let query = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, _ in
                guard let summary = summaries?.first else {
                    finish()
                    return
                }
                let energy = HKUnit.kilocalorie()
                let count = HKUnit.count()
                Task { @MainActor in
                    self?.moveCalories = summary.activeEnergyBurned.doubleValue(for: energy)
                    self?.moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: energy)
                    self?.exerciseMinutes = summary.appleExerciseTime.doubleValue(for: HKUnit.minute())
                    self?.exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: HKUnit.minute())
                    self?.standHours = summary.appleStandHours.doubleValue(for: count)
                    self?.standGoal = summary.appleStandHoursGoal.doubleValue(for: count)
                    finish()
                }
            }
            store.execute(query)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                finish()
            }
        }
    }

    func fetchRecentWorkouts() async {
        let workoutType = HKObjectType.workoutType()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let store = healthStore
        let energy = HKUnit.kilocalorie()
        let meter = HKUnit.meter()
        let bpm = HKUnit.count().unitDivided(by: .minute())

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 20,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        var mapped: [SyncedWorkout] = []
        for workout in workouts {
            var avgHR: Int?
            var maxHR: Int?
            if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
               let stats = workout.statistics(for: hrType) {
                if let avg = stats.averageQuantity() {
                    avgHR = Int(avg.doubleValue(for: bpm).rounded())
                }
                if let mx = stats.maximumQuantity() {
                    maxHR = Int(mx.doubleValue(for: bpm).rounded())
                }
            }
            mapped.append(
                SyncedWorkout(
                    uuid: workout.uuid.uuidString,
                    activityType: Self.activityName(workout.workoutActivityType),
                    start: workout.startDate,
                    end: workout.endDate,
                    duration: workout.duration,
                    calories: workout.totalEnergyBurned?.doubleValue(for: energy) ?? 0,
                    distanceMeters: workout.totalDistance?.doubleValue(for: meter) ?? 0,
                    avgHeartRate: avgHR,
                    maxHeartRate: maxHR
                )
            )
        }

        await MainActor.run {
            self.recentWorkouts = mapped
        }
    }

    private static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .cycling: return "cycling"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .hiking: return "hiking"
        case .walking: return "walking"
        case .yoga: return "yoga"
        case .mixedCardio: return "cardio"
        default: return "workout"
        }
    }
}

// MARK: - Supporting Types

struct SleepData {
    let totalHours: Double
    let deepHours: Double
    let remHours: Double
    let awakeMinutes: Int
}

struct SyncedWorkout: Identifiable {
    let uuid: String
    let activityType: String
    let start: Date
    let end: Date
    let duration: TimeInterval
    let calories: Double
    let distanceMeters: Double
    let avgHeartRate: Int?
    let maxHeartRate: Int?

    var id: String { uuid }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .notAuthorized:
            return "HealthKit access was not authorized."
        }
    }
}
