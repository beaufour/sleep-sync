import Foundation
import HealthKit

final class HealthKitClient: @unchecked Sendable {
    private let store = HKHealthStore()
    private let sleepType: HKCategoryType

    init() throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SleepdError.healthDataUnavailable
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw SleepdError.sleepTypeUnavailable
        }
        self.sleepType = sleepType
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    func fetchSleepSamples(now: Date = Date()) async throws -> [SleepSampleRecord] {
        let start = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: [.strictStartDate, .strictEndDate]
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        return samples.map {
            SleepSampleRecord(
                stage: Self.stageName(for: $0.value),
                start: $0.startDate,
                end: $0.endDate,
                source: $0.sourceRevision.source.name
            )
        }
    }

    private static func stageName(for value: Int) -> String {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: "inBed"
        case .asleepUnspecified: "asleepUnspecified"
        case .awake: "awake"
        case .asleepCore: "asleepCore"
        case .asleepDeep: "asleepDeep"
        case .asleepREM: "asleepREM"
        default: "unknown(\(value))"
        }
    }
}
