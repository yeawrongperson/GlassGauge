
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = false
    @State private var reduceMotion = false
    @State private var profile: SamplingProfile = .balanced

    var body: some View {
        Form {
            Picker("Sampling Profile", selection: $profile) {
                ForEach(SamplingProfile.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
            Toggle("Reduce motion", isOn: $reduceMotion)
            Picker("Default Range", selection: $state.range) {
                Text("Now").tag(TimeRange.now)
                Text("1h").tag(TimeRange.hour1)
                Text("24h").tag(TimeRange.hour24)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

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
