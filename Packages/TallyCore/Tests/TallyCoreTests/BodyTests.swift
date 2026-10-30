import Foundation
import Testing
@testable import TallyCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ text: String) -> DayKey { DayKey(rawValue: text) }

private func date(_ text: String) -> Date {
    try! Date(text + "Z", strategy: .iso8601)
}

@Suite struct BodyTests {
    @Test func loggingTheSameDayMergesAndDropsTypos() {
        var log = BodyLog()
        log.log([.waist: 84.04, .chest: 101], on: day("2026-10-01"))
        log.log([.waist: 83.5, .leftArm: 900], note: "Morning", on: day("2026-10-01"))
        #expect(log.entries.count == 1)
        #expect(log.entries[0].values == [.waist: 83.5, .chest: 101])
        #expect(log.entries[0].note == "Morning")

        log.log([:], on: day("2026-10-02"))
        #expect(log.entries.count == 1)
    }

    @Test func entriesStaySortedAndReplaceClearsValues() throws {
        var log = BodyLog()
        log.log([.waist: 82], on: day("2026-10-10"))
        log.log([.waist: 84, .hips: 99], on: day("2026-10-01"))
        #expect(log.entries.map(\.day) == [day("2026-10-01"), day("2026-10-10")])

        var first = log.entries[0]
        first.values[.hips] = nil
        log.replace(first)
        #expect(log.entries[0].values == [.waist: 84])

        first.values = [:]
        log.replace(first)
        #expect(log.entries.map(\.day) == [day("2026-10-10")])
    }

    @Test func roundTripsThroughJSON() throws {
        var log = BodyLog()
        log.log([.bodyFat: 18.5, .rightCalf: 38], note: "After cut", on: day("2026-10-01"))
        log.add(ProgressPhoto(day: day("2026-10-01"), pose: .side))
        log.tracked = [.waist, .bodyFat]
        let decoded = try JSONDecoder().decode(BodyLog.self, from: JSONEncoder().encode(log))
        #expect(decoded == log)

        let json = String(decoding: try JSONEncoder().encode(log), as: UTF8.self)
        #expect(json.contains("\"bodyFat\""))
    }

    @Test func oldOrPartialFilesDecode() throws {
        let decoded = try JSONDecoder().decode(BodyLog.self, from: Data("{}".utf8))
        #expect(decoded.entries.isEmpty)
        #expect(decoded.tracked == BodyMeasure.defaults)

        let future = """
        {"entries":[{"id":"9F1C2B9E-0000-4000-8000-000000000001","day":"2026-10-01","values":{"waist":80,"wrist":17}}],"tracked":["waist","wrist"]}
        """
        let log = try JSONDecoder().decode(BodyLog.self, from: Data(future.utf8))
        #expect(log.entries[0].values == [.waist: 80])
        #expect(log.tracked == [.waist])
    }

    @Test func healthFillsGapsButLoggedValuesWin() {
        var log = BodyLog()
        log.log([.waist: 84], on: day("2026-10-01"))
        let merged = BodyLog.merge(log.entries, health: [
            (.waist, date("2026-10-01T08:00:00"), 86),
            (.bodyFat, date("2026-10-01T08:00:00"), 20),
            (.bodyFat, date("2026-10-03T07:00:00"), 19.5),
            (.bodyFat, date("2026-10-03T21:00:00"), 19.8),
            (.bodyFat, date("2026-10-04T07:00:00"), 0.2),
        ], calendar: utc)
        #expect(merged.count == 2)
        #expect(merged[0].values == [.waist: 84, .bodyFat: 20])
        #expect(!merged[0].fromHealth)
        #expect(merged[1].day == day("2026-10-03"))
        #expect(merged[1].values == [.bodyFat: 19.8])
        #expect(merged[1].fromHealth)
    }

