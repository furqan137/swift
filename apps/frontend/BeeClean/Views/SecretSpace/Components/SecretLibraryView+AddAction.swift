import SwiftUI

@MainActor
extension SecretLibraryView {

    // MARK: - Import Toast
    var importToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: "22C55E"))
                .font(.system(size: 14))
            Text("\(importCount) file\(importCount == 1 ? "" : "s") imported")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "1C1917"))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.white)
                .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
        )
        .padding(.top, 8)
    }

    // MARK: - Add Action Sheet
    var addActionSheet: some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule()
                .fill(Color.black.opacity(0.14))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // Title block — eyebrow + headline
            VStack(spacing: 4) {
                Text("ADD TO VAULT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.4)
                    .foregroundColor(Color(hex: "78716C"))
                Text("Choose how to bring it in")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
            }
            .padding(.bottom, 18)

            // Grouped action rows — white card with gold hardware-badge icons
            VStack(spacing: 0) {
                addActionRow(
                    icon: "camera.aperture",
                    title: "Capture",
                    subtitle: "Shoot straight into the vault"
                ) {
                    withAnimation(.easeOut(duration: 0.25)) { showAddSheet = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCamera = true }
                }

                Rectangle()
                    .fill(Color(hex: "ECECEF"))
                    .frame(height: 0.5)
                    .padding(.leading, 78)

                addActionRow(
                    icon: "square.stack.3d.up.fill",
                    title: "Import",
                    subtitle: "Pull from your library"
                ) {
                    withAnimation(.easeOut(duration: 0.25)) { showAddSheet = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showMediaPicker = true }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 14)

            // Cancel — light chip on the gray sheet
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showAddSheet = false }
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 1)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Add Sheet Shell (extracted to keep type-checker happy)
    var addSheetShell: some View {
        return RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(hex: "F2F2F7"))
            .shadow(color: Color.black.opacity(0.18), radius: 28, y: -8)
    }

    // MARK: - Add Action Row
    func addActionRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        // Bitepal badge — tint per action, full-saturation glyph on a 10% wash
        let tint: Color = (title == "Capture")
            ? Color(hex: "6366F1")   // indigo — action / shutter
            : Color(hex: "64748B")   // slate — library / storage
        return Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.10))
                        .frame(width: 46, height: 46)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(Color(hex: "78716C"))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "C7C7CC"))
            }
            .padding(.horizontal, 16)
            .frame(height: 74)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}
