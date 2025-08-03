import SwiftUI

@main
struct GlassGaugeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 700) // Increased minimum window size
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1400, height: 900) // Set a comfortable default size

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // macOS 13+ menu bar extra
        MenuBarExtra("GlassGauge", systemImage: "gauge.high") {
            MenuBarExtraView()
                .environmentObject(appState)
                .frame(width: 360)
        }
        .menuBarExtraStyle(.window)
    }
}
