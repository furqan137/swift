import SwiftUI

// MARK: - Support View
// Mirrors src/pages/SupportPage.tsx
struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let categories: [(icon: String, title: String, description: String, color: Color)] = [
        ("photo.fill", "Photos & Videos", "Issues with cleaning, duplicates, or compression", .categoryBlue),
        ("person.2.fill", "Contacts", "Help with duplicate or incomplete contacts", .categoryGreen),
        ("envelope.fill", "Email", "Gmail connection or cleanup issues", .categoryPurple),
        ("lock.fill", "Secret Vault", "PIN recovery or vault access problems", .categoryPink),
        ("bolt.fill", "Charging Animations", "Setup help or animation issues", .categoryOrange),
        ("creditcard.fill", "Billing & Subscription", "Payment, refunds, or plan changes", .categoryYellow),
    ]
    
    var body: some View {
        AppLayout(showBackButton: true, title: "Support") {
            ScrollView {
                VStack(spacing: 24) {
                    // Contact info card
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.primaryColor.opacity(0.15))
                                .frame(width: 64, height: 64)
                            
                            Image(systemName: "headphones.circle.fill")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.primaryColor)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Need Help?")
                                .font(.titleMedium)
                                .foregroundColor(.foreground)
                            
                            Text("We typically respond within 24 hours")
                                .font(.bodySmall)
                                .foregroundColor(.mutedForeground)
                        }
                        
                        // Email button
                        Button {
                            // Open email
                            if let url = URL(string: "mailto:support@beeclean.app") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                Text("support@beeclean.app")
                            }
                            .font(.labelMedium)
                            .foregroundColor(.primaryColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.primaryColor.opacity(0.15))
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .cardSurface(.elevated)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Categories
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What do you need help with?")
                            .font(.titleSmall)
                            .foregroundColor(.foreground)
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 0) {
                            ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                                SupportCategoryRow(
                                    icon: category.icon,
                                    title: category.title,
                                    description: category.description,
                                    color: category.color,
                                    showDivider: index < categories.count - 1
                                )
                            }
                        }
                        .cardSurface(.standard)
                        .padding(.horizontal, 20)
                    }
                    
                    // Additional resources
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Additional Resources")
                            .font(.titleSmall)
                            .foregroundColor(.foreground)
                            .padding(.horizontal, 20)
                        
                        HStack(spacing: 12) {
                            ResourceButton(
                                icon: "book.fill",
                                title: "User Guide",
                                color: .categoryBlue
                            ) {
                                if let url = URL(string: "https://beeclean.app/guide") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            
                            ResourceButton(
                                icon: "play.rectangle.fill",
                                title: "Video Tutorials",
                                color: .categoryRed
                            ) {
                                if let url = URL(string: "https://beeclean.app/tutorials") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Support Category Row
struct SupportCategoryRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let showDivider: Bool
    
    var body: some View {
        Button {
            let subject = "BeeClean Support: \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
            let body = "Hi BeeClean team,\n\nI need help with \(title.lowercased()).\n\nIssue details:\n\n".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:support@beeclean.app?subject=\(subject)&body=\(body)") {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(color.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.labelLarge)
                            .foregroundColor(.foreground)
                        
                        Text(description)
                            .font(.bodySmall)
                            .foregroundColor(.mutedForeground)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mutedForeground)
                }
                .padding(16)
                
                if showDivider {
                    Divider()
                        .background(Color.border)
                        .padding(.leading, 76)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Resource Button
struct ResourceButton: View {
    let icon: String
    let title: String
    let color: Color
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.labelMedium)
                    .foregroundColor(.foreground)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .cardSurface(.standard)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SupportView()
    }
    .preferredColorScheme(.dark)
}
