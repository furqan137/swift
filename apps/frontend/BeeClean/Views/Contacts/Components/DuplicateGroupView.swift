import SwiftUI
import Contacts

// MARK: - Duplicate Group View (Premium Merge Flow)
struct DuplicateGroupView: View {
    let group: DuplicateGroup
    @StateObject private var viewModel = ContactsViewModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showMergeConfirm = false
    @State private var isMerging = false

    // Animation states
    @State private var mergePhase: MergePhase = .preview
    @State private var cardOffsets: [CGFloat] = []
    @State private var cardOpacities: [Double] = []
    @State private var cardScales: [CGFloat] = []
    @State private var mergedCardScale: CGFloat = 0.8
    @State private var mergedCardOpacity: Double = 0
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var shimmerOffset: CGFloat = -200

    private enum MergePhase {
        case preview, merging, collapsed, success
    }

    private var preview: MergePreview { group.buildMergePreview() }

    var body: some View {
        NavigationStack {
            ZStack {
                BitepalCanvas()

                switch mergePhase {
                case .preview:
                    previewContent
                case .merging, .collapsed:
                    mergeAnimation
                case .success:
                    successContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Combine Contacts")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "1C1917"))
                            .frame(width: 32, height: 32)
                            .background(Color(hex: "F5F5F4"))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            cardOffsets = Array(repeating: 0, count: group.contacts.count)
            cardOpacities = Array(repeating: 1, count: group.contacts.count)
            cardScales = Array(repeating: 1, count: group.contacts.count)
        }
        .alert("Combine \(group.count) Contacts?", isPresented: $showMergeConfirm) {
            Button("Combine") {
                Task { await performMerge() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All phone numbers, emails, and other info will be combined into one contact. No data will be lost.")
        }
    }

    // MARK: - Preview Content

    private var previewContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Confidence badge
                confidenceBadge

                // Stacked source contacts
                VStack(spacing: 10) {
                    ForEach(Array(group.contacts.enumerated()), id: \.element.id) { index, contact in
                        sourceContactCard(contact, index: index)
                    }
                }

                // Arrow
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "D4D4D8"))
                    .padding(.vertical, 4)

                // Merged result preview
                mergedPreviewCard

                // Match reasons
                matchReasonPills

                // Merge button
                Button { showMergeConfirm = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Combine \(group.count) Contacts")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "1C1917"))
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Confidence Badge

    private var confidenceBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)

            Text("\(group.confidence.rawValue) confidence match")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(confidenceColor)

            Text("·")
                .foregroundColor(Color(hex: "D4D4D8"))

            Text("\(group.count) contacts")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "A1A1AA"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(confidenceColor.opacity(0.08))
        )
    }

    private var confidenceColor: Color {
        switch group.confidence {
        case .high: return Color(hex: "22C55E")
        case .medium: return Color(hex: "E5930E")
        case .low: return Color(hex: "DC2626")
        }
    }

    // MARK: - Source Contact Card

