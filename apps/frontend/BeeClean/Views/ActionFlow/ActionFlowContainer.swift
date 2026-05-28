import SwiftUI

// MARK: - Action Flow Container
//
// Thin SwiftUI view that switches between loading and summary based on
// the coordinator's phase. Presented via .fullScreenCover so the user
// can't swipe to dismiss during loading.

struct ActionFlowContainer: View {
    @ObservedObject var coordinator: ActionFlowCoordinator
    var onDismiss: () -> Void
    var onNextSection: (() -> Void)?

    var body: some View {
        ZStack {
            switch coordinator.phase {
            case .loading:
                ActionLoadingView(progress: coordinator.progress)
                    .transition(.opacity)
            case .summary:
                if let result = coordinator.result {
                    ActionSummaryView(
                        result: result,
                        onContinue: {
                            coordinator.dismiss()
                            onDismiss()
                        },
                        onNextSection: onNextSection
                    )
                    .transition(.opacity)
                }
            case .idle:
                EmptyView()
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.light)
    }
}
