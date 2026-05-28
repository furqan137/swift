import SwiftUI

// MARK: - LanguageSettingsView
//
// Modal language picker that mirrors the inspo screenshot. Presented
// as a sheet from Settings (not pushed onto a navigation stack), so
// the chrome is the bare minimum: a single header row with the
// "Select Language" title on the left and an X-close pill on the
// right, then a scrolling list of flat rows directly on the white
// sheet background.
//
// Visual recipe (inspo-matched):
//   • Header — Poppins-Bold 22 "Select Language" + circular X pill
//   • Drag indicator (provided by the .sheet modifier)
//   • Rows — 28pt flag glyph, native autonym only (no English
//     subtitle), full-width hairline divider between rows
//   • Selected row — 24pt black circle with white check (high
//     contrast, replaces the previous honey check)
//
// Behaviour:
//   • Tapping a row writes through `LocalizationService.shared
//     .setLocale(_:)`, which flips the published `current` value
//     and persists to AppStorage; the sheet then dismisses so the
//     user sees the freshly-translated Settings page immediately.
//   • RTL scripts (Arabic, Hebrew, Urdu, Persian) keep their
//     native column trailing-aligned via an inline environment
//     override.

struct LanguageSettingsView: View {
    @ObservedObject private var loc = LocalizationService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(SupportedLocale.allCases.enumerated()),
                            id: \.element) { idx, lang in
                        row(for: lang)
                        if idx < SupportedLocale.allCases.count - 1 {
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 0.5)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.card.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(BCLoc.selectLanguage.tr)
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(.foreground)
            Spacer(minLength: 8)
            closeButton
        }
    }

    private var closeButton: some View {
        Button {
            HapticManager.shared.arrowNudge(.backward)
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.foreground)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(Color.surfaceLight)
                )
                .overlay(
                    Circle().stroke(Color.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    // MARK: - Row

    private func row(for lang: SupportedLocale) -> some View {
        let isSelected = (loc.current == lang)
        return Button {
            HapticManager.shared.filterChange()
            loc.setLocale(lang)
            // Selection-only: live-applies the locale (every BCLoc.tr
            // re-renders) but keeps the sheet open so an accidental
            // tap is recoverable. X close button (top-right) is the
            // explicit exit.
        } label: {
            HStack(spacing: 18) {
                Text(lang.flag)
                    .font(.system(size: 28))
                    .frame(width: 34, height: 34)

                Text(lang.nativeName)
                    .font(.custom("Poppins-Medium", size: 17))
                    .foregroundColor(.foreground)
                    .lineLimit(1)
                    .environment(\.layoutDirection,
                                 lang.isRTL ? .rightToLeft : .leftToRight)

                Spacer(minLength: 8)

                if isSelected {
                    selectedMark
                }
            }
            .padding(.horizontal, 24)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private var selectedMark: some View {
        ZStack {
            Circle()
                .fill(Color.foreground)
                .frame(width: 24, height: 24)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
