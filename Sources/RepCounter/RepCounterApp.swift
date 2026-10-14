import SwiftUI

@main
struct RepCounterApp: App {
    @State private var model = RepModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up the new day (and any external changes) when returning to the app.
            if phase == .active { model.reload() }
        }
    }
}
