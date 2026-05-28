import SwiftUI

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    let title: String
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color(hex: "3B82F6"))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                Spacer()
                
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.border)
                        .frame(height: 1)
                    
                    Button {
                        onSelect()
                        dismiss()
                    } label: {
                        Text(BCLoc.select.tr)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primaryForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: "3B82F6"))
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 34)
                }
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.foreground)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.mutedForeground)
                    }
                }
            }
        }
    }
}

#Preview {
    DatePickerSheet(selectedDate: .constant(Date()), title: "Start Date", onSelect: {})
}
