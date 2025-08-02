
import Foundation
import Combine
import SwiftUI

final class AppState: ObservableObject {
    @Published var selection: SectionID = .overview
    @Published var range: TimeRange = .now
    @Published var searchText: String = ""

    // Core metrics
    @Published var cpu = MetricModel("CPU", icon: "cpu", unit: "%")
    @Published var gpu = MetricModel("GPU", icon: "rectangle.portrait.on.rectangle.portrait.angled", unit: "%")
    @Published var memory = MetricModel("Memory", icon: "memorychip", unit: "GB")
    @Published var disk = MetricModel("Disk", icon: "externaldrive", unit: "KB/s")
    @Published var network = MetricModel("Network", icon: "wifi", unit: "KB/s")
    @Published var battery = MetricModel("Battery", icon: "battery.100", unit: "%")
    @Published var fans = MetricModel("Fans", icon: "fanblades", unit: "RPM")
    @Published var power = MetricModel("Power", icon: "bolt.fill", unit: "W")

    @Published var pinnedIDs: Set<UUID> = []

    private var timer: Timer?

    init() {
        // Seed initial values
        cpu.primaryValue = 32; gpu.primaryValue = 18
        memory.primaryValue = 19.9; disk.primaryValue = 118
        network.primaryValue = 145; battery.primaryValue = 88
        fans.primaryValue = 1431; power.primaryValue = -6.7

        startMockPolling()
    }

    func startMockPolling() {
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
        // Simple noise generator for mock data
        func n(_ base: Double, _ spread: Double) -> Double { max(0, base + Double.random(in: -spread...spread)) }

        push(cpu, value: min(100, n(cpu.primaryValue, 5)))
        push(gpu, value: min(100, n(gpu.primaryValue, 8)))
        push(memory, value: max(0, n(memory.primaryValue, 0.1)))
        push(disk, value: max(0, n(disk.primaryValue, 20)))
        push(network, value: max(0, n(network.primaryValue, 30)))
        push(battery, value: min(100, max(0, n(battery.primaryValue + (Bool.random() ? -0.1: 0.0), 0.2))))
        push(fans, value: max(0, n(fans.primaryValue, 40)))
        push(power, value: n(power.primaryValue, 0.6))
    }

    var allMetrics: [MetricModel] {
        [cpu, gpu, memory, disk, network, battery, fans, power]
    }
}
