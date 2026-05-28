import SwiftUI

// MARK: - Media Category Model
// Mirrors src/data/mockData.ts
struct MediaCategory: Identifiable, Hashable {
    let id: String
    let label: String
    let iconName: String
    let count: Int
    let size: String
    let color: Color
    
    static func == (lhs: MediaCategory, rhs: MediaCategory) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Media Item Model
struct MediaItem: Identifiable, Hashable {
    let id: String
    let categoryId: String
    let name: String
    let size: String
    let date: Date
    let thumbnailColor: Color
}

