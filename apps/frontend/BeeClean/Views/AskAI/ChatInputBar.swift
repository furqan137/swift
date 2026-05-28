import SwiftUI

// MARK: - Chat Input Bar (Apple Messages–style)
//
// Two independent floating elements — a capsule text pill and a circular
// send button — anchored directly to the bottom of the parent `VStack`.
// There is intentionally NO wrapper background, hairline divider, or
// material behind this row. The chat surface shows through all the way
// to the bottom safe area, matching iMessage.
//
// POSITIONING CONTRACT
// • Consumer MUST make this view the last element of a vertical stack
//   whose first element fills available space (a `ScrollView`). That
//   lets SwiftUI's built-in keyboard avoidance lift the bar with the
//   keyboard — no `.safeAreaInset`, no `.toolbar`, no manual offsets.
// • This view applies NO bottom padding of its own. The system's
//   bottom safe-area inset already clears the home indicator, and
//   any extra bottom padding here stacks on top of that inset and
//   produces the "floating ~40pt above the home indicator" look.
//   If the bar ends up visually flush against the indicator on a
//   given device, add `.padding(.bottom, 4)` to the root HStack —
//   NOT to any child — after confirming no parent container is
//   double-applying padding.
// • Do NOT wrap this view in any container that applies its own
//   background (material, `.systemBackground` rect, etc.) — that
//   recreates the grey "tray" we explicitly removed.

struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        // `.bottom` alignment keeps the send button visually pinned to
        // the bottom edge of the text pill as it grows from 1 → 5 lines,
        // which is how iMessage behaves. For a single-line pill the
        // difference vs `.center` is negligible, but this stays correct
        // when the user pastes a long prompt.
        HStack(alignment: .bottom, spacing: 8) {
            textPill
            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Text pill

    private var textPill: some View {
        TextField("Ask about your photos...", text: $text, axis: .vertical)
            .font(.system(size: 17))
            // `.primary` adapts: near-black in light mode, near-white in
            // dark mode. Don't hard-code a hex value here.
            .foregroundStyle(.primary)
            // `.plain` strips the default system field chrome (rounded
            // bordered style on iOS). Without this, TextField may paint
            // its own faint rule underneath our capsule in some states.
            .textFieldStyle(.plain)
            .focused(isFocused)
            .lineLimit(1...5)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Solid white — same token as the Compress storage card and
            // the chat header pills, so Ask Bee reads as one product
            // family. Pops cleanly against the BitepalCanvas gradient.
            .background(Color.white, in: Capsule())
    }

    // MARK: - Send button

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(canSend
                              ? Color.accentColor
                              : Color(.systemGray4))
                )
        }
        .disabled(!canSend)
        // No bottom padding here. An inner nudge would stack with the
        // parent HStack's safe-area placement and push the button into
        // (or past) the home indicator. `HStack(alignment: .bottom)` is
        // enough to keep the 36 pt circle flush with the last line of
        // the text pill as it grows to multiple lines.
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}

#Preview("Light") {
    StatefulPreview()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatefulPreview()
        .preferredColorScheme(.dark)
}

private struct StatefulPreview: View {
    @State private var text = ""
    @FocusState private var focus: Bool

    var body: some View {
        VStack(spacing: 0) {
            Color.gray.opacity(0.1).frame(maxHeight: .infinity)
            ChatInputBar(
                text: $text,
                isLoading: false,
                isFocused: $focus,
                onSend: {}
            )
        }
    }
}
