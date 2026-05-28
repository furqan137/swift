import SwiftUI

// MARK: - New Task Launcher
//
// Standalone page presented after the user completes a Quick Cleanup task
// and taps "Start New Task" on the completion screen. Lets the user
// confirm before a fresh plan is generated.

struct NewTaskLauncherView: View {
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            glassBackdrop

            VStack(spacing: 0) {
                topBar

                Spacer()

                heroIcon
                    .padding(.bottom, 24)

                VStack(spacing: 10) {
                    Text("Ready for Another Round?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text("We'll scan your library for a fresh set of photos to review — duplicates, similars, screenshots, and more.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 28)

                featureGrid
                    .padding(.horizontal, 24)

                Spacer()

                startButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                cancelButton
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Backdrop

    private var glassBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "DDE1F2"), location: 0.0),
                .init(color: Color(hex: "DDE1F2"), location: 0.45),
                .init(color: Color(hex: "E3E6EE"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                HapticManager.shared.impact(.light)
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }

            Spacer()

            Text("New Task")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            // Invisible spacer to keep title centered.
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Hero Icon

    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "3A6B3A").opacity(0.12))
                .frame(width: 120, height: 120)
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(Color(hex: "3A6B3A"))
        }
    }

    // MARK: - Feature Grid

    private var featureGrid: some View {
        VStack(spacing: 12) {
            featureRow(
                icon: "doc.on.doc.fill",
                title: "Smart Selection",
                subtitle: "AI picks the best photos to review next"
            )
            featureRow(
                icon: "bolt.fill",
                title: "Quick Swipes",
                subtitle: "Swipe left to delete, right to keep"
            )
            featureRow(
                icon: "checkmark.shield.fill",
                title: "Safe by Default",
                subtitle: "Nothing is deleted until you confirm"
            )
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "3A6B3A").opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "3A6B3A"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: - Buttons

    private var startButton: some View {
        Button {
            HapticManager.shared.impact(.medium)
            onStart()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("Start New Task")
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color(hex: "3A6B3A"))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
            .shadow(color: Color(hex: "3A6B3A").opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var cancelButton: some View {
        Button {
            HapticManager.shared.impact(.light)
            onCancel()
        } label: {
            Text(BCLoc.notNow.tr)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}
