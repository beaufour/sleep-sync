import Darwin
import Foundation

enum SleepdError: LocalizedError {
    case healthDataUnavailable
    case sleepTypeUnavailable
    case invalidArguments(String)
    case atomicRenameFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "HealthKit data is unavailable on macOS. Apple exposes the framework on macOS 13+, but does not provide a readable HealthKit store."
        case .sleepTypeUnavailable:
            "The HealthKit Sleep Analysis type is unavailable."
        case .invalidArguments(let message):
            message
        case .atomicRenameFailed(let message):
            message
        }
    }
}

struct Options {
    let outputURL: URL
    let watchMinutes: Int?

    static func parse(_ arguments: [String]) throws -> Options {
        var outputPath: String?
        var watchMinutes: Int?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--watch" {
                index += 1
                guard index < arguments.count,
                      let minutes = Int(arguments[index]),
                      minutes > 0 else {
                    throw SleepdError.invalidArguments("usage: sleepd [output-path] [--watch minutes]")
                }
                watchMinutes = minutes
            } else if argument.hasPrefix("--watch=") {
                let value = String(argument.dropFirst("--watch=".count))
                guard let minutes = Int(value), minutes > 0 else {
                    throw SleepdError.invalidArguments("--watch requires a positive number of minutes")
                }
                watchMinutes = minutes
            } else if argument.hasPrefix("-") {
                throw SleepdError.invalidArguments("unknown option: \(argument)")
            } else if outputPath == nil {
                outputPath = argument
            } else {
                throw SleepdError.invalidArguments("unexpected argument: \(argument)")
            }
            index += 1
        }

        let path = outputPath ?? "./sleep.json"
        return Options(
            outputURL: URL(fileURLWithPath: path).standardizedFileURL,
            watchMinutes: watchMinutes
        )
    }
}

enum JSONWriter {
    static func data(for sessions: [SleepSession]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(sessions)
        data.append(0x0A)
        return data
    }

    @discardableResult
    static func writeIfChanged(_ data: Data, to outputURL: URL) throws -> Bool {
        if (try? Data(contentsOf: outputURL)) == data {
            return false
        }

        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let temporaryURL = directory.appendingPathComponent(
            ".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporaryURL)
            guard rename(temporaryURL.path, outputURL.path) == 0 else {
                throw SleepdError.atomicRenameFailed(
                    "Could not atomically rename \(temporaryURL.path) to \(outputURL.path): \(String(cString: strerror(errno)))"
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        return true
    }
}

@main
struct Sleepd {
    static func main() async {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            let client = try HealthKitClient()
            try await client.requestAuthorization()

            repeat {
                let records = try await client.fetchSleepSamples()
                let sessions = SessionBuilder.sessions(from: records)
                let json = try JSONWriter.data(for: sessions)
                let changed = try JSONWriter.writeIfChanged(json, to: options.outputURL)
                print("sleepd: \(sessions.count) sessions, \(records.count) samples — \(changed ? "wrote" : "unchanged") \(options.outputURL.path)")

                guard let minutes = options.watchMinutes else { break }
                try await Task.sleep(for: .seconds(Double(minutes) * 60))
            } while !Task.isCancelled
        } catch {
            FileHandle.standardError.write(Data("sleepd: error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
