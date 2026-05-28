import SwiftUI

// @MainActor — extension methods access `vault` (a @MainActor-isolated
// SecretVaultManager). Swift 6 doesn't auto-inherit @MainActor on a
// View's extensions; mirrors SecretLibraryView+Helpers.swift.
@MainActor
extension SecretLibraryView {

    // MARK: - Media Grid
    var mediaGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ], spacing: 2) {
                ForEach(vault.items) { item in
                    VaultMediaCell(
                        item: item,
                        isSelected: selectedItems.contains(item.id),
                        isSelecting: isSelecting,
                        onTap: {
                            // In selection mode → toggle. Otherwise open
                            // the fullscreen preview so users can actually
                            // SEE what they've vaulted (photo or video).
                            if isSelecting {
                                toggleSelection(item)
                            } else {
                                previewItem = item
                            }
                        },
                        onSelect: {
                            toggleSelection(item)
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Empty State
    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            // Stacked photo icons
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "E0E0E4"))
                    .frame(width: 120, height: 100)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -10, y: 6)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "D4D4D8"))
                    .frame(width: 120, height: 100)
                    .rotationEffect(.degrees(4))
                    .offset(x: 8, y: -4)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "C8C8CC"))
                    .frame(width: 120, height: 100)

                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(Color(hex: "A1A1AA").opacity(0.6))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.5), value: appeared)

            VStack(spacing: 8) {
                Text("No Secret Files")
                    .font(.custom("Poppins-Bold", size: 20))
                    .foregroundColor(Color(hex: "1C1917"))

                Text("Tap the button below to add\nphotos and videos to your vault.")
                    .font(.custom("Poppins-Regular", size: 14))
                    .foregroundColor(Color(hex: "A1A1AA"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: appeared)

            Spacer()
        }
    }

    // MARK: - Bottom Bar
    var bottomBar: some View {
        Group {
            if !selectedItems.isEmpty {
                HStack(spacing: 0) {
                    // Share
                    Button {
                        HapticManager.shared.impact(.light)
                        prepareShareItems()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                            Text(BCLoc.share.tr)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(maxWidth: .infinity)
                    }

                    // Delete
                    Button {
                        HapticManager.shared.impact(.medium)
                        showDeleteConfirm = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 20, weight: .medium))
                            Text(BCLoc.delete.tr)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 8, y: -2)
                )
                .padding(.bottom, 0)
            } else {
                Button {
                    HapticManager.shared.impact(.light)
                    showAddSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("Add New")
                            .font(.custom("Poppins-Bold", size: 16))
                    }
                    .foregroundColor(.white)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "1C1917"))
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 16, y: 6)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
    }

}
