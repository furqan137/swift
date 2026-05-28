import SwiftUI
import Contacts

extension MergePreviewView {

    // MARK: - Preview List

    var previewListContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ForEach(visibleGroups) { group in
                    groupPreviewCard(group)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                }

                // "Before you merge" footer flows DIRECTLY under the
                // last merged card (not pinned at bottom). User wants
                // the explainer immediately adjacent to the merged
                // result so the eye reads "what's happening + how
                // it's safe" as one unit, not as two separate visual
                // anchors at the top and bottom of the page.
                mergeFooter
            }
            .padding(.horizontal, 20)
            // Tightened from 22 → 8 so the first merged card sits
            // immediately under the "{N} Contact(s)" subtitle in the
            // header — no more 38pt visual gap.
            .padding(.top, 8)
            // Reserve room for the sticky CTA strip at the bottom of
            // the screen so the footer's last line doesn't slide
            // BEHIND the pinned button.
            .padding(.bottom, 140)
        }
    }

    /// Sticky footer pinned above the merge CTA. Always visible — fills
    /// the lower third of the screen so the layout never reads hollow.
    /// Three short, scannable lines explain what merge will do, why it's
    /// safe, and where the backup goes. Tighter copy than the inline
    /// version that lived in the scroll view.
    var mergeFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                Text("Before you merge")
                    .font(.custom("Poppins-Bold", size: 13))
                    .foregroundColor(Color(hex: "1C1917"))
                    .tracking(0.4)
            }

            footerBullet(
                icon: "phone.fill",
                text: "These contacts share a phone number — that's how we matched them."
            )
            footerBullet(
                icon: "rectangle.stack.fill",
                text: "Merging keeps every saved detail (numbers, emails, notes) on one contact."
            )
            footerBullet(
                icon: "shield.lefthalf.filled",
                text: "Back up first — saves a snapshot in the Backups tab so you can undo any time."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contactGlass(cornerRadius: 18)
    }

    func footerBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "78716C"))
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "57534E"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Group Preview Card

    func groupPreviewCard(_ group: DuplicateGroup) -> some View {
        let selected = selectedContactsInGroup(group)
        // Pick the richest selected contact as the preview's primary so
        // the name + thumbnail show the most complete record. Mirrors the
        // primary-selection logic in mergeSelectedContactsByGroup.
        let primary = selected.max(by: { completenessScore($0) < completenessScore($1) })
            ?? selected.first

        let combinedPhones = combinedPhoneStrings(from: selected)
        let phoneCount = uniquePhoneCount(from: selected)
        let emailCount = uniqueEmailCount(from: selected)
        let confidence = group.confidence

        return VStack(alignment: .leading, spacing: 0) {
            // Header: confidence dot + count + dismiss X. The confidence
            // dot — green for "high", amber for "medium", red for "low" —
            // is something Cleanup doesn't show. Reading "high confidence"
            // before merging gives the user a one-glance signal that the
            // algorithm is sure about this group, while a yellow dot
            // invites them to peek at the preview before committing.
            HStack(spacing: 8) {
                Circle()
                    .fill(confidenceColor(confidence))
                    .frame(width: 7, height: 7)

                Text("\(selected.count) Contacts Merged")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                Button {
                    HapticManager.shared.impact(.light)
                    // Remove THIS group's currently-selected contact IDs
                    // from the parent's selection. That single mutation
                    // both: (a) drops the group out of `visibleGroups`
                    // here (count<2 → not visible), and (b) clears the
                    // checkboxes back in the parent's duplicates list.
                    // Without this, the user dismisses a group from the
                    // preview but the parent still thinks they're
                    // marked-for-merge — selection drift bug.
                    let dismissIds = Set(selectedContactsInGroup(group).map(\.id))
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        selectedIds.subtract(dismissIds)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(hex: "EEEDF3")))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Tappable merged-preview row — opens CNContactViewController
            // populated with the in-memory merged result (no save).
            Button {
                HapticManager.shared.impact(.light)
                if let preview = buildPreviewContact(for: group) {
                    previewContact = PreviewContact(contact: preview)
                }
            } label: {
                HStack(spacing: 12) {
                    if let primary = primary {
                        contactAvatar(primary, size: 44)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(primary?.fullName ?? group.name)
                            .font(.custom("Poppins-Bold", size: 16))
                            .foregroundColor(Color(hex: "1C1917"))
                            .lineLimit(1)

                        if !combinedPhones.isEmpty {
                            Text(combinedPhones)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "78716C"))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(Color(hex: "78716C"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    // Lavender-tinted nested pill instead of a
                    // white-on-white card-on-card. The outer card is
                    // already a chrome-glass surface, so a white inner
                    // row just sat there flat — the lavender fill
                    // (mirrors the back-button chip + dismiss-X chip
                    // tint already used elsewhere in this view) makes
                    // the merged-result row visually inset INTO the
                    // glass card, like a slot. Hairline espresso edge
                    // keeps the row's silhouette crisp.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "EEEDF3"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "1C1917").opacity(0.06), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            // "Kept" stats — the small print Cleanup omits. Tells the user
            // exactly how many distinct phone numbers / emails will live
            // on the merged contact. Reads as honest UX: no surprises
            // about which fields survive the merge.
            HStack(spacing: 6) {
                if phoneCount > 0 {
                    statPill(
                        icon: "phone.fill",
                        text: "\(phoneCount) number\(phoneCount == 1 ? "" : "s") kept"
                    )
                }
                if emailCount > 0 {
                    statPill(
                        icon: "envelope.fill",
                        text: "\(emailCount) email\(emailCount == 1 ? "" : "s") kept"
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        // Chrome-glass card surface — mirrors the BottomNavBar's
        // lighting model so the merge-preview cards read as crafted
        // hardware, not flat sticker rectangles. Stack (bottom up):
        //   1. Body gradient (white → warm-cream) — gives the card a
        //      lit-from-above look against the cool-gray canvas.
        //   2. Top rim-light highlight via .plusLighter — the same
        //      "edge catches the light" cue the nav bar uses.
        //   3. Bottom inner shadow — hint of depth at the lower edge.
        //   4. Outer hairline silhouette so the card stays crisp on
        //      busy gradients.
        //   5. Tight + wide drop shadow stack — mirrors the nav bar's
        //      shadow signature so the two surfaces visibly share an
        //      elevation plane.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(hex: "F8F9FB")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.8
                    )
                    .blendMode(.plusLighter)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.06)
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            }
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 8)
    }

}
