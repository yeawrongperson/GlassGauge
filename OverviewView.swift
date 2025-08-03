import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var state: AppState
    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(state.allMetrics) { metric in
                    // Use custom network tile for network metric
                    if metric.title == "Network" {
                        NetworkDualTile(networkIn: state.networkIn, networkOut: state.networkOut)
                    } else {
                        MetricTile(model: metric)
                    }
                }
            }
            .padding(16)
        }
        .background(VisualEffectView(material: .hudWindow))
    }
}
