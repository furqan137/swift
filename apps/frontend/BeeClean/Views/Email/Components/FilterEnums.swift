import Foundation

// MARK: - Filter Enums (shared across FiltersView)

enum FilterTimeOption: String, CaseIterable, Identifiable {
    case all = "All emails"
    case threeDays = "3 days and older"
    case week = "1 week and older"
    case twoWeeks = "2 weeks and older"
    case month = "1 month and older"
    case threeMonths = "3 months and older"
    case sixMonths = "6 months and older"
    case year = "1 year and older"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .threeDays: return "clock.fill"
        case .week, .twoWeeks: return "calendar"
        case .month, .threeMonths, .sixMonths: return "calendar.badge.clock"
        case .year: return "calendar.circle.fill"
        }
    }
    var days: Int? {
        switch self {
        case .all: return nil
        case .threeDays: return 3
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        }
    }
}

enum FilterReadOption: String, CaseIterable, Identifiable {
    case all = "All emails"
    case readOnly = "Read only"
    case unreadOnly = "Unread only"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: return "envelope.fill"
        case .readOnly: return "envelope.open.fill"
        case .unreadOnly: return "envelope.badge.fill"
        }
    }
}

enum FilterAttachmentOption: String, CaseIterable, Identifiable {
    case any = "Any"
    case withAttachments = "Has attachments"
    case withoutAttachments = "No attachments"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .any: return "paperclip"
        case .withAttachments: return "paperclip.circle.fill"
        case .withoutAttachments: return "xmark.circle.fill"
        }
    }
}
