import SwiftUI

/// Compatibility shim for iOS 26's GlassEffectContainer.
/// Provides a glass-like material background on iOS 17+.
struct GlassEffectContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if let spacing {
            VStack(spacing: spacing) {
                content
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
