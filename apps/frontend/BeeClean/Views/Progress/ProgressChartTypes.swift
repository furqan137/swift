import SwiftUI

// MARK: - Range
//
// Time-window options for every Progress-tab chart. Defines the bucket
// count (per chart point), the bucket unit (hour/day/month), and the
// pill label. Owned at module scope rather than as a private nested
// type so the hero chart, the segmentation chart, and any future
// Progress surface can share one source of truth.

enum ProgressRange: CaseIterable {
    case oneDay, sevenDay, thirtyDay, oneYear

    var label: String {
        switch self {
        case .oneDay:    return "1D"
        case .sevenDay:  return "7D"
        case .thirtyDay: return "30D"
        case .oneYear:   return "1Y"
        }
    }

    /// Bucket count per range. 1D is hourly (24), 7D/30D are daily,
    /// 1Y rolls up to monthly (12) so longer windows stay readable.
    var pointCount: Int {
        switch self {
        case .oneDay:    return 24
        case .sevenDay:  return 7
        case .thirtyDay: return 30
        case .oneYear:   return 12
        }
    }

    /// Time unit each bucket represents — drives tooltip wording.
    var unit: BucketUnit {
        switch self {
        case .oneDay:               return .hour
        case .sevenDay, .thirtyDay: return .day
        case .oneYear:              return .month
        }
    }
}

enum BucketUnit {
    case hour, day, week, month

    var singular: String {
        switch self {
        case .hour:  return "hour"
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        }
    }
}

// MARK: - XP Range
//
// Time window for the XP card. Intentionally narrower than
// `ProgressRange` (no 1D / 1Y) — XP is a weekly motivation rhythm,
// daily resolution loses the streak feel, and a yearly rollup flattens
// every weekly nuance into noise. Week / Month is the right zoom for
// the gamification surface.

enum XpRange: CaseIterable {
    case week, month

    var label: String {
        switch self {
        case .week:  return "Week"
        case .month: return "Month"
        }
    }

    /// Phrase used in the XP card eyebrow ("earned this week").
    var scopeLabel: String {
        switch self {
        case .week:  return "this week"
        case .month: return "this month"
        }
    }

    /// Comparison-period phrase used by the delta chip ("vs last week").
    var priorLabel: String {
        switch self {
        case .week:  return "last week"
        case .month: return "last month"
        }
    }
}

// MARK: - Top-Level Category
//
// Groups granular `SavedFindSourceCategory` leaves + non-photo action
// verbs ("email_cleanup", "compression", "contact_cleanup") into the
// five user-facing surfaces from Quick Access: Photos, Videos, Email,
// Compression, Contacts. Drives the Segmentation card and any future
// per-category aggregation on the Progress tab.

enum TopLevelCategory: String, Hashable, CaseIterable {
    case photos
    case videos
    case emails
    case compression
    case contacts

    var displayName: String {
        switch self {
        case .photos:      return "Photos"
        case .videos:      return "Videos"
        case .emails:      return "Email"
        case .compression: return "Compression"
        case .contacts:    return "Contacts"
        }
    }

    /// Tight single-word label for compact 5-segment chip rows where
    /// `displayName` ("Compression") wouldn't fit. Same as displayName
    /// for everything except Compression → "Compress".
    var shortLabel: String {
        switch self {
        case .compression: return "Compress"
        default:           return displayName
        }
    }

    var iconName: String {
        switch self {
        case .photos:      return "photo.fill"
        case .videos:      return "video.fill"
        case .emails:      return "envelope.fill"
        case .compression: return "arrow.down.right.and.arrow.up.left"
        case .contacts:    return "person.2.fill"
        }
    }

    /// Distinct hue per top-level so the donut + per-row colored dot
    /// read as one identity. Picked to match the rest of the app's
    /// category palette — no two rows share a color so the legend
    /// doesn't need labels.
    var accentColor: Color {
        switch self {
        case .photos:      return Color(hex: "FF7A1A")
        case .videos:      return Color(hex: "7C5CFF")
        case .emails:      return Color(hex: "0EA5E9")
        case .compression: return Color(hex: "10B981")
        case .contacts:    return Color(hex: "EC4899")
        }
    }

    /// Leaf categories that drill down from this top-level group.
    /// Email + Contacts return [] because their activity entries
    /// don't carry a leaf — segmentation surfaces just show the
    /// aggregate for those scopes. Compression's leaves are its own
    /// photo/video lanes to avoid double-counting against Photos/Videos.
    var leafCategories: [SavedFindSourceCategory] {
        switch self {
        case .photos:
            return [.duplicates, .similarPhotos, .similarScreenshots,
                    .screenshots, .blurredPhotos, .otherPhotos]
        case .videos:
            return [.similarVideos, .screenRecordings,
                    .shortRecordings, .longVideos]
        case .compression:
            return [.photoCompression, .videoCompression]
        case .emails, .contacts:
            return []
        }
    }
}

