import SwiftUI
import Charts

struct NetworkDetailView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var networkIn: MetricModel
    @ObservedObject var networkOut: MetricModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                trafficSummaryCards
                detailChartsSection
                Spacer(minLength: 50)
            }
            .padding(16)
        }
        .background(VisualEffectView(material: .hudWindow))
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        HStack {
            Label("Network Activity", systemImage: "wifi")
                .font(.title2.bold())
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.network.primaryString)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
    }
    
    private var trafficSummaryCards: some View {
        HStack(spacing: 12) {
            incomingTrafficCard
            outgoingTrafficCard
        }
    }
    
    private var incomingTrafficCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Incoming")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(networkIn.secondary ?? "Incoming data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(networkIn.primaryString)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.green)
        }
        .padding()
        .glassBackground(emphasized: !state.reduceMotion)
    }
    
    private var outgoingTrafficCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outgoing")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(networkOut.secondary ?? "Outgoing data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(networkOut.primaryString)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.red)
        }
        .padding()
        .glassBackground(emphasized: !state.reduceMotion)
    }
    
    private var detailChartsSection: some View {
        HStack(spacing: 12) {
            incomingDetailChart
            outgoingDetailChart
        }
    }
    
    private var incomingDetailChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.green)
                Text("Incoming Detail")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
            
            Chart(cleanIncomingSamples) { sample in
                createSimpleLineMark(sample: sample, color: .green)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel("")
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        let doubleValue = value.as(Double.self) ?? 0
                        Text("\(doubleValue, specifier: "%.0f")")
                            .font(.caption2)
                    }
                }
            }
            .chartYScale(domain: 0...max(getCleanIncomingMax(), 25))
            .chartXScale(domain: getTimeRange())
            .frame(height: 120)
        }
        .padding()
        .glassBackground(emphasized: !state.reduceMotion)
    }
    
    private var outgoingDetailChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.red)
                Text("Outgoing Detail")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
            
            Chart(cleanOutgoingSamples) { sample in
                createSimpleLineMark(sample: sample, color: .red)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel("")
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        let doubleValue = value.as(Double.self) ?? 0
                        Text("\(doubleValue, specifier: "%.0f")")
                            .font(.caption2)
                    }
                }
            }
            .chartYScale(domain: 0...max(getCleanOutgoingMax(), 25))
            .chartXScale(domain: getTimeRange())
            .frame(height: 120)
        }
        .padding()
        .glassBackground(emphasized: !state.reduceMotion)
    }
    
    private func createSimpleLineMark(sample: SamplePoint, color: Color) -> some ChartContent {
        LineMark(x: .value("Time", sample.t), y: .value("KB/s", sample.v))
            .interpolationMethod(.linear)
            .foregroundStyle(color)
    }
    
    // MARK: - Data Processing
    
    private var cleanIncomingSamples: [SamplePoint] {
        cleanNetworkData(networkIn.samples)
    }
    
    private var cleanOutgoingSamples: [SamplePoint] {
        cleanNetworkData(networkOut.samples)
    }
    
    private func cleanNetworkData(_ samples: [SamplePoint]) -> [SamplePoint] {
        guard samples.count > 1 else { return samples }
        
        let now = Date()
        let timeWindow = state.range.window
        
        // Sort by time and filter to current time window first
        let sortedSamples = samples
            .sorted { $0.t < $1.t }
            .filter { now.timeIntervalSince($0.t) <= timeWindow }
        
        guard sortedSamples.count > 1 else { return sortedSamples }
        
        // Remove extreme outliers and old spikes
        var cleanedSamples: [SamplePoint] = []
        
        for (index, sample) in sortedSamples.enumerated() {
            // Cap values to prevent extreme spikes
            let cappedValue = min(sample.v, 100.0) // Much lower cap to prevent spikes
            
            // Check for time gaps - if there's a big gap, don't include old isolated points
            if index == 0 {
                // Always include first point
                cleanedSamples.append(SamplePoint(t: sample.t, v: max(cappedValue, 0)))
            } else {
                let timeSinceLastPoint = sample.t.timeIntervalSince(sortedSamples[index - 1].t)
                
                // If there's a gap bigger than 30 seconds, start fresh to avoid connecting lines
                if timeSinceLastPoint > 30.0 {
                    // Clear old points and start with current point
                    cleanedSamples = [SamplePoint(t: sample.t, v: max(cappedValue, 0))]
                } else {
                    // Normal case - add the point
                    cleanedSamples.append(SamplePoint(t: sample.t, v: max(cappedValue, 0)))
                }
            }
        }
        
        // Keep only the most recent continuous data (last 50 points max)
        if cleanedSamples.count > 50 {
            cleanedSamples = Array(cleanedSamples.suffix(50))
        }
        
        return cleanedSamples
    }
    
    private func getTimeRange() -> ClosedRange<Date> {
        let now = Date()
        let start = now.addingTimeInterval(-state.range.window)
        return start...now
    }
    
    private func getCleanMaxValue() -> Double {
        let maxIn = cleanIncomingSamples.map(\.v).max() ?? 0
        let maxOut = cleanOutgoingSamples.map(\.v).max() ?? 0
        return max(maxIn, maxOut)
    }
    
    private func getCleanIncomingMax() -> Double {
        cleanIncomingSamples.map(\.v).max() ?? 0
    }
    
    private func getCleanOutgoingMax() -> Double {
        cleanOutgoingSamples.map(\.v).max() ?? 0
    }
}
