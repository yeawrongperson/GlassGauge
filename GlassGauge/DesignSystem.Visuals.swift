
import SwiftUI
import AppKit

// NSVisualEffect wrapper for SwiftUI (glass/blur)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.state = .active
        v.material = material
        v.blendingMode = blending
        v.isEmphasized = emphasized
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// Basic glass card container
struct GlassCard<Content: View>: View {
    let content: () -> Content
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                .blendMode(.overlay)
            content().padding(12)
        }
    }
}
