import SwiftUI

extension EmailCategoryDetailView {
    // MARK: - Loading Skeleton
    var loadingSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonEmailRow()
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Error
    func errorState(_ error: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: needsSignIn ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(needsSignIn ? Color(hex: "1C1917") : .orange)
            Text(needsSignIn ? "Sign in required" : "Failed to load emails")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "1C1917"))
            Text(error.contains("timed out") || error.contains("timeout") ? "The request timed out. Check your connection and try again." : error)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "A1A1AA"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if needsSignIn {
                Button {
                    Task {
                        isSigningIn = true
                        await AuthService.shared.signInWithGoogle()
                        isSigningIn = false
                        if AuthService.shared.isAuthenticated {
                            await loadMessages()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(isSigningIn ? "Signing in..." : "Sign in with Google")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(hex: "1C1917"))
                    .cornerRadius(12)
                }
                .disabled(isSigningIn)
            } else {
                Button {
                    Task { await loadMessages() }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(hex: "1C1917"))
                        .cornerRadius(10)
                }
            }
            Spacer()
        }
    }

    // MARK: - Empty
    var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.3))
            Text(hasActiveFilters ? "No emails match your filters" : "No emails found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "1C1917"))
            Text(hasActiveFilters ? "Try adjusting or clearing your filters" : "This category is empty")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "A1A1AA"))

            if hasActiveFilters {
                Button {
                    filters = EmailFilters()
                    Task { await loadMessages() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                        Text("Clear Filters")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.top, 8)
            }
            Spacer()
        }
    }

}
