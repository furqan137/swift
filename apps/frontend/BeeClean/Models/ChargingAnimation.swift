import SwiftUI

// MARK: - Charging Animation Model
// Mirrors src/data/chargingData.ts
struct ChargingAnimation: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String
    let gradientColors: [Color]
    let accentColor: Color
    let description: String
    
    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Tutorial Step Model
struct TutorialStep: Identifiable {
    let id: Int
    let title: String
    let description: String
    let iconName: String
}

