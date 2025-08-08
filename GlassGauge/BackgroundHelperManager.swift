//
//  BackgroundHelperManager.swift
//  GlassGauge
//
//  Created by Matt Zeigler on 8/7/25.
//


import ServiceManagement

enum BackgroundHelperManager {
    private static let plistName = "com.zeiglerstudios.glassgauge.helper.plist"

    static func registerIfNeeded() {
        guard #available(macOS 13, *) else { return }
        let svc = SMAppService.daemon(plistName: plistName)
        switch svc.status {
        case .enabled:
            return
        case .requiresApproval:
            try? SMAppService.openSystemSettingsLoginItems()
            fallthrough
        default:
            do { try svc.register() } catch { /* show retry UI */ }
        }
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13, *) else { return }
        let svc = SMAppService.daemon(plistName: plistName)
        do { enabled ? try svc.register() : try svc.unregister() } catch { }
    }
}
