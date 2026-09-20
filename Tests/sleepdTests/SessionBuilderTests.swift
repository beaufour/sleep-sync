import Foundation
import XCTest
@testable import sleepd

final class SessionBuilderTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testGroupsAdjacentStagesAndCalculatesBounds() {
        let records = [
            record(stage: "asleepCore", startMinutes: 30, endMinutes: 90),
            record(stage: "inBed", startMinutes: 0, endMinutes: 30),
            record(stage: "asleepREM", startMinutes: 100, endMinutes: 120)
        ]

        let sessions = SessionBuilder.sessions(from: records)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].durationMinutes, 120)
        XCTAssertEqual(sessions[0].stages.map(\.stage), ["inBed", "asleepCore", "asleepREM"])
    }

    func testStartsNewSessionAtTwoHourGap() {
        let records = [
            record(stage: "asleepCore", startMinutes: 0, endMinutes: 60),
            record(stage: "asleepDeep", startMinutes: 180, endMinutes: 240)
        ]

        XCTAssertEqual(SessionBuilder.sessions(from: records).count, 2)
    }

    func testSeparatesOverlappingSources() {
        let records = [
            record(stage: "asleepCore", startMinutes: 0, endMinutes: 60, source: "Sleep Cycle"),
            record(stage: "asleepCore", startMinutes: 0, endMinutes: 60, source: "Apple Watch")
        ]

        let sessions = SessionBuilder.sessions(from: records)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(Set(sessions.map(\.source)), ["Sleep Cycle", "Apple Watch"])
    }

    private func record(
        stage: String,
        startMinutes: TimeInterval,
        endMinutes: TimeInterval,
        source: String = "Sleep Cycle"
    ) -> SleepSampleRecord {
        SleepSampleRecord(
            stage: stage,
            start: base.addingTimeInterval(startMinutes * 60),
            end: base.addingTimeInterval(endMinutes * 60),
            source: source
        )
    }
}
