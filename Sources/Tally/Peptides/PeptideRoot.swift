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
    /// Covers the screen while the app is not in front, so the app switcher shows nothing.
    @State private var covered = false

    var body: some View {
        ZStack {
            PeptideHome(store: store, onHide: onHide)
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
    }
}
