import TallyKit
import SwiftUI
import WidgetKit

@main
struct TallyWidgets: WidgetBundle {
    init() {
        Typo.registerFonts()
    }

    var body: some Widget {
        RepsWidget()
        TrainingWidget()
        FoodWidget()
        WorkoutLiveActivity()
    }
}

/// Small uppercase label, as in the app.
struct WidgetLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Typo.body(11, .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.ink3)
            .lineLimit(1)
    }
}

enum MidnightTimeline {
    /// Widgets refresh at midnight so daily counts reset.
    static var nextMidnight: Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60)
    }
}
