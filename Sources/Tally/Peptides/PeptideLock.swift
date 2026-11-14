import SwiftUI
import TallyCore
import TallyKit
import UIKit

/// Settings: the one way into the peptide tracker.
struct PeptideSettingsSection: View {
    @Environment(AppUI.self) private var ui
    @State private var showing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Private").eyebrow(11.5)
            Button {
                showing = true
            } label: {
                HStack {
                    Text("Peptides").font(Typo.body(15, .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                }
                .foregroundStyle(Theme.ink)
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .card(padding: 0, cornerRadius: 18)
        }
        .fullScreenCover(isPresented: $showing) {
            PeptideRoot {
                // Straight back to the app: the tracker and Settings both close.
                showing = false
                ui.showingSettings = false
            }
        }
    }
}

/// The tracker's own screen stack. It owns its store, so the data is only in memory while this is open.
struct PeptideRoot: View {
    let onHide: () -> Void

    @State private var store = PeptideStore()
    @State private var unlocked = false
    /// Covers the screen while the app is not in front, so the app switcher shows nothing.
    @State private var covered = false

    var body: some View {
        ZStack {
            if store.hasPIN && !unlocked {
                PeptideLockView(store: store, onUnlock: { unlocked = true }, onHide: onHide)
            } else {
                PeptideHome(store: store, onHide: onHide)
            }
            if covered {
                Theme.paper.ignoresSafeArea()
            }
        }
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            covered = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            covered = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            unlocked = false
        }
    }
}

/// Four dots and a number pad. Calls `onComplete` when the fourth digit is typed.
struct PinPad: View {
    let title: String
    var message: String?
    var isError = false
    @Binding var pin: String
    let onComplete: (String) -> Void

    private static let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "delete"]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(title).display(30)
                Text(message ?? " ")
                    .font(Typo.body(14))
                    .foregroundStyle(isError ? Theme.danger : Theme.ink3)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Theme.accent : Theme.line2)
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityLabel("\(pin.count) of 4 digits")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 18), count: 3), spacing: 14) {
                ForEach(Self.keys, id: \.self) { key in
                    if key.isEmpty {
                        Color.clear.frame(width: 76, height: 76)
                    } else {
                        Button {
                            press(key)
                        } label: {
                            Group {
                                if key == "delete" {
                                    Image(systemName: "delete.left").font(.system(size: 22, weight: .medium))
                                } else {
                                    Text(key).font(Typo.display(34)).monospacedDigit()
                                }
                            }
                            .foregroundStyle(Theme.ink)
                            .frame(width: 76, height: 76)
                            .background(key == "delete" ? Color.clear : Theme.card, in: .circle)
                            .overlay(Circle().strokeBorder(key == "delete" ? Color.clear : Theme.line, lineWidth: 1))
                            .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "delete" ? "Delete" : key)
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        if key == "delete" {
            if !pin.isEmpty { pin.removeLast() }
            return
        }
        guard pin.count < 4 else { return }
        pin.append(key)
        if pin.count == 4 { onComplete(pin) }
    }
}

/// Asks for the PIN before the tracker shows anything.
struct PeptideLockView: View {
    let store: PeptideStore
    let onUnlock: () -> Void
    let onHide: () -> Void

    @State private var pin = ""
    @State private var wrong = false
    @State private var confirmingErase = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                PinPad(title: "Enter PIN", message: wrong ? "Wrong PIN. Try again." : nil, isError: wrong, pin: $pin) { entered in
                    if store.checkPIN(entered) {
                        onUnlock()
                    } else {
                        wrong = true
                        pin = ""
                    }
                }
                Button("Forgot PIN?") { confirmingErase = true }
                    .font(Typo.body(14, .semibold))
                    .foregroundStyle(Theme.ink3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hide", systemImage: "eye.slash", action: onHide)
                }
            }
            .confirmationDialog("Erase the tracker?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { store.eraseEverything() }
            } message: {
                Text("The PIN can't be recovered. Erasing removes every peptide and log entry, and the PIN.")
            }
        }
    }
}

/// Set or change the PIN: type it, then type it again.
struct PeptidePINSheet: View {
    let store: PeptideStore
    @Environment(\.dismiss) private var dismiss

    @State private var first: String?
    @State private var pin = ""
    @State private var mismatch = false

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                PinPad(title: first == nil ? "New PIN" : "Repeat PIN",
                       message: mismatch ? "Those didn't match. Start again." : "4 digits. It can't be recovered if you forget it.",
                       isError: mismatch, pin: $pin) { entered in
                    if let chosen = first {
                        if chosen == entered {
                            store.setPIN(entered)
                            dismiss()
                        } else {
                            first = nil
                            mismatch = true
                            pin = ""
                        }
                    } else {
                        first = entered
                        mismatch = false
                        pin = ""
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .screenBackground()
            .navigationTitle("PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
