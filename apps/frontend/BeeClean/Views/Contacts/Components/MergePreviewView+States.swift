import SwiftUI
import Contacts

extension MergePreviewView {

    // MARK: - Empty State

    var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("No Preview Available")
                .font(.custom("Poppins-Bold", size: 20))
                .foregroundColor(Color(hex: "1C1917"))
            Text("Go back and select duplicate contacts to see a preview")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "A1A1AA"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Success State (post-merge)
    //
    // Shown after `runMerge` completes. Replaces the generic
    // "no preview available" copy with a real celebration: green
    // checkmark, headline count of groups merged, fine-print count of
    // duplicate contacts removed, and a Done CTA that dismisses back
    // to the duplicates list. Bitepal-themed — espresso ink, lavender
    // pill chrome, no Cleanup-blue.
    var successView: some View {
        VStack(spacing: 18) {
            Spacer()

            // Soft mint puck behind a checkmark — same visual rhythm as
            // the streak badge / settings cog: shape + tinted halo +
            // glyph. Green is the only non-Bitepal color we keep, but
            // it's communicating "success" so it earns the screen real
            // estate.
            ZStack {
                Circle()
                    .fill(Color(hex: "10B981").opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .fill(Color(hex: "10B981").opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "059669"))
            }

            VStack(spacing: 6) {
                Text(mergedGroupCount == 1
                     ? "1 Contact Merged"
                     : "\(mergedGroupCount) Contacts Merged")
                    .font(.custom("Poppins-Bold", size: 24))
                    .foregroundColor(Color(hex: "1C1917"))
                    .contentTransition(.numericText(countsDown: false))

                if mergedDeletedCount > 0 {
                    Text(mergedDeletedCount == 1
                         ? "Removed 1 duplicate from your Contacts"
                         : "Removed \(mergedDeletedCount) duplicates from your Contacts")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "78716C"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                }
            }

            Spacer()

            // Done CTA — Bitepal espresso fill (no Cleanup blue).
            // Mirrors the segmented control's active pill so the same
            // "this is the active call" cue carries across surfaces.
            Button {
                HapticManager.shared.impact(.light)
                BottomNavBarVisibility.shared.releaseHide()
                dismiss()
            } label: {
                Text(BCLoc.done.tr)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "2A2724"),
                                        Color(hex: "0F0E0C")
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
    }

    // MARK: - Merge CTA

    /// Wraps the pinned bottom CTA in a backdrop strip so the scroll
    /// content underneath doesn't visibly bleed past the button. Same
    /// helper pattern as `ContactListView.bottomCTABackdrop`.
    @ViewBuilder
    func bottomCTABackdrop<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color(hex: "E3E6EE").opacity(0),
                    Color(hex: "E3E6EE").opacity(1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)

            content()
                .frame(maxWidth: .infinity)
                .background(Color(hex: "E3E6EE"))
        }
    }

    var mergeCTA: some View {
        Button {
            HapticManager.shared.impact(.medium)
            showConfirmAlert = true
        } label: {
            HStack(spacing: 10) {
                if isMerging {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(isMerging ? "Merging…" : "Merge \(totalMergedContacts) Contact\(totalMergedContacts == 1 ? "" : "s")")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    // Bitepal espresso fill — same family as the
                    // segmented control's active pill and the
                    // contacts list's "See Merge Preview" CTA.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "2A2724"),
                                    Color(hex: "0F0E0C")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Top rim-light (plusLighter) — premium "lit-from-
                    // above" cue at button scale.
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.8
                        )
                        .blendMode(.plusLighter)
                }
            )
            .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
            .shadow(color: Color.black.opacity(0.18), radius: 22, y: 10)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isMerging)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        // Was 34pt — eaten partially by the parent's
        // `.ignoresSafeArea(.container, edges: .bottom)`. 38pt clears
        // the home-indicator zone with real breathing room so the CTA
        // reads as a button, not a banner welded to the screen edge.
        .padding(.bottom, 38)
    }

    // MARK: - Backup Prompt

    var backupPromptSheet: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 6)

            VStack(spacing: 10) {
                Text("Save a backup before merging?")
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("We'll save a snapshot of all your contacts to the Backups tab. If anything looks off after merging, restore it in one tap.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "78716C"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                HapticManager.shared.impact(.medium)
                Task { await runBackupThenMerge() }
            } label: {
                HStack(spacing: 8) {
                    if isBackingUp {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    }
                    Text(isBackingUp ? "Backing up…" : "Back up")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    // Bitepal espresso — matches the merge CTA so both
                    // primary actions in this flow share the same fill.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "2A2724"),
                                    Color(hex: "0F0E0C")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: Color.black.opacity(0.22), radius: 12, y: 5)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isBackingUp || isMerging)
            .padding(.horizontal, 20)

            Button {
                HapticManager.shared.impact(.light)
                showBackupPrompt = false
                Task { await runMerge() }
            } label: {
                Text("No, Thanks")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "78716C"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isBackingUp || isMerging)
            .padding(.bottom, 28)
        }
        .padding(.top, 22)
    }

    // MARK: - Actions

    func runBackupThenMerge() async {
        isBackingUp = true
        // BackupService writes to local app storage — fully on-device,
        // visible in the Backups tile so the user can restore.
        let succeeded = await backupService.createBackup(contacts: viewModel.allContacts)
        isBackingUp = false
        // On failure, DO NOT proceed to merge. The whole point of the
        // "back up first" prompt is to make changes reversible — silently
        // committing the merge after a failed backup defeats the
        // affordance the user just opted into. Surface an alert and let
        // them retry or explicitly skip the backup via "No, Thanks".
        guard succeeded else {
            backupErrorMessage = "Couldn't write the backup. Your contacts are unchanged. Try again, or pick \"No, Thanks\" to merge without a backup."
            return
        }
        showBackupPrompt = false
        await runMerge()
    }

    func runMerge() async {
        isMerging = true
        let result = await onMerge()
        isMerging = false
        HapticManager.shared.notify(.success)
        // Capture the merge totals BEFORE flipping `didMerge`, otherwise
        // the success view has nothing concrete to show — previously
        // we flipped to a generic "Go back and select duplicate
        // contacts to see a preview" empty state, which was the wrong
        // affordance for a freshly-completed merge. The success view
        // now reads "{N} Contacts Merged" + "Removed {M} duplicate(s)"
        // and gives the user a Done CTA back to the duplicates list.
        mergedGroupCount = result.merged
        mergedDeletedCount = result.deleted
        withAnimation(.easeInOut(duration: 0.25)) {
            didMerge = true
        }
    }

    // MARK: - Preview Contact Builder

    /// Builds an in-memory `CNContact` representing what the merged
    /// result would look like — used for the read-only native preview.
    /// Mirrors `ContactsManager.mergeContacts` dedup rules so the preview
    /// matches reality byte-for-byte. Never saves to the store.
    func buildPreviewContact(for group: DuplicateGroup) -> CNContact? {
        let selected = selectedContactsInGroup(group)
        guard let first = selected.first?.cnContact,
              let mutable = first.mutableCopy() as? CNMutableContact
        else { return nil }

        for ac in selected.dropFirst() {
            guard let other = ac.cnContact else { continue }

            // Phones — dedup by normalized digits
            let existingPhones = Set(mutable.phoneNumbers.map { normalizePhone($0.value.stringValue) })
            for phone in other.phoneNumbers {
                let n = normalizePhone(phone.value.stringValue)
                if !n.isEmpty && !existingPhones.contains(n) {
                    mutable.phoneNumbers.append(phone)
                }
            }

            // Emails — dedup by lowercased
            let existingEmails = Set(mutable.emailAddresses.map { ($0.value as String).lowercased() })
            for email in other.emailAddresses where !existingEmails.contains((email.value as String).lowercased()) {
                mutable.emailAddresses.append(email)
            }

            // Scalar fields — fill where empty
            if mutable.givenName.isEmpty && !other.givenName.isEmpty { mutable.givenName = other.givenName }
            if mutable.familyName.isEmpty && !other.familyName.isEmpty { mutable.familyName = other.familyName }
            if mutable.organizationName.isEmpty && !other.organizationName.isEmpty {
                mutable.organizationName = other.organizationName
            }
            if mutable.jobTitle.isEmpty && !other.jobTitle.isEmpty { mutable.jobTitle = other.jobTitle }
            if mutable.imageData == nil && other.imageData != nil { mutable.imageData = other.imageData }
        }

        return mutable.copy() as? CNContact
    }

}
