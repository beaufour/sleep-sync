import Foundation

struct SleepStage: Codable, Equatable {
    let stage: String
    let start: String
    let end: String
}

struct SleepSession: Codable, Equatable {
    let bedStart: String
    let wakeEnd: String
    let durationMinutes: Int
    let stages: [SleepStage]
    let source: String

    enum CodingKeys: String, CodingKey {
        case bedStart = "bed_start"
        case wakeEnd = "wake_end"
        case durationMinutes = "duration_minutes"
        case stages
        case source
    }
}

struct SleepSampleRecord: Equatable {
    let stage: String
    let start: Date
    let end: Date
    let source: String
}

enum SessionBuilder {
    static let maximumGap: TimeInterval = 2 * 60 * 60

    static func sessions(from records: [SleepSampleRecord]) -> [SleepSession] {
        let bySource = Dictionary(grouping: records, by: \.source)
        var datedSessions: [(end: Date, session: SleepSession)] = []

        for (source, sourceRecords) in bySource {
            let sorted = sourceRecords.sorted {
                if $0.start == $1.start {
                    if $0.end == $1.end { return $0.stage < $1.stage }
                    return $0.end < $1.end
                }
                return $0.start < $1.start
            }

            var current: [SleepSampleRecord] = []
            var currentEnd: Date?

            for record in sorted {
                if let end = currentEnd,
                   record.start.timeIntervalSince(end) >= maximumGap {
                    datedSessions.append(makeSession(from: current, source: source))
                    current = []
                    currentEnd = nil
                }

                current.append(record)
                currentEnd = max(currentEnd ?? record.end, record.end)
            }

            if !current.isEmpty {
                datedSessions.append(makeSession(from: current, source: source))
            }
        }

        return datedSessions
            .sorted {
                if $0.end == $1.end { return $0.session.source < $1.session.source }
                return $0.end > $1.end
            }
            .map(\.session)
    }

    private static func makeSession(
        from records: [SleepSampleRecord],
        source: String
    ) -> (end: Date, session: SleepSession) {
        let start = records.map(\.start).min()!
        let end = records.map(\.end).max()!
        let stages = records.map {
            SleepStage(
                stage: $0.stage,
                start: ISO8601.string(from: $0.start),
                end: ISO8601.string(from: $0.end)
            )
        }

        return (
            end,
            SleepSession(
                bedStart: ISO8601.string(from: start),
                wakeEnd: ISO8601.string(from: end),
                durationMinutes: Int(end.timeIntervalSince(start) / 60),
                stages: stages,
                source: source
            )
        )
    }
}

enum ISO8601 {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
