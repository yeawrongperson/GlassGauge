import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @State private var launchAtLogin = false
    @State private var profile: SamplingProfile = .balanced

    // UI state for the helper management
    @State private var isEnabling = false
    @State private var statusMessage: String?
    @State private var showingDetailedStatus = false

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

            // MARK: Enhanced Sensor Access
            Section("Enhanced Sensor Access") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hardware Sensor Access")
                                .fontWeight(.medium)
                            Text(state.hasPrivilegedAccess
                                 ? "Real hardware sensor data available"
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
                    
                    // Helper Status
                    HStack {
                        Text("Status:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(state.helperStatus)
                            .font(.caption)
                            .fontFamily(.monospaced)
                        
                        Spacer()
                        
                        Button("Details") {
                            showingDetailedStatus.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    
                    if showingDetailedStatus {
                        Text(state.getDetailedHelperStatus())
                            .font(.caption)
                            .fontFamily(.monospaced)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                }

                if !state.hasPrivilegedAccess {
                    Button {
                        enableEnhancedAccess()
                    } label: {
                        HStack {
                            if isEnabling {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text(isEnabling ? "Setting up..." : "Enable Enhanced Access")
                        }
                    }
                    .disabled(isEnabling)
                    .buttonStyle(.borderedProminent)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                } else {
                    // Show current access status and controls
                    VStack(alignment: .leading, spacing: 6) {
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
                        
                        HStack {
                            Button("Refresh Connection") {
                                refreshHelperConnection()
                            }
                            .disabled(isEnabling)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            if #available(macOS 13.0, *) {
                                Button("Unregister Helper") {
                                    unregisterHelper()
                                }
                                .disabled(isEnabling)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Text("Enhanced access provides real fan speeds and temperatures instead of estimates. Requires administrator privileges to install a secure helper daemon.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: Data Quality Status
            Section("Data Quality") {
                VStack(alignment: .leading, spacing: 8) {
                    DataQualityRow(label: "Fan Data", hasRealData: state.realSensorData.hasFanData)
                    DataQualityRow(label: "Temperature Data", hasRealData: state.realSensorData.hasTempData)
                    DataQualityRow(label: "Power Data", hasRealData: true) // Always available
                    DataQualityRow(label: "Network Data", hasRealData: true) // Always available
                    DataQualityRow(label: "Memory Data", hasRealData: true) // Always available
                }
            }

            // MARK: macOS Version Info
            Section("System Information") {
                HStack {
                    Text("macOS Version:")
                    Spacer()
                    Text(getmacOSVersion())
                        .fontFamily(.monospaced)
                }
                
                HStack {
                    Text("Helper API:")
                    Spacer()
                    Text(getHelperAPIType())
                        .fontFamily(.monospaced)
                }
                
                HStack {
                    Text("Architecture:")
                    Spacer()
                    Text(getArchitecture())
                        .fontFamily(.monospaced)
                }
            }

            // MARK: Debug & Diagnostics
            Section("Debug & Diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If Enhanced Access isn't working properly:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("🔍 Test Connection") {
                            testHelperConnection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("📋 Check Logs") {
                            checkLogs()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("⚙️ Open System Settings") {
                            openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("Check the Console app for logs from 'GlassGauge' and 'com.zeiglerstudios.glassgauge.helper'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 650)
    }

    // MARK: - Helper Management Functions

    private func enableEnhancedAccess() {
        guard !isEnabling else { return }
        
        isEnabling = true
        statusMessage = "Requesting administrator privileges..."
        
        print("🔧 Starting enhanced access setup...")
        
        UnifiedHelperManager.shared.ensureHelperIsReady { [self] result in
            DispatchQueue.main.async {
                self.isEnabling = false
                
                switch result {
                case .success:
                    self.state.hasPrivilegedAccess = true
                    self.statusMessage = "✅ Enhanced access enabled successfully!"
                    print("✅ Enhanced access setup complete")
                    
                    // Refresh the app state
                    self.state.refreshHelperConnection()
                    
                    // Clear status message after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.statusMessage = nil
                    }
                    
                case .failure(let error):
                    self.state.hasPrivilegedAccess = false
                    self.statusMessage = "❌ Setup failed: \(error.localizedDescription)"
                    print("❌ Enhanced access setup failed: \(error)")
                    
                    // Provide specific guidance based on error type
                    if let unifiedError = error as? UnifiedHelperManager.HelperError {
                        switch unifiedError {
                        case .authorizationFailed:
                            self.statusMessage = "❌ Administrator privileges required. Please try again and enter your password when prompted."
                        case .connectionFailed:
                            self.statusMessage = "❌ Helper installed but connection failed. Try refreshing or restarting the app."
                        case .installationFailed:
                            self.statusMessage = "❌ Installation failed. Check System Settings > General > Login Items & Extensions"
                        default:
                            break
                        }
                    }
                }
            }
        }
    }
    
    private func refreshHelperConnection() {
        isEnabling = true
        statusMessage = "Refreshing connection..."
        
        state.refreshHelperConnection()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isEnabling = false
            self.statusMessage = state.hasPrivilegedAccess ? "✅ Connection refreshed" : "❌ Connection failed"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.statusMessage = nil
            }
        }
    }
    
    @available(macOS 13.0, *)
    private func unregisterHelper() {
        isEnabling = true
        statusMessage = "Unregistering helper..."
        
        UnifiedHelperManager.shared.unregisterHelper { result in
            DispatchQueue.main.async {
                self.isEnabling = false
                
                switch result {
                case .success:
                    self.state.hasPrivilegedAccess = false
                    self.statusMessage = "✅ Helper unregistered successfully"
                case .failure(let error):
                    self.statusMessage = "❌ Unregistration failed: \(error.localizedDescription)"
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.statusMessage = nil
                }
            }
        }
    }
    
    private func testHelperConnection() {
        statusMessage = "Testing helper connection..."
        
        UnifiedHelperManager.shared.runPowermetrics(arguments: ["--help"]) { exitCode, output in
            DispatchQueue.main.async {
                if exitCode == 0 {
                    self.statusMessage = "✅ Helper connection test successful"
                } else {
                    self.statusMessage = "❌ Helper connection test failed (exit code: \(exitCode))"
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.statusMessage = nil
                }
            }
        }
    }
    
    private func checkLogs() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["/Applications/Utilities/Console.app"]
        
        do {
            try process.run()
            statusMessage = "Console app opened - search for 'GlassGauge' or 'glassgauge.helper'"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.statusMessage = nil
            }
        } catch {
            statusMessage = "Failed to open Console app"
        }
    }
    
    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
            statusMessage = "System Settings opened - check Login Items & Extensions"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.statusMessage = nil
            }
        }
    }
    
    // MARK: - System Information
    
    private func getmacOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private func getHelperAPIType() -> String {
        if #available(macOS 13.0, *) {
            return "SMAppService (Modern)"
        } else {
            return "SMJobBless (Legacy)"
        }
    }
    
    private func getArchitecture() -> String {
        #if arch(arm64)
        return "Apple Silicon (ARM64)"
        #else
        return "Intel (x86_64)"
        #endif
    }
}

// MARK: - Helper Views

struct DataQualityRow: View {
    let label: String
    let hasRealData: Bool
    
    var body: some View {
        HStack {
            Text("\(label):")
            Spacer()
            HStack {
                Image(systemName: hasRealData ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(hasRealData ? .green : .orange)
                    .font(.caption)
                Text(hasRealData ? "Real Values" : "Estimated")
                    .font(.caption)
                    .foregroundColor(hasRealData ? .green : .orange)
            }
        }
    }
}

// Keep the existing enum for compatibility
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
