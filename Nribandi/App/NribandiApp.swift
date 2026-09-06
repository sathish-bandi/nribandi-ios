import SwiftUI

@main
struct NribandiApp: App {
    /// Constructed in `init` so `@MainActor` `AppState` is created from an isolated context
    /// (property-initializer defaults can fail actor checks in newer Xcode toolchains).
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.session)
        }
    }
}
