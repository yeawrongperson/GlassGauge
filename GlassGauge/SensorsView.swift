
import SwiftUI

struct SensorsView: View {
    @EnvironmentObject var state: AppState

    var filtered: [MetricModel] {
        let q = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return state.allMetrics }
        return state.allMetrics.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        Table(filtered) {
            TableColumn("Sensor") { m in
                Label(m.title, systemImage: m.icon)
            }.width(min: 160)
            TableColumn("Value") { m in
                Text(m.primaryString).monospacedDigit()
            }.width(min: 100)
            TableColumn("Unit") { m in
                Text(m.unit)
            }.width(min: 60)
        }
        .padding(8)
        .background(VisualEffectView(material: .hudWindow))
    }
}
