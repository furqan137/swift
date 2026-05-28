import SwiftUI

// MARK: - Recommendation Engine

struct EmailRecommendation: Identifiable {
    let id: String
    let label: String        // "Biggest Win", "Quick Clean", "Stop Future Clutter"
    let headline: String
    let detail: String
    let count: Int
    let color: Color
    let icon: String
    let action: RecommendationAction

    enum RecommendationAction {
        case category(GmailCategory)
        case unsubscribe
    }
}

struct EmailInsight {
    let hero: EmailRecommendation?
    let secondary: [EmailRecommendation]
    let clutterDescription: String   // "Heavy", "Moderate", "Light"
    let lowPriorityCount: Int        // promotions + updates + forums + spam
}

enum EmailRecommendationEngine {

    static func analyze(categories: [GmailCategory], senderCount: Int) -> EmailInsight {
        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        let promos = catMap["promotions"]?.count ?? 0
        let updates = catMap["updates"]?.count ?? 0
        let social = catMap["social"]?.count ?? 0
        let forums = catMap["forums"]?.count ?? 0
        let spam = catMap["spam"]?.count ?? 0

        let lowPriority = promos + updates + forums + spam

        // Clutter description
        let clutterDescription: String
        if lowPriority > 10000 { clutterDescription = "Heavy" }
        else if lowPriority > 2000 { clutterDescription = "Moderate" }
        else if lowPriority > 500 { clutterDescription = "Light" }
        else { clutterDescription = "Minimal" }

        var recs: [EmailRecommendation] = []

        // 1. Biggest Win — largest cleanable category
        let cleanable: [(id: String, count: Int, name: String, icon: String, color: Color)] = [
            ("promotions", promos, "Promotions", "tag", Color(hex: "D97706")),
            ("updates", updates, "Updates", "arrow.down.circle", Color(hex: "059669")),
            ("social", social, "Social Media", "person.2", Color(hex: "2563EB")),
            ("forums", forums, "Forums", "quote.bubble", Color(hex: "7C3AED")),
        ]

        if let biggest = cleanable.max(by: { $0.count < $1.count }), biggest.count > 100,
           let cat = catMap[biggest.id] {
            recs.append(EmailRecommendation(
                id: "biggest",
                label: "Biggest Win",
                headline: "\(EmailFormatters.numFmt(biggest.count)) \(biggest.name) emails",
                detail: "Your largest cleanup opportunity. Review and clear low-value \(biggest.name.lowercased()) to reclaim your inbox.",
                count: biggest.count,
                color: biggest.color,
                icon: biggest.icon,
                action: .category(cat)
            ))
        }

        // 2. Quick Clean — spam is always safe
        if spam > 10, let spamCat = catMap["spam"] {
            recs.append(EmailRecommendation(
                id: "quick",
                label: "Quick Clean",
                headline: "\(EmailFormatters.numFmt(spam)) spam emails",
                detail: "Safe to clear. These are already flagged by Gmail as junk or phishing.",
                count: spam,
                color: Color(hex: "DC2626"),
                icon: "shield.slash",
                action: .category(spamCat)
            ))
        }

        // 3. Stop Future Clutter — unsubscribe
        if senderCount > 5 {
            recs.append(EmailRecommendation(
                id: "unsub",
                label: "Stop Future Clutter",
                headline: "\(senderCount) senders to review",
                detail: "Unsubscribe from senders you no longer read to reduce future inbox noise.",
                count: senderCount,
                color: Color(hex: "0891B2"),
                icon: "bell.slash",
                action: .unsubscribe
            ))
        }

        // Hero = first rec, secondary = rest
        let hero = recs.first
        let secondary = Array(recs.dropFirst().prefix(2))

        return EmailInsight(
            hero: hero,
            secondary: secondary,
            clutterDescription: clutterDescription,
            lowPriorityCount: lowPriority
        )
    }
}

// MARK: - Hero Insight Card

struct HeroInsightCard: View {
    let recommendation: EmailRecommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                // Label
                Text(recommendation.label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(recommendation.color)
                    .tracking(0.5)

                // Headline
                Text(recommendation.headline)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                // Detail
                Text(recommendation.detail)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "78716C"))
                    .lineSpacing(2)

                // CTA
                HStack(spacing: 6) {
                    Text("Review now")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(hex: "1C1917"))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(recommendation.color.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(recommendation.color.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(ContactTileButtonStyle())
    }
}

// MARK: - Secondary Recommendation Card

struct SecondaryRecommendationCard: View {
    let recommendation: EmailRecommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: recommendation.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(recommendation.color)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(recommendation.color.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(recommendation.color)
                        .tracking(0.3)

                    Text(recommendation.headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "D4D4D8"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(ContactTileButtonStyle())
    }
}
