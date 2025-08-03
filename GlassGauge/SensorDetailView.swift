
import SwiftUI
import Charts

struct SensorDetailView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var metric: MetricModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if metric.id == state.power.id {
                Chart {
                    ForEach(segmentSamples(metric.samples)) { segment in
                        ForEach(segment.points) { point in
                            LineMark(x: .value("Time", point.t), y: .value(metric.unit, point.v))
                        }
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color(for: segment.state))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
            } else {
                Chart(metric.samples) {
                    LineMark(x: .value("Time", $0.t), y: .value(metric.unit, $0.v))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(metric.accent)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
            }
            .frame(minHeight: 240)
            .glassBackground(emphasized: !state.reduceMotion)
            .animation(state.reduceMotion ? nil : .default, value: metric.samples)

            Spacer()
        }
        .padding(16)
        .background(VisualEffectView(material: .hudWindow))
    }
}

private struct SampleSegment: Identifiable {
    let id = UUID()
    let state: PowerDirection?
    var points: [SamplePoint]
}

private func segmentSamples(_ samples: [SamplePoint]) -> [SampleSegment] {
    var result: [SampleSegment] = []
    guard !samples.isEmpty else { return result }
    var currentState = samples.first?.direction
    var currentPoints: [SamplePoint] = []

    for s in samples {
        if s.direction == currentState {
            currentPoints.append(s)
        } else {
            result.append(SampleSegment(state: currentState, points: currentPoints))
            currentState = s.direction
            currentPoints = [s]
        }
    }
    if !currentPoints.isEmpty {
        result.append(SampleSegment(state: currentState, points: currentPoints))
    }
    return result
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
