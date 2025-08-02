
import SwiftUI
import Charts

struct MetricTile: View {
    @ObservedObject var model: MetricModel

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.icon)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.title).font(.callout).opacity(0.85)
                    Text(model.primaryString)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    if let sub = model.secondary {
                        Text(sub).font(.caption).opacity(0.7)
                    }
                    MiniChart(samples: model.samples)
                        .frame(height: 36)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MiniChart: View {
    let samples: [SamplePoint]
    var body: some View {
        Chart(samples) {
            LineMark(x: .value("t", $0.t), y: .value("v", $0.v))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.frame(maxWidth: .infinity) }
    }
}
