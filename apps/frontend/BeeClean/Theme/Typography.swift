import SwiftUI

// MARK: - Typography System
extension Font {
    // Display fonts
    static let displayLarge = Font.system(size: 36, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 24, weight: .semibold, design: .rounded)

    // Title fonts
    static let titleLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let titleMedium = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let titleSmall = Font.system(size: 16, weight: .medium, design: .rounded)

    // Body fonts
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .rounded)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .rounded)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .rounded)

    // Label fonts
    static let labelLarge = Font.system(size: 14, weight: .medium, design: .rounded)
    static let labelMedium = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let labelSmall = Font.system(size: 11, weight: .semibold, design: .rounded)

    // Bee speech — the bee's voice, pair with .italic()
    static let beeSpeech = Font.system(size: 16, weight: .medium, design: .rounded)

    // Caption
    static let caption = Font.system(size: 10, weight: .regular, design: .rounded)
}

// MARK: - Text Styles
struct GradientText: View {
    let text: String
    let font: Font
    let gradient: LinearGradient

    init(_ text: String, font: Font = .titleMedium, gradient: LinearGradient = .honeyGradient) {
        self.text = text
        self.font = font
        self.gradient = gradient
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(gradient)
    }
}

// MARK: - Text Modifiers
extension View {
    func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}

enum TextStyle {
    case displayLarge
    case displayMedium
    case displaySmall
    case titleLarge
    case titleMedium
    case titleSmall
    case bodyLarge
    case bodyMedium
    case bodySmall
    case labelLarge
    case labelMedium
    case labelSmall
    case caption
}

struct TextStyleModifier: ViewModifier {
    let style: TextStyle

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundColor(color)
    }

    private var font: Font {
        switch style {
        case .displayLarge: return .displayLarge
        case .displayMedium: return .displayMedium
        case .displaySmall: return .displaySmall
        case .titleLarge: return .titleLarge
        case .titleMedium: return .titleMedium
        case .titleSmall: return .titleSmall
        case .bodyLarge: return .bodyLarge
        case .bodyMedium: return .bodyMedium
        case .bodySmall: return .bodySmall
        case .labelLarge: return .labelLarge
        case .labelMedium: return .labelMedium
        case .labelSmall: return .labelSmall
        case .caption: return .caption
        }
    }

    private var color: Color {
        switch style {
        case .displayLarge, .displayMedium, .displaySmall,
             .titleLarge, .titleMedium, .titleSmall:
            return .foreground
        case .bodyLarge, .bodyMedium, .bodySmall:
            return .foreground.opacity(0.9)
        case .labelLarge, .labelMedium, .labelSmall, .caption:
            return .mutedForeground
        }
    }
}
