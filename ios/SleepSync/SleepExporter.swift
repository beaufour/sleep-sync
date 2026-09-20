import Foundation
import HealthKit

enum SleepExportError: LocalizedError {
    case healthDataUnavailable
    case sleepTypeUnavailable
    case outputFolderUnavailable
    case coordinatedWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "HealthKit data is unavailable on this device."
        case .sleepTypeUnavailable:
            "The HealthKit Sleep Analysis type is unavailable."
        case .outputFolderUnavailable:
            "The selected output folder is unavailable. Choose it again in Sleep Sync."
        case .coordinatedWriteFailed(let message):
            "Could not write sleep.json: \(message)"
        }
    }
}

@MainActor
final class SleepExporter: ObservableObject {
    static let shared = SleepExporter()
    private static let outputFolderBookmarkKey = "outputFolderBookmark"

    @Published private(set) var status = "Ready"
    @Published private(set) var sampleCount = 0
    @Published private(set) var sessionCount = 0
    @Published private(set) var lastExport: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isWorking = false
    @Published private(set) var hasOutputFolder = false
    @Published private(set) var outputFolderName = "Not selected"

    private let healthStore = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    private init() {
        if let url = try? resolvedOutputFolder() {
            hasOutputFolder = true
            outputFolderName = url.lastPathComponent
        }
    }

    private var sleepType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
    }

    func requestAuthorizationAndExport() async {
        guard !isWorking else { return }

        do {
            guard HKHealthStore.isHealthDataAvailable() else {
                throw SleepExportError.healthDataUnavailable
            }
            guard let sleepType else {
                throw SleepExportError.sleepTypeUnavailable
            }

            status = "Requesting Health access…"
            isWorking = true
            lastError = nil
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            isWorking = false

            try await startBackgroundObservation()
            await export(reason: "authorization")
        } catch {
            record(error)
        }
    }

    func resumeBackgroundObservation() async {
        guard HKHealthStore.isHealthDataAvailable(), sleepType != nil else { return }
        do {
            try await startBackgroundObservation()
        } catch {
            // First launch may occur before the user grants Health access. The
            // foreground authorization flow will register observation again.
        }
    }

    func export(reason: String) async {
        guard !isWorking else { return }

        guard hasOutputFolder else {
            status = "Choose an output folder"
            return
        }

        do {
            guard HKHealthStore.isHealthDataAvailable() else {
                throw SleepExportError.healthDataUnavailable
            }
            guard let sleepType else {
                throw SleepExportError.sleepTypeUnavailable
            }

            isWorking = true
            lastError = nil
            status = "Reading HealthKit…"

            let records = try await fetchSleepSamples(type: sleepType)
            let sessions = SessionBuilder.sessions(from: records)
            let data = try encode(sessions)

            status = "Writing sleep.json…"
            try writeOutput(data)

            sampleCount = records.count
            sessionCount = sessions.count
            lastExport = Date()
            status = "Synced (\(reason))"
            isWorking = false
        } catch {
            record(error)
        }
    }

    func handleFolderSelection(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess { url.stopAccessingSecurityScopedResource() }
            }

            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.outputFolderBookmarkKey)
            hasOutputFolder = true
            outputFolderName = url.lastPathComponent
            lastError = nil
            await export(reason: "output folder selected")
        } catch {
            record(error)
        }
    }

    private func startBackgroundObservation() async throws {
        guard observerQuery == nil else { return }
        guard let sleepType else {
            throw SleepExportError.sleepTypeUnavailable
        }

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) {
            [weak self] _, completion, error in
            guard error == nil else {
                completion()
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    completion()
                    return
                }
                await self.export(reason: "HealthKit update")
                completion()
            }
        }

        observerQuery = query
        healthStore.execute(query)

        do {
            try await healthStore.enableBackgroundDelivery(
                for: sleepType,
                frequency: .immediate
            )
        } catch {
            healthStore.stop(query)
            observerQuery = nil
            throw error
        }
    }

    private func fetchSleepSamples(type: HKCategoryType) async throws -> [SleepSampleRecord] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: [.strictStartDate, .strictEndDate]
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
            }
            healthStore.execute(query)
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

    private func encode(_ sessions: [SleepSession]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(sessions)
        data.append(0x0A)
        return data
    }

    private func writeOutput(_ data: Data) throws {
        let folder = try resolvedOutputFolder()
        let canAccess = folder.startAccessingSecurityScopedResource()
        defer {
            if canAccess { folder.stopAccessingSecurityScopedResource() }
        }
        let output = folder.appendingPathComponent("sleep.json")

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: output,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                if (try? Data(contentsOf: coordinatedURL)) != data {
                    try data.write(to: coordinatedURL, options: .atomic)
                }
            } catch {
                writeError = error
            }
        }

        if let error = coordinationError ?? writeError as NSError? {
            throw SleepExportError.coordinatedWriteFailed(error.localizedDescription)
        }
    }

    private func resolvedOutputFolder() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(
            forKey: Self.outputFolderBookmarkKey
        ) else {
            throw SleepExportError.outputFolderUnavailable
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            let refreshed = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(refreshed, forKey: Self.outputFolderBookmarkKey)
        }
        return url
    }

    private func record(_ error: Error) {
        isWorking = false
        status = "Export failed"
        lastError = error.localizedDescription
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
