import SwiftUI
import Charts

struct SensorDetailView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var metric: MetricModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            chartSection
            Spacer()
        }
        .padding(16)
        .background(VisualEffectView(material: .hudWindow))
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            Label(metric.title, systemImage: metric.icon)
                .font(.title2.bold())
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(metric.primaryString)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let secondary = metric.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var chartSection: some View {
        let chartColor = metric.id == state.power.id ? color(for: metric.samples.last?.direction) : metric.accent

        return Chart(metric.samples) { sample in
            LineMark(
                x: .value("Time", sample.t),
                y: .value(metric.unit, sample.v)
            )
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .foregroundStyle(chartColor)
        .frame(minHeight: 240)
        .glassBackground(emphasized: !state.reduceMotion)
        .animation(state.reduceMotion ? nil : .default, value: metric.samples)
    }
}

private func color(for state: PowerDirection?) -> Color {
    switch state {
    case .charging: return .green
    case .using: return .red
    default: return .gray
    }
}

extension View {
    func glassBackground(emphasized: Bool = true) -> some View {
        self
            .padding()
            .background(VisualEffectView(material: .hudWindow, emphasized: emphasized))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    .blendMode(.overlay)
            )
    }
}
