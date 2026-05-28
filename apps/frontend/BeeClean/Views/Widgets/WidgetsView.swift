import SwiftUI

// MARK: - Widgets View
// Mirrors src/pages/WidgetsPage.tsx
struct WidgetsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWidgetType: WidgetType = .both
    @State private var selectedColor: WidgetColor = .cyan
    
    enum WidgetType: String, CaseIterable {
        case battery = "Battery"
        case storage = "Storage"
        case both = "Both"
        
        var iconName: String {
            switch self {
            case .battery: return "battery.75"
            case .storage: return "internaldrive.fill"
            case .both: return "square.grid.2x2.fill"
            }
        }
    }
    
    enum WidgetColor: String, CaseIterable {
        case cyan = "Cyan"
        case purple = "Purple"
        case green = "Green"
        case orange = "Orange"
        case pink = "Pink"
        
        var color: Color {
            switch self {
            case .cyan: return .categoryCyan
            case .purple: return .categoryPurple
            case .green: return .categoryGreen
            case .orange: return .categoryOrange
            case .pink: return .categoryPink
            }
        }
    }
    
    var body: some View {
        AppLayout(showBackButton: true, title: "Widgets") {
            ScrollView {
                VStack(spacing: 24) {
                    // Widget preview
                    WidgetPreview(
                        widgetType: selectedWidgetType,
                        accentColor: selectedColor.color
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Widget type selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Widget Type")
                            .font(.titleSmall)
                            .foregroundColor(.foreground)
                            .padding(.horizontal, 20)
                        
                        HStack(spacing: 12) {
                            ForEach(WidgetType.allCases, id: \.self) { type in
                                WidgetTypeButton(
                                    type: type,
                                    isSelected: selectedWidgetType == type
                                ) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedWidgetType = type
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Color selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color Theme")
                            .font(.titleSmall)
                            .foregroundColor(.foreground)
                            .padding(.horizontal, 20)
                        
                        HStack(spacing: 16) {
                            ForEach(WidgetColor.allCases, id: \.self) { color in
                                ColorButton(
                                    color: color.color,
                                    isSelected: selectedColor == color
                                ) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedColor = color
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to Add Widget")
                            .font(.titleSmall)
                            .foregroundColor(.foreground)
                        
                        VStack(spacing: 12) {
                            InstructionRow(number: 1, text: "Long press on your home screen")
                            InstructionRow(number: 2, text: "Tap the + button in the corner")
                            InstructionRow(number: 3, text: "Search for \"BeeClean\"")
                            InstructionRow(number: 4, text: "Select your preferred widget size")
                        }
                    }
                    .padding(20)
                    .cardSurface(.standard)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Widget Preview
struct WidgetPreview: View {
    let widgetType: WidgetsView.WidgetType
    let accentColor: Color
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Preview")
                .font(.labelSmall)
                .foregroundColor(.mutedForeground)
            
            // Widget card
            HStack(spacing: 20) {
                if widgetType == .battery || widgetType == .both {
                    // Battery widget
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(Color.surfaceLight, lineWidth: 8)
                                .frame(width: 60, height: 60)
                            
                            Circle()
                                .trim(from: 0, to: 0.78)
                                .stroke(accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 60, height: 60)
                                .rotationEffect(.degrees(-90))
                            
                            Text("78%")
                                .font(.labelSmall)
                                .fontWeight(.semibold)
                                .foregroundColor(.foreground)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "battery.75")
                                .font(.system(size: 12))
                                .foregroundColor(accentColor)
                            Text("Battery")
                                .font(.caption)
                                .foregroundColor(.mutedForeground)
                        }
                    }
                }
                
                if widgetType == .storage || widgetType == .both {
                    // Storage widget
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(Color.surfaceLight, lineWidth: 8)
                                .frame(width: 60, height: 60)
                            
                            Circle()
                                .trim(from: 0, to: 0.68)
                                .stroke(accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 60, height: 60)
                                .rotationEffect(.degrees(-90))
                            
                            Text("68%")
                                .font(.labelSmall)
                                .fontWeight(.semibold)
                                .foregroundColor(.foreground)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive.fill")
                                .font(.system(size: 12))
                                .foregroundColor(accentColor)
                            Text("Storage")
                                .font(.caption)
                                .foregroundColor(.mutedForeground)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(accentColor.opacity(0.3), lineWidth: 2)
            )
            .shadow(color: accentColor.opacity(0.2), radius: 20)
        }
    }
}

// MARK: - Widget Type Button
struct WidgetTypeButton: View {
    let type: WidgetsView.WidgetType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.filterChange()
            action()
        }) {
            VStack(spacing: 8) {
                Image(systemName: type.iconName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(isSelected ? .primaryColor : .mutedForeground)

                Text(type.rawValue)
                    .font(.labelSmall)
                    .foregroundColor(isSelected ? .foreground : .mutedForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.primaryColor.opacity(0.1) : Color.surfaceLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.primaryColor : Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Button
struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.filterChange()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 44, height: 44)

                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primaryColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                
                Text("\(number)")
                    .font(.labelSmall)
                    .fontWeight(.semibold)
                    .foregroundColor(.primaryColor)
            }
            
            Text(text)
                .font(.bodyMedium)
                .foregroundColor(.foreground)
            
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        WidgetsView()
    }
    .preferredColorScheme(.dark)
}