// MARK: - ActivityEntry → TopLevelCategory mapping

extension ActivityEntry {
    /// Group this activity entry into one of the five user-facing
    /// top-level surfaces. Returns nil for entries we don't want on
    /// the segmentation chart (scans, plan_generated, untagged legacy
    /// deletions).
    var topLevelCategory: TopLevelCategory? {
        switch bareAction {
        case "email_cleanup":   return .emails
        case "contact_cleanup": return .contacts
        case "compression":     return .compression
        case "deletion":
            guard let leaf = category else { return nil }
            if TopLevelCategory.photos.leafCategories.contains(leaf) {
                return .photos
            }
            if TopLevelCategory.videos.leafCategories.contains(leaf) {
                return .videos
            }
            return nil
        default:
            return nil
        }
    }

    /// Email sub-category encoded into the action string as
    /// `"email_cleanup:promotions"` etc. Returns nil for unsegmented
    /// email cleanups (QuickClean bulk-trash that spans categories)
    /// and for non-email entries.
    var emailCategory: EmailCategory? {
        guard bareAction == "email_cleanup" else { return nil }
        let parts = action.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        return EmailCategory(rawValue: String(parts[1]))
    }
}

// MARK: - ChartPalette
//
// User-selectable chart palette. Nine glass-polish color families, each
// a paired tonal ramp (lighter → deeper of the same hue) so the
// gradient stroke reads as a single liquid material rather than two
// competing colors. Sourced from a `@AppStorage`-backed raw string on
// the Progress tab so the user's choice survives a relaunch.
//
// The five color slots per palette serve distinct visual jobs:
//   • lineStart / lineEnd   — gradient stroke painted along the line
//   • areaFillTop           — apex of the area-fill gradient that fades
//                             to transparent at the chart baseline
//   • shadowColor           — colored glow under the line + best marker
//   • bestMarkerColor       — deliberately CONTRASTING hue for the BEST
//                             pill so it pops off the line

