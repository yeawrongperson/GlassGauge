import Foundation
import Combine
import SwiftUI

final class AppState: ObservableObject {
    @Published var selection: SectionID = .overview
    @Published var range: TimeRange = .now
    @Published var searchText: String = ""
    @Published var reduceMotion: Bool = false
    
    // Core metrics
    @Published var cpu = MetricModel("CPU", icon: "cpu", unit: "%")
    @Published var gpu = MetricModel("GPU", icon: "rectangle.portrait.on.rectangle.portrait.angled", unit: "%")
    @Published var memory = MetricModel("Memory", icon: "memorychip", unit: "GB")
    @Published var disk = MetricModel("Disk", icon: "externaldrive", unit: "KB/s")
    @Published var network = MetricModel("Network", icon: "wifi", unit: "KB/s")
    @Published var networkIn = MetricModel("Network In", icon: "arrow.down.circle", unit: "KB/s")
    @Published var networkOut = MetricModel("Network Out", icon: "arrow.up.circle", unit: "KB/s")
    @Published var battery = MetricModel("Battery", icon: "battery.100", unit: "%")
    @Published var fans = MetricModel("Fans", icon: "fanblades", unit: "RPM")
    @Published var power = MetricModel("Power", icon: "bolt.fill", unit: "W")
    @Published var temps = MetricModel("Temps", icon: "thermometer", unit: "°C")
    
    @Published var pinnedIDs: Set<UUID> = []
    
    // Enhanced sensor data from privileged helper
    @Published var hasPrivilegedAccess = false
    @Published var realSensorData: RealSensorData = RealSensorData()
    @Published var helperStatus: String = "Unknown"
    
    private var timer: Timer?
    private let monitor = SystemMonitor()
    
    init() {
        startPolling()
        checkPrivilegedAccess()
    }
    
