import SwiftUI

// MARK: - Chevron Glyph
//
// The single source of truth for disclosure-style chevrons across the
// app (card right-edge "drill into me" indicators, row trailing
// hints, etc.). One size, one weight, one tint — so the dashboard,
// progress tab, leaderboard preview, more tab, and any future card
// surface read as a single visual family instead of a buffet of
// 11/12/13/14pt heavy/bold/semibold variants.
//
// Default spec: 13pt, semibold, mutedForeground — neutral grey that
// recedes against any card surface and matches the existing list
// affordances in Settings / Apple's HIG.
struct ChevronGlyph: View {
    enum Direction: String {
        case right, left, up, down
        var systemName: String {
            switch self {
            case .right: return "chevron.right"
            case .left:  return "chevron.left"
            case .up:    return "chevron.up"
            case .down:  return "chevron.down"
            }
        }
    }

    enum Size {
        /// 11pt — tight inline hints (row trailing affordance).
        case small
        /// 13pt — standard disclosure on cards / list rows.
        case standard
        /// 15pt — heavier emphasis (filter pills, prominent CTAs).
        case large

        var fontSize: CGFloat {
            switch self {
            case .small:    return 11
            case .standard: return 13
            case .large:    return 15
            }
        }
    }

    var direction: Direction = .right
    var size: Size = .standard
    var tint: Color = .mutedForeground

    var body: some View {
        Image(systemName: direction.systemName)
            .font(.system(size: size.fontSize, weight: .semibold))
            .foregroundColor(tint)
    }
}
