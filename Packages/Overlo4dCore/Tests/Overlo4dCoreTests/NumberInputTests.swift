import Testing
@testable import Overlo4dCore

struct NumberInputTests {
    @Test func formatsWithoutGroupingAndTrailingZeros() {
        #expect(NumberInput.text(62.5) == "62.5")
        #expect(NumberInput.text(100) == "100")
        #expect(NumberInput.text(1000) == "1000")
        #expect(NumberInput.text(61.234) == "61.23")
        #expect(NumberInput.text(0.005) == "0.01")
        #expect(NumberInput.text(nil) == "")
        #expect(NumberInput.text(.nan) == "")
        #expect(NumberInput.text(62.5, decimalSeparator: ",") == "62,5")
    }

    @Test func readsEitherDecimalMark() {
        #expect(NumberInput.double("62,5") == 62.5)
        #expect(NumberInput.double("62.5") == 62.5)
        #expect(NumberInput.double(" 80 ") == 80)
        #expect(NumberInput.double("") == nil)
        #expect(NumberInput.double("abc") == nil)
        #expect(NumberInput.int("8") == 8)
        #expect(NumberInput.int("") == nil)
    }

    /// Showing a number and reading it back gives the shown number again, so the field and the
    /// workout settle after one step instead of rewriting each other (in both decimal marks).
    @Test func textAndNumberSettle() {
        for separator in [".", ","] {
            var value = 0.0
            while value < 400 {
                let shown = NumberInput.text(value, decimalSeparator: separator)
                let read = NumberInput.double(shown)
                #expect(read != nil)
                #expect(NumberInput.text(read, decimalSeparator: separator) == shown)
                value += 0.37
            }
        }
        // Pounds shown from kilograms: 62 kg is 136.69 lb.
        let lb = 62 / 0.45359237
        let shown = NumberInput.text(lb)
        #expect(NumberInput.text(NumberInput.double(shown)) == shown)
    }

    @Test func showingAValueNeverWritesIt() {
        #expect(!NumberInput.shouldWrite("61.23", over: 61.234))
        #expect(!NumberInput.shouldWrite("62,5", over: 62.5, decimalSeparator: ","))
        #expect(!NumberInput.shouldWrite("", over: nil))
        #expect(!NumberInput.shouldWrite("62.", over: 62))
        #expect(NumberInput.shouldWrite("62.5", over: 62))
        #expect(NumberInput.shouldWrite("", over: 62))
        #expect(NumberInput.shouldWrite("8", over: nil))
    }
}
