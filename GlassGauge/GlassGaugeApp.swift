
import SwiftUI

@main
struct GlassGaugeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

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
