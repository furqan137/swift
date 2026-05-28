import SwiftUI

// MARK: - FAQ View
struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedItems: Set<Int> = []

    private let faqs: [(question: String, answer: String)] = [
        (
            "How do you find duplicate photos?",
            "BeeClean scans every photo on your device using on-device image analysis. It compares the actual picture content, not just file names, so burst shots, screenshots of the same thing, and re-saved copies all get grouped together. Nothing leaves your phone, and you always pick which ones to keep."
        ),
        (
            "Is my data actually private?",
            "Yes. Your photos, videos, and contacts never leave your device. There is no cloud scan, no server copy, and no background upload. The only data that touches a server is your sign-in token and, if you use the Gmail cleanup feature, the action you take inside Gmail itself."
        ),
        (
            "If I delete something, is it gone forever?",
            "No. Photos and videos move to your Recently Deleted folder for 30 days, so you have plenty of time to restore anything. Emails you remove go to Gmail's Trash (also 30 days), and every email action inside BeeClean has an in-app undo button."
        ),
        (
            "How does Gmail cleanup work?",
            "You sign in with Google, which gives BeeClean a secure token to act on your behalf. We never see or store your password. From there you can bulk-clear promotions, swipe through emails one at a time with Quick Clean, or unsubscribe from senders you no longer want to hear from."
        ),
        (
            "What is the Secret Vault?",
            "A PIN-locked space for photos and videos you want kept separate from your camera roll. Files live inside BeeClean's private storage, so they won't show up in Photos and won't sync to iCloud. Only you can unlock it."
        ),
        (
            "What do I get with Premium?",
            "Unlimited cleaning across photos, videos, contacts, and email. Premium also unlocks the full Secret Vault, file compression, every charging animation, and the advanced contact tools. The free tier covers the basics with limits on how much you can clean at once."
        ),
        (
            "How do I cancel my subscription?",
            "Subscriptions are handled by Apple. Open the Settings app, tap your name, choose Subscriptions, find BeeClean, and tap Cancel. You keep Premium access until the end of your current billing period. For refunds, Apple Support is the right place to reach out."
        )
    ]

    private var inkBlack: Color { Color(red: 0.110, green: 0.098, blue: 0.090) }
    private var mutedText: Color { Color(red: 0.294, green: 0.333, blue: 0.388) }

    var body: some View {
        ZStack {
            // Bitepal gradient — matches the rest of the app
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.867, green: 0.882, blue: 0.949), location: 0.0),
                    .init(color: Color(red: 0.890, green: 0.902, blue: 0.933), location: 0.45),
                    .init(color: Color(red: 0.929, green: 0.933, blue: 0.937), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        HapticManager.shared.arrowNudge(.backward)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(inkBlack)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(Color.white.opacity(0.55))
                            )
                    }

                    Spacer()

                    Text("FAQ")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(inkBlack)

                    Spacer()

                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title block
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Got a question?")
                                .font(.custom("Anton-Regular", size: 38))
                                .foregroundColor(inkBlack)
                                .tracking(-0.4)

                            Text("Answers to the things people ask us most.")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(mutedText)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        VStack(spacing: 10) {
                            ForEach(Array(faqs.enumerated()), id: \.offset) { index, faq in
                                faqCard(index: index, question: faq.question, answer: faq.answer)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Contact block — compact so the email pill sits
                        // in the same scroll viewport as the last FAQ
                        // card. Tighter padding + smaller type, same
                        // soft translucent panel.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Still stuck?")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(inkBlack)

                            Text("Email us and a real human will get back to you fast.")
                                .font(.system(size: 13))
                                .foregroundColor(mutedText)

                            Text("support@beeclean.app")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(inkBlack)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.55))
                                )
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.65), lineWidth: 0.5)
                                )
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.42))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.65), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .preferredColorScheme(.light)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .hidesBottomNavBar()
        .environment(\.colorScheme, .light)
    }

    private func faqCard(index: Int, question: String, answer: String) -> some View {
        let isExpanded = expandedItems.contains(index)

        return Button {
            // Rotor tick on every expand/collapse — same family as
            // chip swaps elsewhere in the app. Cosmetic state change,
            // not a commit, so `filterChange()` is the right read.
            HapticManager.shared.filterChange()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                if expandedItems.contains(index) {
                    expandedItems.remove(index)
                } else {
                    expandedItems.insert(index)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text(question)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(inkBlack)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: 28, height: 28)
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(inkBlack)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                if isExpanded {
                    Rectangle()
                        .fill(inkBlack.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 18)

                    Text(answer)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(mutedText)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        FAQView()
    }
    .preferredColorScheme(.light)
}
