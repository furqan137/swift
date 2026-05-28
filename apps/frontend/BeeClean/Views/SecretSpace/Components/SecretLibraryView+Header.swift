import SwiftUI

@MainActor
extension SecretLibraryView {

    // MARK: - Header
    var headerBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: back chevron left, Select All right (only when selecting)
            HStack(alignment: .center) {
                Button(action: {
                    HapticManager.shared.arrowNudge(.backward)
                    onLock()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(hex: "EEEDF3")))
                        .contentShape(Circle())
                }

                Spacer()

                // Select All — only visible when there are items & selecting
                if isSelecting && !vault.items.isEmpty {
                    Button {
                        HapticManager.shared.impact(.light)
                        if selectedItems.count == vault.items.count {
                            selectedItems.removeAll()
                        } else {
                            selectedItems = Set(vault.items.map(\.id))
                        }
                    } label: {
                        BitePalSelectPillLabel(
                            text: selectedItems.count == vault.items.count ? "Deselect All" : "Select All",
                            isActive: selectedItems.count == vault.items.count,
                            restingIcon: "checkmark.circle",
                            activeIcon: "checkmark.circle.fill"
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Title row: "Secret Library" left, red lock button RIGHT
            HStack(alignment: .center) {
                Text("Secret Library")
                    .font(.custom("Poppins-Bold", size: 32))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                // Lock toggle button
                Button {
                    HapticManager.shared.impact(.medium)
                    lockPIN = ""
                    lockPINCandidate = ""
                    lockPINError = false
                    lockShake = 0
                    lockStep = (hasCreatedPIN && !savedPIN.isEmpty) ? 10 : 0
                    showLockFlow = true
                } label: {
                    if hasCreatedPIN && !savedPIN.isEmpty {
                        // White locked icon
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917"))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                            )
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                            )
                    } else {
                        // Red unlocked icon
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(hex: "DC2626"))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color(hex: "DC2626").opacity(0.08))
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Subtitle — always visible
            Text("\(vault.photoCount) Photos, \(vault.videoCount) Videos")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(Color(hex: "A1A1AA"))
                .padding(.horizontal, 20)
                .padding(.top, 2)
        }
        .padding(.bottom, 10)
    }

}
