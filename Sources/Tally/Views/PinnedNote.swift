import TallyKit
import SwiftUI

/// The note pinned to an exercise (seat height, grip, cues), shown every time the exercise comes up.
/// Tap to edit; an empty note removes it.
struct PinnedNoteRow: View {
    @Environment(GymStore.self) private var gym
    let exerciseID: UUID
    @Binding var isEditing: Bool

    var body: some View {
        let note = gym.pinnedNote(for: exerciseID)
        if !note.isEmpty {
            Button {
                isEditing = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.hot)
                        .rotationEffect(.degrees(35))
                    Text(note)
                        .font(Typo.body(13.5, .medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.hot.opacity(0.1), in: .rect(cornerRadius: 12))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pinned note: \(note)")
            .accessibilityHint("Edit")
        }
    }
}

/// The alert that edits an exercise's pinned note.
struct PinnedNoteEditor: ViewModifier {
    @Environment(GymStore.self) private var gym
    let exerciseID: UUID
    @Binding var isPresented: Bool

    @State private var text = ""

    func body(content: Content) -> some View {
        let note = gym.pinnedNote(for: exerciseID)
        content
            .alert("Pinned note", isPresented: $isPresented) {
                TextField("e.g. Seat on 4, outer handles", text: $text)
                Button("Save") { gym.setPinnedNote(text, for: exerciseID) }
                if !note.isEmpty {
                    Button("Remove", role: .destructive) { gym.setPinnedNote("", for: exerciseID) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Shown every time you do this exercise.")
            }
            .onChange(of: isPresented) { _, presented in
                if presented { text = note }
            }
    }
}

extension View {
    func pinnedNoteEditor(for exerciseID: UUID, isPresented: Binding<Bool>) -> some View {
        modifier(PinnedNoteEditor(exerciseID: exerciseID, isPresented: isPresented))
    }
}
