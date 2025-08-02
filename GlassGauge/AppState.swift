
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
    }

    var allMetrics: [MetricModel] {
        [cpu, gpu, memory, disk, network, battery, fans, power]
    }
}
