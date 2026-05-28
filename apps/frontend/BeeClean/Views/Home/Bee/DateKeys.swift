import Foundation

// MARK: - Date Key Helper
enum DateKeys {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var todayKey: String {
        formatter.string(from: Date())
    }
}
