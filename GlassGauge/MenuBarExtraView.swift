
import SwiftUI

struct MenuBarExtraView: View {
    @EnvironmentObject var state: AppState
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(state.allMetrics.prefix(6)) { m in
                MiniTile(model: m)
            }
        }
        .padding(10)
        .background(VisualEffectView(material: .popover))
    }
}

struct MiniTile: View {
    @ObservedObject var model: MetricModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(model.title, systemImage: model.icon)
                .font(.caption)
                .labelStyle(.titleAndIcon)
            Text(model.primaryString)
                .font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(VisualEffectView(material: .menu))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                .blendMode(.overlay)
        )
    }
}
