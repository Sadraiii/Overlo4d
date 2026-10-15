import SwiftUI
import TallyCore
import TallyKit

/// Time input that fills like a timer: typing 2, 5, 0, 0 shows 25:00.
struct TimeField: View {
    @Binding var seconds: Int?
    var placeholder: String

    @State private var digits = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { TimeEntry.display(digits) },
            set: { newText in
                digits = TimeEntry.cleaned(newText)
                let value = TimeEntry.seconds(fromDigits: digits)
                if value != seconds { seconds = value }
            }
        ))
        .keyboardType(.numberPad)
        .focused($focused)
        .setField()
        .onAppear { digits = TimeEntry.digits(fromSeconds: seconds ?? 0) }
        .onChange(of: seconds) { _, newValue in
            if TimeEntry.seconds(fromDigits: digits) != newValue {
                digits = TimeEntry.digits(fromSeconds: newValue ?? 0)
            }
        }
        // Typed values like 0:90 become 1:30 once the field is left.
        .onChange(of: focused) { _, isFocused in
            if !isFocused { digits = TimeEntry.digits(fromSeconds: seconds ?? 0) }
        }
    }
}
