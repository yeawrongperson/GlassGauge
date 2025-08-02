
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

    private func push(_ model: MetricModel, value: Double) {
        let now = Date()
        model.primaryValue = value
        model.samples.append(SamplePoint(t: now, v: value))
        // Trim to current range window
        let cutoff = now.addingTimeInterval(-range.window)
        model.samples.removeAll { $0.t < cutoff }
    }

    private func tick() {
        let s = monitor.sample()
        push(cpu, value: s.cpu)
        push(gpu, value: s.gpu)
        push(memory, value: s.memory)
        push(disk, value: s.disk)
        push(network, value: s.network)
        push(battery, value: s.battery)
        push(fans, value: s.fans)
        push(power, value: s.power)

        if s.cpuTemp > 0 {
            cpu.secondary = "\(Int(s.cpuTemp))°C • \(temperatureBadge(for: s.cpuTemp))"
            cpu.accent = accentColor(for: s.cpuTemp)
        } else {
            cpu.secondary = "Sensor Not Found"
            cpu.accent = .gray
        }

        if s.gpuTemp > 0 {
            gpu.secondary = "\(Int(s.gpuTemp))°C • \(temperatureBadge(for: s.gpuTemp))"
            gpu.accent = accentColor(for: s.gpuTemp)
        } else {
            gpu.secondary = "Sensor Not Found"
            gpu.accent = .gray
        }

        if s.diskTemp > 0 {
            disk.secondary = "\(Int(s.diskTemp))°C • \(temperatureBadge(for: s.diskTemp))"
            disk.accent = accentColor(for: s.diskTemp)
        } else {
            disk.secondary = "Sensor Not Found"
            disk.accent = .gray
        }

        battery.secondary = "Cycle \(s.batteryCycle) • In \(String(format: "%.1f", s.powerIn))W / Out \(String(format: "%.1f", s.powerOut))W"
    }

    var allMetrics: [MetricModel] {
        [cpu, gpu, memory, disk, network, battery, fans, power, temps]
    }

    private func color(for temp: Double) -> Color {
        switch temp {
        case ..<40: return .teal
        case ..<70: return .blue
        case ..<85: return .orange
        default: return .red
        }
    }

    private func badge(for temp: Double) -> String {
        switch temp {
        case ..<70: return "ok"
        case ..<85: return "elevated"
        default: return "critical"
        }
    }

    private func healthBadge(for temp: Double) -> String {
        switch temp {
        case ..<70: return "ok"
        case ..<85: return "elevated"
        default: return "critical"
        }
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
