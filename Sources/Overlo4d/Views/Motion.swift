import SwiftUI
import UIKit

/// The app's motion, in one place so every screen moves the same way.
/// Short and without overshoot for things people do often (ticking sets, pressing buttons);
/// a small settle only for things that arrive. Nothing waits for an animation to finish.
/// With Reduce Motion on, slides and scaling become plain fades (`animate`, `rise`, `pop`, `reveal`).
enum Motion {
    /// Press-down on buttons and cards, ticks and toggles.
    static let tap = Animation.snappy(duration: 0.2)
    /// Content changing in place: rows added or removed, progress and values moving.
    static let standard = Animation.smooth(duration: 0.3)
    /// Something arriving, like the rest dock or the finished workout: settles without bouncing back.
    static let arrive = Animation.spring(duration: 0.45, bounce: 0.15)
    /// What Reduce Motion gets instead: a short fade with no travel.
    static let reduced = Animation.easeInOut(duration: 0.2)

    /// `withAnimation` with `animation`, or the short fade when Reduce Motion is on.
    @MainActor
    static func animate<Result>(_ animation: Animation = standard, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(UIAccessibility.isReduceMotionEnabled ? reduced : animation, body)
    }
}

extension AnyTransition {
    /// Slides up from the bottom edge while fading in; only fades with Reduce Motion.
    static func rise(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    /// Grows from slightly smaller while fading in, for badges and pills; only fades with Reduce Motion.
    static func pop(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }
}

/// Fades a block in and lifts it into place `delay` seconds after `isShown` turns true,
/// so a screen's sections can arrive one after another. Only fades with Reduce Motion.
private struct Reveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isShown: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 14)
            .animation((reduceMotion ? Motion.reduced : Motion.arrive).delay(delay), value: isShown)
    }
}

extension View {
    func reveal(_ isShown: Bool, delay: Double = 0) -> some View {
        modifier(Reveal(isShown: isShown, delay: delay))
    }
}

/// Tappable cards: the whole card presses in slightly, so it answers the touch like a button.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Haptics for workout moments, kept to the system patterns and what they mean.
/// Elsewhere the app uses `.selection` when a value is picked or nudged and `.success` when
/// something is done (a fast started, water logged). The rest timer's end plays a notification
/// haptic from `RestTimer` itself, so it is felt on any screen.
extension SensoryFeedback {
    /// A set ticked off.
    static var setDone: SensoryFeedback { .success }
    /// The workout saved: a single heavy tap, so it never feels like another set.
    static var workoutDone: SensoryFeedback { .impact(weight: .heavy, intensity: 1) }
}
