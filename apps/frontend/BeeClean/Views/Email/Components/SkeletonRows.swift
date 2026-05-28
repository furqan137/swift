import SwiftUI

// MARK: - Skeleton Email Row (Loading Placeholder)
struct SkeletonEmailRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: "E5E7EB"))
                .frame(width: 22, height: 22)
            
            Circle()
                .fill(Color(hex: "E5E7EB"))
                .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "E5E7EB"))
                        .frame(width: 120, height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "E5E7EB"))
                        .frame(width: 40, height: 10)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 180, height: 11)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(height: 10)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(hex: "F3F4F6"))
        .cornerRadius(10)
        .opacity(isAnimating ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Skeleton Sender Row (Loading Placeholder)
struct SkeletonSenderRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "E5E7EB"))
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 140, height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 200, height: 12)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "E5E7EB"))
                .frame(width: 80, height: 36)
        }
        .padding(16)
        .background(Color(hex: "F3F4F6"))
        .cornerRadius(16)
        .opacity(isAnimating ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Skeleton Category Row (Loading Placeholder)
struct SkeletonCategoryRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 14) {
            // Icon placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "F4F4F5"))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F4F4F5"))
                    .frame(width: 100, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F4F4F5"))
                    .frame(width: 150, height: 12)
            }

            Spacer()

            Capsule()
                .fill(Color(hex: "F4F4F5"))
                .frame(width: 48, height: 24)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "F4F4F5"))
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
        )
        .opacity(isAnimating ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}
