
import SwiftUI
import Charts

struct SensorDetailView: View {
    @ObservedObject var metric: MetricModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(metric.title, systemImage: metric.icon)
                    .font(.title2.bold())
                Spacer()
                Text(metric.primaryString)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)

            Chart(metric.samples) {
                LineMark(x: .value("Time", $0.t), y: .value(metric.unit, $0.v))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .frame(minHeight: 240)
            .glassBackground()

            Spacer()
        }
        .padding(16)
        .background(VisualEffectView(material: .hudWindow))
    }
}

extension View {
    func glassBackground() -> some View {
        self
            .padding()
            .background(VisualEffectView(material: .hudWindow))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    .blendMode(.overlay)
            )
    }
}
