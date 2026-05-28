import SwiftUI

// MARK: - Category Detail View
// Mirrors src/pages/CategoryDetailPage.tsx
struct CategoryDetailView: View {
    let category: MediaCategory
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: Set<String> = []
    @State private var items: [MediaItem] = []
    
    var body: some View {
        AppLayout(showBackButton: true, title: category.label) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Header info
                        HStack {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(category.color.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: category.iconName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(category.color)
                                }
                                
                                Text("\(items.count) items")
                                    .font(.bodyMedium)
                                    .foregroundColor(.mutedForeground)
                                
                                Text("•")
                                    .foregroundColor(.mutedForeground.opacity(0.5))
                                
                                Text(category.size)
                                    .font(.bodyMedium)
                                    .foregroundColor(category.color)
                            }
                            
                            Spacer()
                            
                            Button {
                                if selectedItems.count == items.count {
                                    selectedItems.removeAll()
                                } else {
                                    selectedItems = Set(items.map { $0.id })
                                }
                            } label: {
                                Text(selectedItems.count == items.count ? "Deselect All" : "Select All")
                                    .font(.labelSmall)
                                    .foregroundColor(.primaryColor)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        // Items grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(items) { item in
                                MediaItemCell(
                                    item: item,
                                    category: category,
                                    isSelected: selectedItems.contains(item.id)
                                ) {
                                    if selectedItems.contains(item.id) {
                                        selectedItems.remove(item.id)
                                    } else {
                                        selectedItems.insert(item.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, selectedItems.isEmpty ? 100 : 180)
                    }
                }
                
                // Delete bar
                if !selectedItems.isEmpty {
                    ActionBar(
                        title: "Delete \(selectedItems.count) items",
                        buttonTitle: "Delete",
                        buttonIcon: "trash.fill",
                        isDestructive: true
                    ) {
                        // Remove selected items
                        items.removeAll { selectedItems.contains($0.id) }
                        selectedItems.removeAll()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedItems.isEmpty)
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Media Item Cell
struct MediaItemCell: View {
    let item: MediaItem
    let category: MediaCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.thumbnailColor)
                    .aspectRatio(1, contentMode: .fill)
                    .overlay(
                        Image(systemName: category.iconName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(category.color.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? category.color : Color.clear, lineWidth: 3)
                    )
                
                // Selection indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? category.color : Color.black.opacity(0.4))
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                            .frame(width: 20, height: 20)
                    }
                }
                .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(
            category: MediaCategory(
                id: "preview",
                label: "Screenshots",
                iconName: "camera.viewfinder",
                count: 50,
                size: "1.2 GB",
                color: .categoryRed
            )
        )
    }
    .preferredColorScheme(.dark)
}
