
import Foundation
import SwiftUI
import Combine

enum SectionID: Hashable {
    case overview, sensors, alerts, logs
    case cpu, gpu, memory, disks, network, battery, fans, power, temps
    case settings
}

enum TimeRange: String, CaseIterable, Identifiable {
    case now, hour1, hour24
    var id: String { rawValue }
    var window: TimeInterval {
        switch self {
        case .now: return 5 * 60       // 5 minutes
        case .hour1: return 60 * 60    // 1 hour
        case .hour24: return 24 * 60 * 60
        }
    }
}


enum PowerDirection: Hashable {
    case charging
    case using
}

struct SamplePoint: Hashable, Identifiable {
    let t: Date
    let v: Double
    var direction: PowerDirection? = nil

    // Required for Identifiable
    var id: String {
        "\(t.timeIntervalSince1970)-\(v)"
    }
}


final class MetricModel: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    @Published var unit: String
    let formatter: NumberFormatter

    @Published var primaryValue: Double = 0
    @Published var secondary: String? = nil
    @Published var samples: [SamplePoint] = []
    @Published var accent: Color = .primary

    init(_ title: String, icon: String, unit: String) {
        self.title = title
        self.icon = icon
        self.unit = unit
        self.formatter = NumberFormatter()
        self.formatter.maximumFractionDigits = 1
        self.formatter.minimumFractionDigits = 0
    }

    var primaryString: String {
        if unit == "%" {
            return "\(Int(primaryValue))%"
        } else if let s = formatter.string(from: NSNumber(value: primaryValue)) {
            return unit.isEmpty ? s : "\(s) \(unit)"
        } else {
            return "\(primaryValue) \(unit)"
        }
    }
}