    private func sourceContactCard(_ contact: AppContact, index: Int) -> some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarGradient(for: contact.fullName))
                    .frame(width: 40, height: 40)
                Text(contact.initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let phone = contact.phoneNumbers.first {
                        Label(phone, systemImage: "phone.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "A1A1AA"))
                            .lineLimit(1)
                    }
                    if let email = contact.emails.first {
                        Label(email, systemImage: "envelope.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "A1A1AA"))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if contact.id == preview.primaryContact.id {
                Text("BEST")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "22C55E")))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "FAFAFA"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Merged Preview Card

    private var mergedPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(avatarGradient(for: preview.bestName))
                        .frame(width: 44, height: 44)
                    Text(String(preview.bestName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.bestName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))

                    if !preview.bestOrganization.isEmpty {
                        Text(preview.bestOrganization)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }
                }

                Spacer()

                Text("MERGED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "22C55E"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(hex: "22C55E").opacity(0.1))
                    )
            }

            Divider()

            // Kept phones
            if !preview.keptPhones.isEmpty {
                fieldSection(title: "Phone", icon: "phone.fill", values: preview.keptPhones, color: Color(hex: "22C55E"))
            }

            // Kept emails
            if !preview.keptEmails.isEmpty {
                fieldSection(title: "Email", icon: "envelope.fill", values: preview.keptEmails, color: Color(hex: "3B82F6"))
            }

            // Removed duplicates
            if preview.totalFieldsRemoved > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                    Text("\(preview.totalFieldsRemoved) duplicate value\(preview.totalFieldsRemoved == 1 ? "" : "s") removed")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "22C55E").opacity(0.2), lineWidth: 1)
        )
    }

    private func fieldSection(title: String, icon: String, values: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)

            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "1C1917"))
            }
        }
    }

    // MARK: - Match Reason Pills

    private var matchReasonPills: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(group.matchReasons), id: \.self) { reason in
                HStack(spacing: 4) {
                    Image(systemName: reasonIcon(reason.kind))
                        .font(.system(size: 9))
                    Text(reason.kind.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Color(hex: "78716C"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "F5F5F4"))
                .cornerRadius(6)
            }
        }
    }

    private func reasonIcon(_ kind: MatchReason.Kind) -> String {
        switch kind {
        case .exactName, .similarName: return "person.fill"
        case .phone: return "phone.fill"
        case .email: return "envelope.fill"
        case .organization: return "building.2.fill"
        case .birthday: return "gift.fill"
        case .photo: return "photo.fill"
        }
    }

    // MARK: - Merge Animation

    private var mergeAnimation: some View {
        ZStack {
            // Source cards collapsing
            ForEach(Array(group.contacts.enumerated()), id: \.element.id) { index, contact in
                if index < cardOffsets.count {
                    sourceContactCard(contact, index: index)
                        .offset(y: cardOffsets[index])
                        .opacity(cardOpacities[index])
                        .scaleEffect(cardScales[index])
                }
            }

            // Merged card emerging
            mergedPreviewCard
                .scaleEffect(mergedCardScale)
                .opacity(mergedCardOpacity)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Success Content

    private var successContent: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(hex: "22C55E").opacity(0.06))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color(hex: "22C55E"))
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

            VStack(spacing: 6) {
                Text("Contacts Merged")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("\(group.count - 1) duplicate\(group.count - 1 == 1 ? "" : "s") removed")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }

            // Stats
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(preview.totalFieldsKept)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "1C1917"))
                    Text("Fields kept")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
                VStack(spacing: 4) {
                    Text("\(preview.totalFieldsRemoved)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "A1A1AA"))
                    Text("Dupes removed")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
            }

            Spacer()

            Button { dismiss() } label: {
                Text(BCLoc.done.tr)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "1C1917"))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Perform Merge with Animation

    private func performMerge() async {
        // Phase 1: Cards collapse toward center
        mergePhase = .merging
        let centerY: CGFloat = 0
        for i in 0..<group.contacts.count {
            let delay = Double(i) * 0.06
            withAnimation(.easeInOut(duration: 0.4).delay(delay)) {
                if i < cardOffsets.count {
                    cardOffsets[i] = centerY
                    cardScales[i] = 0.9
                }
            }
        }

        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Phase 2: Cards fade out, merged card appears
        mergePhase = .collapsed
        for i in 0..<group.contacts.count {
            withAnimation(.easeOut(duration: 0.3)) {
                if i < cardOpacities.count {
                    cardOpacities[i] = 0
                    cardScales[i] = 0.7
                }
            }
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
            mergedCardScale = 1.0
            mergedCardOpacity = 1.0
        }

        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s

        // Phase 3: Actually merge contacts
        isMerging = true
        let success = await viewModel.merge(group: group, primaryIndex: group.contacts.firstIndex(of: group.bestPrimary) ?? 0)
        isMerging = false

        if success {
            HapticManager.shared.notify(.success)

            // Phase 4: Show success
            withAnimation(.easeOut(duration: 0.3)) {
                mergePhase = .success
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.2)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
        } else {
            // Merge failed — reset to preview
            withAnimation(.easeOut(duration: 0.3)) {
                mergePhase = .preview
            }
        }
    }

    // MARK: - Avatar Gradient

    private func avatarGradient(for name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        let colors: [(Color, Color)] = [
            (Color(hex: "4A90D9"), Color(hex: "2563B0")),
            (Color(hex: "8B5CF6"), Color(hex: "6D28D9")),
            (Color(hex: "D97BB5"), Color(hex: "B0477A")),
            (Color(hex: "2EC4A2"), Color(hex: "1A9B7E")),
            (Color(hex: "E5930E"), Color(hex: "C47A0A")),
            (Color(hex: "E8453C"), Color(hex: "C23028"))
        ]
        let pair = colors[hash % colors.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// FlowLayout defined in FiltersView.swift — shared across app