    @Test func nearestReadingPrefersEarlierOnTies() {
        var log = BodyLog()
        log.log([.waist: 90], on: day("2026-09-28"))
        log.log([.waist: 88], on: day("2026-10-04"))
        let near = BodyLog.value(.waist, near: day("2026-10-01"), in: log.entries, calendar: utc)
        #expect(near == 90)
        #expect(BodyLog.value(.waist, near: day("2026-10-03"), in: log.entries, calendar: utc) == 88)
        #expect(BodyLog.value(.waist, near: day("2026-12-01"), in: log.entries, calendar: utc) == nil)
    }

    @Test func comparesWeightAndMeasurementsNearPhotoDays() throws {
        var log = BodyLog()
        log.log([.waist: 90, .leftArm: 35], on: day("2026-07-01"))
        log.log([.waist: 84, .leftArm: 36.5, .chest: 100], on: day("2026-09-28"))
        let weights = [
            WeightPoint(day: day("2026-07-03"), kg: 88),
            WeightPoint(day: day("2026-10-01"), kg: 82.4),
        ]
        let rows = BodyLog.changes(from: day("2026-07-01"), to: day("2026-10-01"), entries: log.entries, weights: weights, calendar: utc)
        #expect(rows.map(\.name) == ["Weight", "Waist", "Left arm"])
        let waist = try #require(rows.first { $0.name == "Waist" })
        #expect(waist.delta == -6)
        #expect(waist.isProgress == true)
        #expect(rows[0].isProgress == nil)
        #expect(rows[2].isProgress == nil)
        #expect(abs(rows[0].delta - -5.6) < 0.001)
    }

    @Test func photoDaysAndDefaultComparison() {
        var log = BodyLog()
        #expect(log.defaultComparison(.front) == nil)
        log.add(ProgressPhoto(day: day("2026-10-01"), pose: .front))
        log.add(ProgressPhoto(day: day("2026-10-01"), pose: .back))
        log.add(ProgressPhoto(day: day("2026-08-01"), pose: .front))
        log.add(ProgressPhoto(day: day("2026-09-01"), pose: .front))
        #expect(log.photoDays == [day("2026-10-01"), day("2026-09-01"), day("2026-08-01")])
        #expect(log.photos(on: day("2026-10-01")).map(\.pose) == [.front, .back])
        let pair = log.defaultComparison(.front)
        #expect(pair?.from == day("2026-08-01"))
        #expect(pair?.to == day("2026-10-01"))
        #expect(log.defaultComparison(.back) == nil)
        #expect(log.bestComparisonPose == .front)

        let removed = log.deletePhoto(log.photos[0].id)
        #expect(removed?.day == day("2026-08-01"))
        #expect(log.photos.count == 3)
    }

    @Test func coachLinesShowRecentAndTotalChange() {
        var log = BodyLog()
        log.log([.waist: 92], on: day("2026-07-01"))
        log.log([.waist: 88], on: day("2026-09-20"))
        log.log([.waist: 86.5], on: day("2026-10-28"))
        log.log([.chest: 100], on: day("2026-10-28"))
        log.add(ProgressPhoto(day: day("2026-07-01"), pose: .front))
        log.add(ProgressPhoto(day: day("2026-10-28"), pose: .front))
        let lines = BodyLog.coachLines(entries: log.entries, photos: log.photos, today: day("2026-10-30"), calendar: utc)
        #expect(lines == [
            "Chest: 100 cm on 2026-10-28",
            "Waist: 86.5 cm on 2026-10-28, -1.5 since 2026-09-20, -5.5 since the first on 2026-07-01",
            "Progress photos: 2 days from 2026-07-01 to 2026-10-28 (you can't see them).",
        ])
    }

    @Test func daysBetween() {
        #expect(day("2026-10-01").days(to: day("2026-10-30"), calendar: utc) == 29)
        #expect(day("2026-10-30").days(to: day("2026-10-01"), calendar: utc) == -29)
    }
}
