import SwiftUI

// MARK: - Reusable Phone Input Sheet
// Used by both SettingsView and ContactsView to edit the user's phone number.
struct PhoneInputSheet: View {
    @Binding var phoneNumber: String
    @Binding var isPresented: Bool
    @State private var tempPhone: String
    
    init(phoneNumber: Binding<String>, isPresented: Binding<Bool>) {
        _phoneNumber = phoneNumber
        _isPresented = isPresented
        _tempPhone = State(initialValue: phoneNumber.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "22C55E"), Color(hex: "16A34A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Your Phone Number")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Enter your phone number so we can identify\nyour contact card in the address book.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    TextField("e.g. +1 (555) 123-4567", text: $tempPhone)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .keyboardType(.phonePad)
                        .padding(16)
                        .background(Color.surfaceMedium)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primaryColor.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    
                    Button {
                        phoneNumber = tempPhone
                        isPresented = false
                        HapticManager.shared.impact(.medium)
                    } label: {
                        Text("Save")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "22C55E"), Color(hex: "16A34A")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
