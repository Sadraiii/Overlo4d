import Testing
@testable import TallyCore

@Suite struct TimeEntryTests {
    @Test func cleanedKeepsDigitsDropsLeadingZerosAndCaps() {
        #expect(TimeEntry.cleaned("25:00") == "2500")
        #expect(TimeEntry.cleaned("0:05") == "5")
        #expect(TimeEntry.cleaned("0:0") == "")
        #expect(TimeEntry.cleaned("1234567") == "123456")
    }

    @Test func secondsFromDigits() {
        #expect(TimeEntry.seconds(fromDigits: "2500") == 1500)
        #expect(TimeEntry.seconds(fromDigits: "90") == 90)
        #expect(TimeEntry.seconds(fromDigits: "12500") == 5100)
        #expect(TimeEntry.seconds(fromDigits: "") == nil)
    }

    @Test func digitsRoundTrip() {
        for seconds in [5, 65, 1500, 3723] {
            #expect(TimeEntry.seconds(fromDigits: TimeEntry.digits(fromSeconds: seconds)) == seconds)
        }
        #expect(TimeEntry.digits(fromSeconds: 0) == "")
    }

    @Test func ninetySecondsRedisplaysAsOneThirty() {
        let seconds = TimeEntry.seconds(fromDigits: "90")
        #expect(TimeEntry.display(TimeEntry.digits(fromSeconds: seconds ?? 0)) == "1:30")
    }

    @Test func displayInsertsColons() {
        #expect(TimeEntry.display("5") == "0:05")
        #expect(TimeEntry.display("2500") == "25:00")
        #expect(TimeEntry.display("12500") == "1:25:00")
        #expect(TimeEntry.display("") == "")
    }

    @Test func format() {
        #expect(TimeEntry.format(0) == "0:00")
        #expect(TimeEntry.format(65) == "1:05")
        #expect(TimeEntry.format(3723) == "1:02:03")
    }
}
