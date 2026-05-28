import Foundation
import PhoneNumberKit

// MARK: - Phone Lookup Result Model
struct PhoneLookupResult {
    let valid: Bool
    let numberType: String        // "Mobile", "Landline", "VoIP", "Toll-Free", etc.
    let countryCode: String       // "US", "GB", etc.
    let regionCode: String        // ISO region
    let internationalFormat: String  // "+1 415-858-6273"
    let nationalFormat: String       // "(415) 858-6273"
    let e164Format: String           // "+14158586273"
    
    /// SF Symbol for the number type
    var typeIcon: String {
        switch numberType {
        case "Mobile": return "iphone"
        case "Landline", "Fixed Line": return "phone.fill"
        case "VoIP": return "wifi"
        case "Toll-Free", "Toll Free": return "phone.arrow.right"
        case "Pager": return "bell.fill"
        default: return "phone"
        }
    }
    
    /// Color hex for the number type badge
    var typeColorHex: String {
        switch numberType {
        case "Mobile": return "22C55E"
        case "Landline", "Fixed Line": return "3B82F6"
        case "VoIP": return "8B5CF6"
        case "Toll-Free", "Toll Free": return "F97316"
        default: return "6B7280"
        }
    }
    
    /// Country flag emoji from country code
    var countryFlag: String {
        let base: UInt32 = 127397 // Regional Indicator Symbol base
        return regionCode.uppercased().unicodeScalars.reduce("") { result, scalar in
            guard let flagScalar = Unicode.Scalar(base + scalar.value) else { return result }
            return result + String(flagScalar)
        }
    }
    
    /// Country name from region code
    var countryName: String {
        Locale.current.localizedString(forRegionCode: regionCode) ?? regionCode
    }
}

// MARK: - Phone Lookup Service (100% On-Device)
@MainActor
class PhoneLookupService: ObservableObject {
    static let shared = PhoneLookupService()
    
    @Published var lookupResult: PhoneLookupResult?
    @Published var isLoading = false
    @Published var error: String?
    
    private let phoneNumberUtility = PhoneNumberUtility()
    
    private init() {}
    
    // MARK: - Parse & Validate Phone Number
    func fetchPhoneInfo(phone: String) async {
        guard !phone.isEmpty else { return }
        
        isLoading = true
        error = nil
        
        // PhoneNumberKit parsing is synchronous but fast — run on background thread
        // to keep UI responsive
        let result: PhoneLookupResult? = await Task.detached { [phoneNumberUtility] in
            do {
                let parsed = try phoneNumberUtility.parse(phone)
                
                let typeString: String = {
                    switch parsed.type {
                    case .mobile: return "Mobile"
                    case .fixedLine: return "Landline"
                    case .fixedOrMobile: return "Mobile/Landline"
                    case .voip: return "VoIP"
                    case .tollFree: return "Toll-Free"
                    case .pager: return "Pager"
                    case .personalNumber: return "Personal"
                    case .premiumRate: return "Premium"
                    case .sharedCost: return "Shared Cost"
                    case .uan: return "UAN"
                    default: return "Unknown"
                    }
                }()
                
                let regionCode = phoneNumberUtility.mainCountry(forCode: parsed.countryCode) ?? "US"
                
                return PhoneLookupResult(
                    valid: true,
                    numberType: typeString,
                    countryCode: "+\(parsed.countryCode)",
                    regionCode: regionCode,
                    internationalFormat: phoneNumberUtility.format(parsed, toType: .international),
                    nationalFormat: phoneNumberUtility.format(parsed, toType: .national),
                    e164Format: phoneNumberUtility.format(parsed, toType: .e164)
                )
            } catch {
                return nil
            }
        }.value
        
        if let result = result {
            lookupResult = result
        } else {
            // Number failed parsing — it's invalid
            lookupResult = PhoneLookupResult(
                valid: false,
                numberType: "Invalid",
                countryCode: "",
                regionCode: "",
                internationalFormat: phone,
                nationalFormat: phone,
                e164Format: phone
            )
            error = "Invalid phone number"
        }
        
        isLoading = false
    }
    
    // MARK: - Clear
    func clear() {
        lookupResult = nil
        error = nil
    }
}
