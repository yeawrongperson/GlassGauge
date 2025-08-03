import SwiftUI

struct SensorsView: View {
    @EnvironmentObject var state: AppState

    var filtered: [MetricModel] {
        let q = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return state.allMetrics }
        return state.allMetrics.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                // Header row
                HStack {
                    Text("Sensor").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Value").fontWeight(.semibold).frame(width: 100, alignment: .trailing)
                    Text("Unit").fontWeight(.semibold).frame(width: 60, alignment: .leading)
                    Text("Status").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.quaternary)
                
                // Data rows
                ForEach(filtered) { metric in
                    SensorRow(metric: metric)
                }
            }
        }
        .padding(8)
        .background(VisualEffectView(material: .hudWindow))
    }
}

struct SensorRow: View {
    @ObservedObject var metric: MetricModel
    
    var body: some View {
        HStack {
            // Sensor name with icon
            HStack {
                Image(systemName: metric.icon)
                    .foregroundStyle(metric.accent)
                    .frame(width: 20)
                Text(metric.title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Value
            Text(metric.primaryString)
                .monospacedDigit()
                .foregroundStyle(metric.accent)
                .fontWeight(.semibold)
                .frame(width: 100, alignment: .trailing)
            
            // Unit
            Text(metric.unit)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            
            // Status
            if let secondary = metric.secondary {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(.separator),
            alignment: .bottom
        )
    }
}
