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
    
    private var timer: Timer?
    private let monitor = SystemMonitor()
    
    init() {
        startPolling()
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
        push(fans, value: s.fans)
        
        // Calculate and update average temperature for Temps tab
        let validTemps = [s.cpuTemp, s.gpuTemp, s.diskTemp].filter { $0 > 0 }
        let avgTemp = validTemps.isEmpty ? 0 : validTemps.reduce(0, +) / Double(validTemps.count)
        push(temps, value: avgTemp)
        
        // Update CPU temperature and secondary info
        if s.cpuTemp > 0 {
            cpu.secondary = "\(Int(s.cpuTemp))°C • \(temperatureBadge(for: s.cpuTemp))"
            cpu.accent = accentColor(for: s.cpuTemp)
        } else {
            cpu.secondary = "Estimated Temperature"
            cpu.accent = .gray
        }
        
        // Update GPU temperature and secondary info
        if s.gpuTemp > 0 {
            gpu.secondary = "\(Int(s.gpuTemp))°C • \(temperatureBadge(for: s.gpuTemp))"
            gpu.accent = accentColor(for: s.gpuTemp)
        } else {
            gpu.secondary = "Estimated Temperature"
            gpu.accent = .gray
        }
        
        // Update disk temperature and secondary info
        if s.diskTemp > 0 {
            disk.secondary = "\(Int(s.diskTemp))°C • \(temperatureBadge(for: s.diskTemp))"
            disk.accent = accentColor(for: s.diskTemp)
        } else {
            disk.secondary = "No Sensor Available"
            disk.accent = .gray
        }
        
        // Update battery secondary info with power readings
        battery.secondary = "Cycle \(s.batteryCycle) • In \(String(format: "%.1f", s.powerIn))W / Out \(String(format: "%.1f", s.powerOut))W"
        
        // Update overall temperature metric secondary info
        if validTemps.count > 0 {
            let tempStrings = [
                s.cpuTemp > 0 ? "CPU: \(Int(s.cpuTemp))°" : nil,
                s.gpuTemp > 0 ? "GPU: \(Int(s.gpuTemp))°" : nil,
                s.diskTemp > 0 ? "Disk: \(Int(s.diskTemp))°" : nil
            ].compactMap { $0 }
            
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
        
        // Update fans secondary info
        if s.fans > 0 {
            fans.secondary = "Fan Speed: \(Int(s.fans)) RPM"
            fans.accent = s.fans > 3000 ? .orange : (s.fans > 4000 ? .red : .primary)
        } else {
            fans.secondary = "Fan Information Unavailable"
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
            push(power, value: 0)
        }
        
        // Update GPU secondary info with more details
        if s.gpu > 0 {
            let gpuSecondary = s.gpuTemp > 0 ?
            "\(Int(s.gpuTemp))°C • \(temperatureBadge(for: s.gpuTemp)) • \(String(format: "%.1f", s.gpu))% Load" :
            "Load: \(String(format: "%.1f", s.gpu))%"
            gpu.secondary = gpuSecondary
            gpu.accent = s.gpu > 80 ? .orange : (s.gpu > 90 ? .red : accentColor(for: s.gpuTemp))
        }
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
}
