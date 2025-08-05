import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @State private var launchAtLogin = false
    @State private var profile: SamplingProfile = .balanced

    // UI state for the bless/connect action
    @State private var isEnabling = false
    @State private var blessStatus: String?

    var body: some View {
        Form {
            // MARK: Performance
            Section("Performance") {
                Picker("Sampling Profile", selection: $profile) {
                    ForEach(SamplingProfile.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Reduce motion", isOn: $state.reduceMotion)
                Picker("Default Range", selection: $state.range) {
                    Text("Now").tag(TimeRange.now)
                    Text("1h").tag(TimeRange.hour1)
                    Text("24h").tag(TimeRange.hour24)
                }
            }

            // MARK: Sensor Access
            Section("Sensor Access") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enhanced Sensor Access")
                            .fontWeight(.medium)
                        Text(state.hasPrivilegedAccess
                             ? "Real sensor data available"
                             : "Using estimated values")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: state.hasPrivilegedAccess
                          ? "checkmark.circle.fill"
                          : "exclamationmark.circle.fill")
                        .foregroundColor(state.hasPrivilegedAccess ? .green : .orange)
                }

                if !state.hasPrivilegedAccess {
                    Button {
                        enableEnhancedAccess()
                    } label: {
                        if isEnabling {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 6)
                            Text("Enabling…")
                        } else {
                            Text("Enable Enhanced Access")
                        }
                    }
                    .disabled(isEnabling)
                    .buttonStyle(.borderedProminent)

                    if let blessStatus {
                        Text(blessStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Show current access status
                    VStack(alignment: .leading, spacing: 4) {
                        if state.realSensorData.hasFanData {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Real fan speeds available")
                                    .font(.caption)
                            }
                        }
                        
                        if state.realSensorData.hasTempData {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Real temperature sensors available")
                                    .font(.caption)
                            }
                        }
                        
                        Button("Reconnect Helper") {
                            enableEnhancedAccess()
                        }
                        .disabled(isEnabling)
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }

                Text("Enhanced access provides real fan speeds and temperatures instead of estimates. Requires administrator privileges to install a secure helper tool.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: Data Quality
            Section("Data Quality") {
                HStack {
                    Text("Fan Data:")
                    Spacer()
                    Text(state.realSensorData.hasFanData ? "Real RPM" : "Estimated")
                        .foregroundColor(state.realSensorData.hasFanData ? .green : .orange)
                }

                HStack {
                    Text("Temperature Data:")
                    Spacer()
                    Text(state.realSensorData.hasTempData ? "Real Sensors" : "Estimated")
                        .foregroundColor(state.realSensorData.hasTempData ? .green : .orange)
                }

                HStack {
                    Text("Power Data:")
                    Spacer()
                    Text("Real Values")
                        .foregroundColor(.green)
                }
            }

            // MARK: Debug & Diagnostics
            Section("Debug & Diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If Enhanced Access isn't working, run these diagnostics:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("🔍 Quick Diagnostics") {
                            SMJobBlessDiagnostics.runQuickDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("🔍 Full Diagnostics") {
                            SMJobBlessDiagnostics.runCompleteDiagnostics()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("📋 Check Console Logs") {
                        checkConsoleLogs()
                    }
                    .buttonStyle(.bordered)
                    
                    Text("Check the Xcode console output for detailed diagnostic information.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 600) // Made wider to accommodate new debug section
    }

    // IMMEDIATE FIX: Replace your SettingsView enableEnhancedAccess method with this:

    private func enableEnhancedAccess() {
        guard !isEnabling else {
            blessStatus = "Installation already in progress..."
            return
        }
        
        isEnabling = true
        blessStatus = "Requesting administrator privileges..."
        
        // First, run comprehensive diagnostics
        print("🔧 Running comprehensive diagnostics...")
        SMJobBlessDiagnostics.runUltimateDebug()
        
        // Try the enhanced authorization approach
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)
        
        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            isEnabling = false
            blessStatus = "Failed to create authorization"
            return
        }
        
        defer { AuthorizationFree(auth, []) }
        
        // Try to prompt for admin rights explicitly
        let rightName = "system.privilege.admin"
        let rightData = rightName.data(using: .utf8)!
        
        let authResult = rightData.withUnsafeBytes { rightBytes in
            let rightPtr = rightBytes.bindMemory(to: CChar.self).baseAddress!
            
            var authItem = AuthorizationItem(
                name: rightPtr,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            
            return withUnsafeMutablePointer(to: &authItem) { authItemPtr in
                var authRights = AuthorizationRights(count: 1, items: authItemPtr)
                
                // This should trigger the admin password prompt
                let result = AuthorizationCopyRights(
                    auth,
                    &authRights,
                    nil,
                    [.interactionAllowed, .extendRights],
                    nil
                )
                
                print("🔐 Authorization result: \(result)")
                return result == errAuthorizationSuccess
            }
        }
        
        if !authResult {
            isEnabling = false
            blessStatus = "Administrator privileges denied. Please try again and enter your password when prompted."
            return
        }
        
        blessStatus = "Installing helper tool..."
        
        // Now try the actual blessing
        SMBlessedHelperManager.shared.ensureBlessedAndConnect { result in
            DispatchQueue.main.async {
                self.isEnabling = false
                
                switch result {
                case .success:
                    self.state.hasPrivilegedAccess = true
                    self.blessStatus = "Helper installed successfully!"
                    
                case .failure(let error):
                    self.state.hasPrivilegedAccess = false
                    self.blessStatus = "Installation failed: \(error.localizedDescription)"
                    print("❌ Final error: \(error)")
                }
            }
        }
    }
    
    private func testHelperConnection() {
        SMBlessedHelperManager.shared.runPowermetrics(arguments: ["--samplers", "smc", "-n", "1", "-i", "100"]) { exitCode, output in
            DispatchQueue.main.async {
                if exitCode == 0 {
                    self.blessStatus = "Helper working! Output: \(output.prefix(100))..."
                    print("✅ Helper test successful. Output preview: \(output.prefix(200))")
                } else {
                    self.blessStatus = "Helper connection failed (exit code: \(exitCode))"
                    print("❌ Helper test failed with exit code: \(exitCode)")
                }
            }
        }
    }
    
    private func checkConsoleLogs() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--predicate", "subsystem == 'com.zeiglerstudios.glassgauge.helper'", "--last", "5m"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("=== Helper Console Logs (Last 5 minutes) ===")
                print(output)
                print("==========================================")
            }
        } catch {
            print("Failed to read console logs: \(error)")
        }
    }
}

// Keep your existing enum so other files compile unchanged
enum SamplingProfile: String, CaseIterable, Identifiable {
    case eco, balanced, performance
    var id: String { rawValue }
    var label: String {
        switch self {
        case .eco: return "Eco"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }
}
