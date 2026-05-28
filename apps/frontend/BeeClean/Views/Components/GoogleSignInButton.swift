import SwiftUI
import GoogleSignInSwift

struct GoogleSignInButton: View {
    let action: () -> Void
    
    private let googleBlue = Color(hex: "4285F4")
    private let googleBlueDark = Color(hex: "3367D6")
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Google Logo
                GoogleLogoView()
                    .frame(width: 20, height: 20)
                
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [googleBlue, googleBlueDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: googleBlue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// Custom Google Logo
struct GoogleLogoView: View {
    var body: some View {
        Image(systemName: "g.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(.white)
    }
}

// Native Google Sign-In Button wrapper
struct NativeGoogleSignInButton: View {
    @StateObject private var authService = AuthService.shared
    
    var body: some View {
        GoogleSignInButton {
            Task {
                await authService.signInWithGoogle()
            }
        }
        .overlay {
            if authService.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .disabled(authService.isLoading)
    }
}

#Preview {
    VStack(spacing: 20) {
        GoogleSignInButton {
            print("Sign in tapped")
        }
        
        NativeGoogleSignInButton()
    }
    .padding()
    .background(Color.black)
}
