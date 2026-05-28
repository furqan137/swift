import SwiftUI

// MARK: - App Layout
struct AppLayout<Content: View>: View {
    let showBackButton: Bool
    let title: String?
    let showSettings: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    init(
        showBackButton: Bool = false,
        title: String? = nil,
        showSettings: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showBackButton = showBackButton
        self.title = title
        self.showSettings = showSettings
        self.content = content
    }

    var body: some View {
        ZStack {
            // Base
            Color.background.ignoresSafeArea()

            // Texture grid
            GridPatternView()
                .ignoresSafeArea()

            // Ambient atmosphere
            AmbientGlowView()

            // Film grain
            NoiseTextureView()

            // Cinematic vignette
            VignetteView()

            VStack(spacing: 0) {
                if showBackButton || title != nil || showSettings {
                    headerView
                }
                content()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Nav bar is hidden (disabling the system pop gesture), so restore
        // the left-edge swipe-right-to-dismiss whenever a back button exists.
        .modifier(ConditionalSwipeToDismiss(enabled: showBackButton))
    }

    private var headerView: some View {
        HStack {
            if showBackButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.foreground)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(Color.surfaceLight)
                                .overlay(
                                    Circle()
                                        .stroke(Color.border.opacity(0.6), lineWidth: 0.5)
                                )
                                .overlay(LinearGradient.glassGradient)
                                .clipShape(Circle())
                        )
                }
            }

            if let title = title {
                if showBackButton { Spacer() }

                Text(title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.foreground)
                    .tracking(-0.3)

                if showBackButton || showSettings { Spacer() }
            } else {
                Spacer()
            }

            if showSettings {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color(hex: "A1A1AA"))
                        .frame(width: 38, height: 38)
                }
            } else if showBackButton && title != nil {
                Color.clear.frame(width: 38, height: 38)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, 10)
    }
}

#Preview {
    AppLayout(showBackButton: true, title: "Test Page", showSettings: false) {
        VStack {
            Text("Content goes here")
                .foregroundColor(.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
