import SwiftUI

@main
struct GlassGaugeApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("didTryRegisterHelper") private var didTryRegisterHelper = false

    var body: some Scene {
        // Main window
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 700)
                .task {
                    if !didTryRegisterHelper {
                        BackgroundHelperManager.registerIfNeeded()
                        didTryRegisterHelper = true
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1400, height: 900)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // macOS 13+ menu bar extra
        #if os(macOS)
        if #available(macOS 13, *) {
            MenuBarExtra("GlassGauge", systemImage: "gauge.high") {
                MenuBarExtraView()
                    .environmentObject(appState)
                    .frame(width: 360)
            }
            .menuBarExtraStyle(.window)
        }
        #endif
    }
}