enum ChartPalette: String, CaseIterable, Codable, Identifiable, Hashable {
    case honey
    case cobalt
    case aurora
    case coral
    case forest
    case sunset
    case ice
    case lilac
    case liquidGlass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        // Display names diverge from enum case names so the labels
        // match what the swatch actually shows: the historic
        // `honey` palette renders as a saturated orange-red, and
        // the historic `liquidGlass` palette renders as the
        // bright-amber CTA color (`#FFC648`) that reads as honey on
        // the swatch. Persisted rawValue + enum case stay stable so
        // no migration needed — only the user-facing strings move.
        case .honey:       return "Orange"
        case .cobalt:      return "Cobalt"
        case .aurora:      return "Aurora"
        case .coral:       return "Coral"
        case .forest:      return "Forest"
        case .sunset:      return "Sunset"
        case .ice:         return "Ice"
        case .lilac:       return "Lilac"
        case .liquidGlass: return "Honey"
        }
    }

    var lineStart: Color {
        switch self {
        case .honey:       return Color(hex: "FFB300")
        case .cobalt:      return Color(hex: "3B82F6")
        case .aurora:      return Color(hex: "A78BFA")
        case .coral:       return Color(hex: "FB7185")
        case .forest:      return Color(hex: "22C55E")
        case .sunset:      return Color(hex: "F97316")
        case .ice:         return Color(hex: "67E8F9")
        case .lilac:       return Color(hex: "F472B6")
        // `#FFC648` — exact match to TodaysCleanupCard's "Start Quick
        // Cleanup" CTA button. Locks every chart that defaults to
        // LiquidGlass onto the dashboard's primary amber identity.
        case .liquidGlass: return Color(hex: "FFC648")
        }
    }

    var lineEnd: Color {
        switch self {
        case .honey:       return Color(hex: "FF7A1A")
        case .cobalt:      return Color(hex: "1E40AF")
        case .aurora:      return Color(hex: "7C3AED")
        case .coral:       return Color(hex: "F43F5E")
        case .forest:      return Color(hex: "15803D")
        case .sunset:      return Color(hex: "DC2626")
        case .ice:         return Color(hex: "0EA5E9")
        case .lilac:       return Color(hex: "EC4899")
        // Slightly deeper amber than `lineStart` so the gradient
        // reads as a single material with subtle depth, not a flat
        // block. Pulled from the same amber family.
        case .liquidGlass: return Color(hex: "F5A623")
        }
    }

    var areaFillTop: Color {
        switch self {
        case .honey:       return Color(hex: "FFB300")
        case .cobalt:      return Color(hex: "60A5FA")
        case .aurora:      return Color(hex: "C4B5FD")
        case .coral:       return Color(hex: "FDA4AF")
        case .forest:      return Color(hex: "86EFAC")
        case .sunset:      return Color(hex: "FB923C")
        case .ice:         return Color(hex: "A5F3FC")
        case .lilac:       return Color(hex: "FBCFE8")
        case .liquidGlass: return Color(hex: "FFC648")
        }
    }

    var shadowColor: Color {
        switch self {
        case .honey:       return Color(hex: "FF7A1A")
        case .cobalt:      return Color(hex: "1E3A8A")
        case .aurora:      return Color(hex: "6D28D9")
        case .coral:       return Color(hex: "BE123C")
        case .forest:      return Color(hex: "166534")
        case .sunset:      return Color(hex: "991B1B")
        case .ice:         return Color(hex: "075985")
        case .lilac:       return Color(hex: "BE185D")
        case .liquidGlass: return Color(hex: "F5A623")
        }
    }

    var bestMarkerColor: Color {
        switch self {
        case .honey:       return Color(hex: "FF5722")
        case .cobalt:      return Color(hex: "0EA5E9")
        case .aurora:      return Color(hex: "EC4899")
        case .coral:       return Color(hex: "F97316")
        case .forest:      return Color(hex: "FACC15")
        case .sunset:      return Color(hex: "FACC15")
        case .ice:         return Color(hex: "A855F7")
        case .lilac:       return Color(hex: "22D3EE")
        case .liquidGlass: return Color(hex: "FF7A1A")
        }
    }

    /// Diagonal gradient used by the picker orb and the corner dot —
    /// same gradient pair as the chart stroke so the orb is a true
    /// preview, not a stylized chip.
    var orbGradient: LinearGradient {
        LinearGradient(
            colors: [lineStart, lineEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - MiniSparkline
//
// 44pt-wide trace used by Recent Wins rows and any future per-row
// chip that wants the same "trend at a glance" feel: smoothed line +
// soft area wash, no axes, no labels — pure shape behind a headline
// number. Animates a left-to-right trace on appear so the trend reads
// as alive, not painted-in.

struct MiniSparkline: View {
    let values: [Double]
    let tint: Color
    @State private var drawProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let cnt = values.count
            let maxV = max(values.max() ?? 1, 1)
            let minV = min(values.min() ?? 0, 0)
            let span = max(maxV - minV, 1)
            let w = geo.size.width
            let h = geo.size.height

            let pts: [CGPoint] = (0..<cnt).map { i in
                let frac = cnt > 1 ? CGFloat(i) / CGFloat(cnt - 1) : 0
                let x = frac * w
                let yFrac = CGFloat((values[i] - minV) / span)
                let y = h - 1 - yFrac * (h - 2)
                return CGPoint(x: x, y: y)
            }

            if pts.count >= 2 {
                ZStack(alignment: .bottom) {
                    smoothedPath(points: pts, closeBaseline: h)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.22), tint.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .opacity(drawProgress)

                    smoothedPath(points: pts, closeBaseline: nil)
                        .trim(from: 0, to: max(drawProgress, 0.001))
                        .stroke(
                            tint.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.6,
                                               lineCap: .round,
                                               lineJoin: .round)
                        )
                }
            }
        }
        .onAppear { retrace() }
        .onChange(of: values.count) { _, _ in retrace() }
        .onChange(of: tint) { _, _ in retrace() }
    }

    private func retrace() {
        drawProgress = 0
        withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
            drawProgress = 1.0
        }
    }

    /// Quadratic-curve smoothing matching `ActivityLineChart.smoothPath`
    /// so sparklines and the hero chart share the same visual hand.
    /// `closeBaseline` non-nil closes the path down to that y for the
    /// area-fill version.
    private func smoothedPath(points: [CGPoint], closeBaseline: CGFloat?) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let mid = CGPoint(x: (prev.x + curr.x) / 2,
                              y: (prev.y + curr.y) / 2)
            p.addQuadCurve(to: mid, control: prev)
            p.addQuadCurve(to: curr, control: curr)
        }
        if let baseline = closeBaseline, let last = points.last, let firstPt = points.first {
            p.addLine(to: CGPoint(x: last.x, y: baseline))
            p.addLine(to: CGPoint(x: firstPt.x, y: baseline))
            p.closeSubpath()
        }
        return p
    }
}
