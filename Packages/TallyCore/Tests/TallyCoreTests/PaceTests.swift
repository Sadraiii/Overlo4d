import Foundation
import Testing
@testable import TallyCore

@Suite struct PaceTests {
    @Test func secondsPerKm() {
        #expect(Pace.secondsPerKm(meters: 5000, seconds: 1500) == 300)
        #expect(Pace.secondsPerKm(meters: nil, seconds: 1500) == nil)
        #expect(Pace.secondsPerKm(meters: 5000, seconds: 0) == nil)
        #expect(Pace.secondsPerKm(meters: 0, seconds: 60) == nil)
    }

    @Test func formatRoundsToWholeSeconds() {
        #expect(Pace.format(secondsPerKm: 300) == "5:00 /km")
        #expect(Pace.format(secondsPerKm: 299.6) == "5:00 /km")
    }

    @Test func distance() {
        let english = Locale(identifier: "en_US")
        #expect(Pace.distance(800, locale: english) == "800 m")
        #expect(Pace.distance(5000, locale: english) == "5 km")
        #expect(Pace.distance(5250, locale: english) == "5.25 km")
        #expect(Pace.distance(5250, locale: Locale(identifier: "da_DK")) == "5,25 km")
    }
}