    private func checkPrivilegedAccess() {
        print("🔍 Checking privileged access...")
        
        // Update helper status
        helperStatus = UnifiedHelperManager.shared.getHelperStatus()
        
        // Try to establish connection asynchronously
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
            UnifiedHelperManager.shared.ensureHelperIsReady { [weak self] (result: Result<Void, Error>) in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.hasPrivilegedAccess = true
                        self?.helperStatus = "Connected"
                        print("✅ Privileged access available")

                        // Test with a simple sensor call
                        self?.testHelperConnection()

                    case .failure(let error):
                        self?.hasPrivilegedAccess = false
                        self?.helperStatus = "Error: \(error.localizedDescription)"
                        print("❌ No privileged access: \(error.localizedDescription)")
                    }
                }
            }
        })
    }
    
    private func testHelperConnection() {
        print("🧪 Testing helper connection with sensor data...")
        
        UnifiedHelperManager.shared.runPowermetrics(
            arguments: ["--samplers", "smc", "-n", "1", "-i", "100"]
        ) { [weak self] (exitCode: Int32, output: String) in
            DispatchQueue.main.async {
                if exitCode == 0 && !output.isEmpty {
                    print("✅ Helper test successful, got \(output.count) chars of sensor data")
                    self?.parsePrivilegedSensorData(output)
                } else {
                    print("⚠️ Helper test failed: exit code \(exitCode)")
                    // Keep privileged access flag true but note the issue
                    self?.helperStatus = "Connected (limited data)"
                }
            }
        }
    }
    
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    private func push(_ model: MetricModel, value: Double, direction: PowerDirection? = nil) {
        let now = Date()
        model.primaryValue = value
        model.samples.append(SamplePoint(t: now, v: value, direction: direction))
        // Trim to current range window
        let cutoff = now.addingTimeInterval(-range.window)
        model.samples.removeAll { $0.t < cutoff }
    }
    
    private func tick() {
        let s = monitor.sample()
        
        // Update privileged sensor data if available (every 5 seconds to avoid overload)
        if hasPrivilegedAccess && Int(Date().timeIntervalSince1970) % 5 == 0 {
            updatePrivilegedSensorData()
        }
        
        // Update all primary metrics
        push(cpu, value: s.cpu)
        push(gpu, value: s.gpu)
        push(memory, value: s.memory)
        
        // Scale disk throughput to MB/s when exceeding 1,024 KB/s for readability
        if s.disk >= 1024 {
            disk.unit = "MB/s"
            push(disk, value: s.disk / 1024)
        } else {
            disk.unit = "KB/s"
            push(disk, value: s.disk)
        }
        
        // Handle network traffic with separate in/out tracking
        push(network, value: s.network)
        
        // Handle incoming network traffic
        if s.networkIn >= 1024 {
            networkIn.unit = "MB/s"
            push(networkIn, value: s.networkIn / 1024)
        } else {
            networkIn.unit = "KB/s"
            push(networkIn, value: s.networkIn)
        }
        
        // Handle outgoing network traffic
        if s.networkOut >= 1024 {
            networkOut.unit = "MB/s"
            push(networkOut, value: s.networkOut / 1024)
        } else {
            networkOut.unit = "KB/s"
            push(networkOut, value: s.networkOut)
        }
        
        push(battery, value: s.battery)
        
        // Use privileged fan data if available, otherwise use estimated
        let fanRPM = realSensorData.fanSpeed ?? s.fans
        push(fans, value: fanRPM)
        
        // Calculate and update average temperature for Temps tab
        let cpuTemp = realSensorData.cpuTemp ?? s.cpuTemp
        let gpuTemp = realSensorData.gpuTemp ?? s.gpuTemp
        let diskTemp = realSensorData.diskTemp ?? s.diskTemp
        
        let validTemps = [cpuTemp, gpuTemp, diskTemp].filter { $0 > 0 }
        let avgTemp = validTemps.isEmpty ? 0 : validTemps.reduce(0, +) / Double(validTemps.count)
        push(temps, value: avgTemp)
        
        // Update secondary information for all metrics
        updateMetricSecondaryInfo(s: s, cpuTemp: cpuTemp, gpuTemp: gpuTemp, diskTemp: diskTemp, avgTemp: avgTemp, validTemps: validTemps, fanRPM: fanRPM)
    }
    
    private func updateMetricSecondaryInfo(s: SystemSample, cpuTemp: Double, gpuTemp: Double, diskTemp: Double, avgTemp: Double, validTemps: [Double], fanRPM: Double) {
        // Update CPU temperature and secondary info
        if cpuTemp > 0 {
            let tempLabel = hasPrivilegedAccess ? "\(Int(cpuTemp))°C" : "~\(Int(cpuTemp))°C"
            cpu.secondary = "\(tempLabel) • \(temperatureBadge(for: cpuTemp))"
            cpu.accent = accentColor(for: cpuTemp)
        } else {
            cpu.secondary = "Temperature Unknown"
            cpu.accent = .gray
        }
        
        // Update GPU temperature and secondary info
        if gpuTemp > 0 {
            let tempLabel = hasPrivilegedAccess ? "\(Int(gpuTemp))°C" : "~\(Int(gpuTemp))°C"
            gpu.secondary = "\(tempLabel) • \(temperatureBadge(for: gpuTemp))"
            gpu.accent = accentColor(for: gpuTemp)
        } else {
            gpu.secondary = "Temperature Unknown"
            gpu.accent = .gray
        }
        
        // Update disk temperature and secondary info
        if diskTemp > 0 {
            let tempLabel = hasPrivilegedAccess ? "\(Int(diskTemp))°C" : "~\(Int(diskTemp))°C"
            disk.secondary = "\(tempLabel) • \(temperatureBadge(for: diskTemp))"
            disk.accent = accentColor(for: diskTemp)
        } else {
            disk.secondary = "No Sensor Available"
            disk.accent = .gray
        }
        
        // Update battery secondary info with power readings
        battery.secondary = "Cycle \(s.batteryCycle) • In \(String(format: "%.1f", s.powerIn))W / Out \(String(format: "%.1f", s.powerOut))W"
        
        // Update overall temperature metric secondary info
        if validTemps.count > 0 {
            let cpuLabel = cpuTemp > 0 ? "CPU: \(Int(cpuTemp))°" : nil
            let gpuLabel = gpuTemp > 0 ? "GPU: \(Int(gpuTemp))°" : nil
            let diskLabel = diskTemp > 0 ? "Disk: \(Int(diskTemp))°" : nil
            
            let tempStrings = [cpuLabel, gpuLabel, diskLabel].compactMap { $0 }
            temps.secondary = tempStrings.joined(separator: " • ")
            temps.accent = accentColor(for: avgTemp)
        } else {
            temps.secondary = "No Temperature Sensors"
            temps.accent = .gray
        }
        
        // Update network secondary info with separate in/out details
        if s.networkIn > 0 || s.networkOut > 0 {
            let inUnit = s.networkIn >= 1024 ? "MB/s" : "KB/s"
            let outUnit = s.networkOut >= 1024 ? "MB/s" : "KB/s"
            let inValue = s.networkIn >= 1024 ? s.networkIn / 1024 : s.networkIn
            let outValue = s.networkOut >= 1024 ? s.networkOut / 1024 : s.networkOut
            
            network.secondary = "↓ \(String(format: "%.1f", inValue)) \(inUnit) • ↑ \(String(format: "%.1f", outValue)) \(outUnit)"
            networkIn.secondary = "Incoming Traffic"
            networkOut.secondary = "Outgoing Traffic"
            
            // Set colors
            networkIn.accent = .green
            networkOut.accent = .red
        } else {
            network.secondary = "No Network Activity"
            networkIn.secondary = "No Incoming Traffic"
            networkOut.secondary = "No Outgoing Traffic"
            networkIn.accent = .gray
            networkOut.accent = .gray
        }
        
        // Update memory secondary info
        let memoryPercent = (s.memory / getTotalMemory()) * 100
        memory.secondary = "Usage: \(String(format: "%.1f", memoryPercent))% of \(String(format: "%.0f", getTotalMemory())) GB"
        memory.accent = memoryPercent > 80 ? .orange : (memoryPercent > 90 ? .red : .primary)
        
        // Update fans secondary info with comprehensive status
        if fanRPM > 0 {
            let displayRPM = Int(fanRPM)
            let statusLabel = hasPrivilegedAccess ? "\(displayRPM) RPM" : "~\(displayRPM) RPM (estimated)"
            fans.secondary = statusLabel
            
            // Color based on fan speed ranges for Intel MacBook Pro
            if fanRPM > 4500 {
                fans.accent = .red
            } else if fanRPM > 3500 {
                fans.accent = .orange
            } else if fanRPM > 2500 {
                fans.accent = .yellow
            } else {
                fans.accent = .primary
            }
        } else {
            fans.secondary = hasPrivilegedAccess ? "No fan sensors detected" : "Fan sensors require elevated access"
            fans.accent = .gray
        }
        
        // Update power secondary info
        if s.powerIn > 0 {
            power.secondary = "Charging at \(String(format: "%.1f", s.powerIn))W"
            power.accent = .green
            push(power, value: s.powerIn, direction: .charging)
        } else if s.powerOut > 0 {
            power.secondary = "Using \(String(format: "%.1f", s.powerOut))W"
            power.accent = .red
            push(power, value: s.powerOut, direction: .using)
        } else {
            power.secondary = "Power Information Unavailable"
            power.accent = .gray
        }
        
        // Update GPU secondary info with more details
        if s.gpu > 0 {
            let gpuSecondary = gpuTemp > 0 ?
            "\(Int(gpuTemp))°C • \(temperatureBadge(for: gpuTemp)) • \(String(format: "%.1f", s.gpu))% Load" :
            "Load: \(String(format: "%.1f", s.gpu))%"
            gpu.secondary = gpuSecondary
            gpu.accent = s.gpu > 80 ? .orange : (s.gpu > 90 ? .red : accentColor(for: gpuTemp))
        }
    }
    
    private func updatePrivilegedSensorData() {
        // Fetch real sensor data from helper in background (throttled)
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            UnifiedHelperManager.shared.runPowermetrics(
                arguments: ["--samplers", "smc", "-n", "1", "-i", "200"]
            ) { (exitCode: Int32, output: String) in
                if exitCode == 0 && !output.isEmpty {
                    DispatchQueue.main.async {
                        self.parsePrivilegedSensorData(output)
                    }
                } else {
                    // Don't spam logs, just note that we didn't get data this time
                    print("📊 Powermetrics call returned exit code \(exitCode)")
                }
            }
        }
    }
    
    private func parsePrivilegedSensorData(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let lineLower = line.lowercased()
            
            // Parse fan speed
            if lineLower.contains("fan") && lineLower.contains("rpm") {
                if let rpm = extractNumber(from: line, pattern: #"(\d+\.?\d*)\s*rpm"#) {
                    realSensorData.fanSpeed = rpm
                }
            }
            
            // Parse CPU temperature
            if lineLower.contains("cpu") && lineLower.contains("temp") {
                if let temp = extractNumber(from: line, pattern: #"(\d+\.?\d*)\s*°?c"#) {
                    realSensorData.cpuTemp = temp
                }
            }
            
            // Parse GPU temperature
            if lineLower.contains("gpu") && lineLower.contains("temp") {
                if let temp = extractNumber(from: line, pattern: #"(\d+\.?\d*)\s*°?c"#) {
                    realSensorData.gpuTemp = temp
                }
            }
            
            // Parse disk temperature
            if (lineLower.contains("disk") || lineLower.contains("ssd")) && lineLower.contains("temp") {
                if let temp = extractNumber(from: line, pattern: #"(\d+\.?\d*)\s*°?c"#) {
                    realSensorData.diskTemp = temp
                }
            }
        }
    }
    
    private func extractNumber(from text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        
        let numberStr = String(text[range])
        return Double(numberStr)
    }
    
    private func getTotalMemory() -> Double {
        // Get total physical memory in GB
        var size: UInt64 = 0
        var sizeSize = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &size, &sizeSize, nil, 0) == 0 {
            return Double(size) / 1024.0 / 1024.0 / 1024.0
        }
        return 16.0 // Fallback to 16GB if we can't determine
    }
    
    var allMetrics: [MetricModel] {
        [cpu, gpu, memory, disk, network, battery, fans, power, temps]
    }
    
    private func accentColor(for temp: Double) -> Color {
        switch temp {
        case ..<40: return .teal
        case ..<70: return .blue
        case ..<85: return .orange
        default: return .red
        }
    }
    
    private func temperatureBadge(for temp: Double) -> String {
        switch temp {
        case ..<70: return "ok"
        case ..<85: return "elevated"
        default: return "critical"
        }
    }
    
    // MARK: - Public methods for UI
    
    func refreshHelperConnection() {
        print("🔄 Manually refreshing helper connection...")
        checkPrivilegedAccess()
    }
    
    func getDetailedHelperStatus() -> String {
        return """
        Status: \(helperStatus)
        Privileged Access: \(hasPrivilegedAccess ? "Yes" : "No")
        Real Fan Data: \(realSensorData.hasFanData ? "Yes" : "No")
        Real Temp Data: \(realSensorData.hasTempData ? "Yes" : "No")
        """
    }
}

// MARK: - Real Sensor Data Model
class RealSensorData: ObservableObject {
    @Published var fanSpeed: Double?
    @Published var cpuTemp: Double?
    @Published var gpuTemp: Double?
    @Published var diskTemp: Double?
    
    var hasFanData: Bool { fanSpeed != nil }
    var hasTempData: Bool { cpuTemp != nil || gpuTemp != nil || diskTemp != nil }
}
