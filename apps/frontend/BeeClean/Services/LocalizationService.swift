import SwiftUI
import Combine

// MARK: - LocalizationService
//
// In-app, dynamic localization that flips the UI live when the user
// picks a new language from Settings. Deliberately bypasses Apple's
// `.strings`/`.xcstrings` pipeline so the project file stays untouched
// — translations are a Swift literal table, the active locale lives
// in `@AppStorage("preferences.appLocale")`, and any view that reads
// `BCLoc.something.tr` re-renders the moment the key changes.
//
// Architecture:
//   • `SupportedLocale` — closed enum of every language we ship.
//     Each case carries its BCP-47 code, native autonym, English
//     display name, and a flag emoji used by the picker.
//   • `BCLoc` — the string-key catalog (one case per user-facing
//     string on the redesigned Settings page). Adding a new string
//     anywhere in the app means adding a case here + an English
//     entry in `translations` — every other locale falls back to
//     English until translated.
//   • `LocalizationService.shared` — `ObservableObject` so any view
//     can observe and re-render on language change.
//
// The translation table covers ~30 of the most-spoken languages on
// the App Store so international users find their tongue on first
// open. Translations are limited to the visible Settings strings
// for v1; the same machinery scales to the rest of the app by
// extending the `BCLoc` enum and the per-locale dictionaries below.

enum SupportedLocale: String, CaseIterable, Identifiable, Hashable {
    case english     = "en"
    case spanish     = "es"
    case french      = "fr"
    case german      = "de"
    case italian     = "it"
    case portugueseBR = "pt-BR"
    case portuguesePT = "pt-PT"
    case russian     = "ru"
    case chineseSimplified  = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese    = "ja"
    case korean      = "ko"
    case arabic      = "ar"
    case hindi       = "hi"
    case bengali     = "bn"
    case urdu        = "ur"
    case dutch       = "nl"
    case polish      = "pl"
    case turkish     = "tr"
    case swedish     = "sv"
    case norwegian   = "nb"
    case danish      = "da"
    case finnish     = "fi"
    case greek       = "el"
    case czech       = "cs"
    case ukrainian   = "uk"
    case indonesian  = "id"
    case malay       = "ms"
    case vietnamese  = "vi"
    case thai        = "th"
    case hebrew      = "he"
    case romanian    = "ro"
    case hungarian   = "hu"
    case filipino    = "fil"
    case azerbaijani = "az"
    case persian     = "fa"
    case catalan     = "ca"
    case slovak      = "sk"
    case croatian    = "hr"
    case bulgarian   = "bg"
    case slovenian   = "sl"
    case lithuanian  = "lt"
    case latvian     = "lv"
    case estonian    = "et"
    case swahili     = "sw"
    case afrikaans   = "af"
    case tamil       = "ta"
    case marathi     = "mr"

    var id: String { rawValue }

    /// Native autonym — what speakers of the language actually call
    /// it. Shown as the primary label in the picker so a user
    /// scrolling the list recognises their own tongue at a glance,
    /// regardless of the currently-active UI language.
    var nativeName: String {
        switch self {
        case .english:             return "English"
        case .spanish:             return "Español"
        case .french:              return "Français"
        case .german:              return "Deutsch"
        case .italian:             return "Italiano"
        case .portugueseBR:        return "Português (Brasil)"
        case .portuguesePT:        return "Português (Portugal)"
        case .russian:             return "Русский"
        case .chineseSimplified:   return "简体中文"
        case .chineseTraditional:  return "繁體中文"
        case .japanese:            return "日本語"
        case .korean:              return "한국어"
        case .arabic:              return "العربية"
        case .hindi:               return "हिन्दी"
        case .bengali:             return "বাংলা"
        case .urdu:                return "اردو"
        case .dutch:               return "Nederlands"
        case .polish:              return "Polski"
        case .turkish:             return "Türkçe"
        case .swedish:             return "Svenska"
        case .norwegian:           return "Norsk"
        case .danish:              return "Dansk"
        case .finnish:             return "Suomi"
        case .greek:               return "Ελληνικά"
        case .czech:               return "Čeština"
        case .ukrainian:           return "Українська"
        case .indonesian:          return "Bahasa Indonesia"
        case .malay:               return "Bahasa Melayu"
        case .vietnamese:          return "Tiếng Việt"
        case .thai:                return "ภาษาไทย"
        case .hebrew:              return "עברית"
        case .romanian:            return "Română"
        case .hungarian:           return "Magyar"
        case .filipino:            return "Filipino"
        case .azerbaijani:         return "Azərbaycanca"
        case .persian:             return "فارسی"
        case .catalan:             return "Català"
        case .slovak:              return "Slovenčina"
        case .croatian:            return "Hrvatski"
        case .bulgarian:           return "Български"
        case .slovenian:           return "Slovenščina"
        case .lithuanian:          return "Lietuvių"
        case .latvian:             return "Latviešu"
        case .estonian:            return "Eesti"
        case .swahili:             return "Kiswahili"
        case .afrikaans:           return "Afrikaans"
        case .tamil:               return "தமிழ்"
        case .marathi:             return "मराठी"
        }
    }

    /// English exonym — secondary label, lets the user identify a
    /// language they don't read but recognise the English name of.
    var englishName: String {
        switch self {
        case .english:             return "English"
        case .spanish:             return "Spanish"
        case .french:              return "French"
        case .german:              return "German"
        case .italian:             return "Italian"
        case .portugueseBR:        return "Portuguese (Brazil)"
        case .portuguesePT:        return "Portuguese (Portugal)"
        case .russian:             return "Russian"
        case .chineseSimplified:   return "Chinese (Simplified)"
        case .chineseTraditional:  return "Chinese (Traditional)"
        case .japanese:            return "Japanese"
        case .korean:              return "Korean"
        case .arabic:              return "Arabic"
        case .hindi:               return "Hindi"
        case .bengali:             return "Bengali"
        case .urdu:                return "Urdu"
        case .dutch:               return "Dutch"
        case .polish:              return "Polish"
        case .turkish:             return "Turkish"
        case .swedish:             return "Swedish"
        case .norwegian:           return "Norwegian"
        case .danish:              return "Danish"
        case .finnish:             return "Finnish"
        case .greek:               return "Greek"
        case .czech:               return "Czech"
        case .ukrainian:           return "Ukrainian"
        case .indonesian:          return "Indonesian"
        case .malay:               return "Malay"
        case .vietnamese:          return "Vietnamese"
        case .thai:                return "Thai"
        case .hebrew:              return "Hebrew"
        case .romanian:            return "Romanian"
        case .hungarian:           return "Hungarian"
        case .filipino:            return "Filipino"
        case .azerbaijani:         return "Azerbaijani"
        case .persian:             return "Persian"
        case .catalan:             return "Catalan"
        case .slovak:              return "Slovak"
        case .croatian:            return "Croatian"
        case .bulgarian:           return "Bulgarian"
        case .slovenian:           return "Slovenian"
        case .lithuanian:          return "Lithuanian"
        case .latvian:             return "Latvian"
        case .estonian:            return "Estonian"
        case .swahili:             return "Swahili"
        case .afrikaans:           return "Afrikaans"
        case .tamil:               return "Tamil"
        case .marathi:             return "Marathi"
        }
    }

    /// Regional flag emoji. Picked the most-recognisable single flag
    /// per language (e.g. 🇧🇷 for pt-BR, 🇵🇹 for pt-PT). Multi-country
    /// languages (English, Spanish, Arabic, etc.) get the flag of the
    /// largest speaker base.
    var flag: String {
        switch self {
        case .english:             return "🇺🇸"
        case .spanish:             return "🇪🇸"
        case .french:              return "🇫🇷"
        case .german:              return "🇩🇪"
        case .italian:             return "🇮🇹"
        case .portugueseBR:        return "🇧🇷"
        case .portuguesePT:        return "🇵🇹"
        case .russian:             return "🇷🇺"
        case .chineseSimplified:   return "🇨🇳"
        case .chineseTraditional:  return "🇹🇼"
        case .japanese:            return "🇯🇵"
        case .korean:              return "🇰🇷"
        case .arabic:              return "🇸🇦"
        case .hindi:               return "🇮🇳"
        case .bengali:             return "🇧🇩"
        case .urdu:                return "🇵🇰"
        case .dutch:               return "🇳🇱"
        case .polish:              return "🇵🇱"
        case .turkish:             return "🇹🇷"
        case .swedish:             return "🇸🇪"
        case .norwegian:           return "🇳🇴"
        case .danish:              return "🇩🇰"
        case .finnish:             return "🇫🇮"
        case .greek:               return "🇬🇷"
        case .czech:               return "🇨🇿"
        case .ukrainian:           return "🇺🇦"
        case .indonesian:          return "🇮🇩"
        case .malay:               return "🇲🇾"
        case .vietnamese:          return "🇻🇳"
        case .thai:                return "🇹🇭"
        case .hebrew:              return "🇮🇱"
        case .romanian:            return "🇷🇴"
        case .hungarian:           return "🇭🇺"
        case .filipino:            return "🇵🇭"
        case .azerbaijani:         return "🇦🇿"
        case .persian:             return "🇮🇷"
        case .catalan:             return "🇪🇸"
        case .slovak:              return "🇸🇰"
        case .croatian:            return "🇭🇷"
        case .bulgarian:           return "🇧🇬"
        case .slovenian:           return "🇸🇮"
        case .lithuanian:          return "🇱🇹"
        case .latvian:             return "🇱🇻"
        case .estonian:            return "🇪🇪"
        case .swahili:             return "🇰🇪"
        case .afrikaans:           return "🇿🇦"
        case .tamil:               return "🇮🇳"
        case .marathi:             return "🇮🇳"
        }
    }

    /// Right-to-left scripts need text alignment / nav flipped. Used
    /// by the picker + future per-string callers that care.
    var isRTL: Bool {
        switch self {
        case .arabic, .hebrew, .urdu, .persian: return true
        default: return false
        }
    }

    /// Resolves a saved AppStorage code (which may be a stale entry
    /// from a removed locale) to a known case, falling back to
    /// English if nothing matches.
    static func resolve(_ raw: String) -> SupportedLocale {
        return SupportedLocale(rawValue: raw) ?? .english
    }

    /// Best initial guess from the device's preferred language list.
    /// Picks the first device preference that's also in our supported
    /// set. Lets a Spanish-speaking user open Settings and see the
    /// app already in Spanish without picking anything.
    static func deviceDefault() -> SupportedLocale {
        let preferred = Locale.preferredLanguages
        for tag in preferred {
            // Direct match (e.g. "es-ES" → strip region → "es")
            let primary = tag.split(separator: "-").first.map(String.init) ?? tag
            if let exact = SupportedLocale(rawValue: tag) { return exact }
            if let stripped = SupportedLocale(rawValue: primary) { return stripped }
            // Special cases for our region-tagged Portuguese.
            if tag.hasPrefix("pt-BR") { return .portugueseBR }
            if tag.hasPrefix("pt") { return .portuguesePT }
            if tag.hasPrefix("zh-Hant") { return .chineseTraditional }
            if tag.hasPrefix("zh") { return .chineseSimplified }
        }
        return .english
    }
}

// MARK: - String catalog keys
//
// One case per visible UI string on the redesigned Settings page (+
// the Language picker itself). Adding strings elsewhere in the app
// means appending here AND adding an English entry in
// `LocalizationService.translations[.english]`. Other locales
// inherit English until translated — no runtime crash on a missing
// key.

enum BCLoc: String, CaseIterable {
    // Header
    case settings
    case yourName
    case yourNameSubtitle

    // Section headers
    case preferences
    case account
    case supportAndLegal

    // Preferences
    case notifications
    case hapticFeedback
    case theme
    case language

    // Theme picker
    case auto
    case autoSubtitle
    case light
    case lightSubtitle
    case dark
    case darkSubtitle

    // Account
    case manageSubscription
    case signOut
    case signOutConfirmTitle

    // Support & legal
    case helpAndFaq
    case privacyPolicy
    case termsOfService

    // Banner
    case unlockProTitle
    case unlockProSubtitle
    case upgrade

    // Footer
    case deleteAccount

    // Stats strip
    case streak
    case cleaned
    case saved

    // Edit-name sheet
    case save
    case cancel

    // Language picker
    case languageSearchPlaceholder
    case languageEmptyState
    case selectLanguage

    // Photos / Videos category lists
    case photos
    case videos
    case duplicates
    case similarPhotos
    case similarScreenshots
    case screenshots
    case blurredPhotos
    case otherPhotos
    case similarVideos
    case screenRecordings
    case shortRecordings
    case longVideos
    case allClear

    // Compress
    case compress
    case noPhotosFound
    case noPhotosFoundSubtitle
    case noVideosFound
    case noVideosFoundSubtitle

    // Email error
    case email
    case backendOffline
    case backendOfflineSubtitle
    case tryAgain
    case signInWithGoogle

    // Chart customization
    case chartColors
    case activity
    case itemsCleaned
    case bestDay

    // Dashboard headers
    case quickAccess
    case spaceToClean
    case totalSpaceToClean

    // Universal UI verbs — used by buttons / sheets / chrome across
    // every flow. Centralized so a single translation update lights up
    // every screen at once.
    case done
    case delete
    case edit
    case share
    case retry
    case apply
    case filters
    case select
    case openSettings
    case keep
    case best
    case quickCleanup
    case allDone
    case notNow
    case goPro

    // Delete action bars — format strings with `%1$d` (count) and
    // `%2$@` (formatted byte size). Per-language ordering is preserved
    // by positional specifiers so SOV languages (Japanese, Korean,
    // Turkish) can place the verb at the end without breaking the
    // count or byte placeholders.
    case deleteDuplicatePhotosFormat
    case deleteSimilarPhotosFormat
    case deleteSimilarVideosFormat
    case deleteSimilarScreenshotsFormat

    // Bee's name row in Settings — label that introduces the mascot
    // rename surface. Mirrors BitePal's "Raccoon's name" row layout
    // (mascot icon → label → current name → chevron).
    case beeName
}

// MARK: - Format helper
//
// Apple's `String.localizedStringWithFormat` doesn't help us here —
// the format string itself comes out of our in-memory catalog, not
// `.strings`. This wrapper feeds the catalog template through
// `String(format:)` with positional args, so a Japanese translation
// like `"%2$@を解放するため%1$d件の写真を削除"` reorders the
// placeholders correctly. The English caller writes `%1$d` and `%2$@`
// in any order it likes.
extension BCLoc {
    func format(_ count: Int, _ bytes: String) -> String {
        let template = self.tr
        // Swift's `String(format:)` follows printf positional specifiers
        // so `%1$d` always maps to `count` and `%2$@` to `bytes`,
        // regardless of word order in the translated template.
        return String(format: template, count, bytes as CVarArg)
    }
}

// MARK: - LocalizationService

final class LocalizationService: ObservableObject {

    static let shared = LocalizationService()

    static let appLocaleKey = "preferences.appLocale"

    /// Public published state. SwiftUI views holding a
    /// `@StateObject`/`@ObservedObject` reference re-render whenever
    /// this flips. Persistence is handled in the setter so
    /// `AppStorage` and this value stay in lockstep regardless of
    /// which side initiated the change.
    @Published private(set) var current: SupportedLocale

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.appLocaleKey) ?? ""
        if stored.isEmpty {
            // First launch: seed from the device's preferred language
            // list so an international user lands in their tongue
            // without picking it from Settings first.
            let guess = SupportedLocale.deviceDefault()
            self.current = guess
            UserDefaults.standard.set(guess.rawValue, forKey: Self.appLocaleKey)
        } else {
            self.current = SupportedLocale.resolve(stored)
        }
    }

    /// Updates the active locale + persists. Triggers an
    /// `objectWillChange` so observing views re-render.
    func setLocale(_ locale: SupportedLocale) {
        guard locale != current else { return }
        current = locale
        UserDefaults.standard.set(locale.rawValue, forKey: Self.appLocaleKey)
    }

    /// Look up a localized string. Pure function — given the catalog
    /// + the active locale, returns the translated text, falling
    /// back to English when the active locale hasn't been translated
    /// for that key yet.
    func tr(_ key: BCLoc) -> String {
        if let table = LocalizationService.translations[current],
           let value = table[key] {
            return value
        }
        // English is guaranteed to be exhaustive — every BCLoc case
        // has an entry there.
        return LocalizationService.translations[.english]?[key] ?? key.rawValue
    }

    /// Apple `Locale` value matching the active selection. Useful
    /// for plumbing into `.environment(\.locale, ...)` so system
    /// formatters (numbers, dates, currency) also follow along.
    var foundationLocale: Locale {
        Locale(identifier: current.rawValue)
    }
}

// MARK: - Convenience extension

extension BCLoc {
    /// Sugar so views can write `Text(BCLoc.preferences.tr)` instead
    /// of `Text(LocalizationService.shared.tr(.preferences))`.
    var tr: String { LocalizationService.shared.tr(self) }
}

// MARK: - Translation table
//
// English is the source of truth — every case appears. Other
// locales are best-effort translations focused on the redesigned
// Settings page so an international user opening Settings sees
// their language immediately. Missing keys per locale fall through
// to English at runtime.

extension LocalizationService {
    static let translations: [SupportedLocale: [BCLoc: String]] = [

        // MARK: en
        .english: [
            .settings: "Settings",
            .yourName: "Your Name",
            .yourNameSubtitle: "Separate from your bee's name.",
            .preferences: "Preferences",
            .account: "Account",
            .supportAndLegal: "Support & Legal",
            .notifications: "Notifications",
            .hapticFeedback: "Haptic Feedback",
            .theme: "Theme",
            .language: "Language",
            .auto: "Auto",
            .autoSubtitle: "Follows time of day",
            .light: "Light",
            .lightSubtitle: "Always light theme",
            .dark: "Dark",
            .darkSubtitle: "Always dark theme",
            .manageSubscription: "Manage Subscription",
            .signOut: "Sign Out",
            .signOutConfirmTitle: "Sign Out?",
            .helpAndFaq: "Help & FAQ",
            .privacyPolicy: "Privacy Policy",
            .termsOfService: "Terms of Service",
            .unlockProTitle: "Unlock BeeClean Pro",
            .unlockProSubtitle: "Unlimited cleans, every category",
            .upgrade: "Upgrade",
            .deleteAccount: "Delete Account",
            .streak: "STREAK",
            .cleaned: "CLEANED",
            .saved: "SAVED",
            .save: "Save",
            .cancel: "Cancel",
            .languageSearchPlaceholder: "Search languages",
            .languageEmptyState: "No languages match your search.",
            .selectLanguage: "Select Language",
            .photos: "Photos",
            .videos: "Videos",
            .duplicates: "Duplicates",
            .similarPhotos: "Similar Photos",
            .similarScreenshots: "Similar Screenshots",
            .screenshots: "Screenshots",
            .blurredPhotos: "Blurred Photos",
            .otherPhotos: "Other Photos",
            .similarVideos: "Similar Videos",
            .screenRecordings: "Screen Recordings",
            .shortRecordings: "Short Recordings",
            .longVideos: "Long Videos",
            .allClear: "All clear",
            .compress: "Compress",
            .noPhotosFound: "No Photos Found",
            .noPhotosFoundSubtitle: "Take or import a photo to\nget started with compression.",
            .noVideosFound: "No Videos Found",
            .noVideosFoundSubtitle: "Record or import a video to\nget started with compression.",
            .email: "Email",
            .backendOffline: "Backend Offline",
            .backendOfflineSubtitle: "Start the backend server:\ncd apps/backend && npm run dev",
            .tryAgain: "Try Again",
            .signInWithGoogle: "Sign In with Google",
            .chartColors: "Chart colors",
            .activity: "Activity",
            .itemsCleaned: "Items Cleaned",
            .bestDay: "Best Day",
            .deleteDuplicatePhotosFormat: "Delete %1$d Duplicate Photos (%2$@)",
            .deleteSimilarPhotosFormat: "Delete %1$d Similar Photos (%2$@)",
            .deleteSimilarVideosFormat: "Delete %1$d Similar Videos (%2$@)",
            .deleteSimilarScreenshotsFormat: "Delete %1$d Similar Screenshots (%2$@)",
            .beeName: "Bee's name",
            .quickAccess: "Quick Access",
            .spaceToClean: "Space to Clean",
            .totalSpaceToClean: "Total Space to Clean",
            .done: "Done",
            .delete: "Delete",
            .edit: "Edit",
            .share: "Share",
            .retry: "Retry",
            .apply: "Apply",
            .filters: "Filters",
            .select: "Select",
            .openSettings: "Open Settings",
            .keep: "Keep",
            .best: "Best",
            .quickCleanup: "Quick Cleanup",
            .allDone: "All Done!",
            .notNow: "Not Now",
            .goPro: "Go Pro"
        ],

        // MARK: es
        .spanish: [
            .settings: "Ajustes",
            .yourName: "Tu nombre",
            .yourNameSubtitle: "Distinto del nombre de tu abeja.",
            .preferences: "Preferencias",
            .account: "Cuenta",
            .supportAndLegal: "Soporte y legal",
            .notifications: "Notificaciones",
            .hapticFeedback: "Vibración",
            .theme: "Tema",
            .language: "Idioma",
            .auto: "Automático",
            .autoSubtitle: "Según la hora del día",
            .light: "Claro",
            .lightSubtitle: "Tema claro siempre",
            .dark: "Oscuro",
            .darkSubtitle: "Tema oscuro siempre",
            .manageSubscription: "Gestionar suscripción",
            .signOut: "Cerrar sesión",
            .signOutConfirmTitle: "¿Cerrar sesión?",
            .helpAndFaq: "Ayuda y FAQ",
            .privacyPolicy: "Política de privacidad",
            .termsOfService: "Términos de servicio",
            .unlockProTitle: "Desbloquea BeeClean Pro",
            .unlockProSubtitle: "Limpiezas ilimitadas en todas las categorías",
            .upgrade: "Mejorar",
            .deleteAccount: "Eliminar cuenta",
            .streak: "RACHA",
            .cleaned: "LIMPIADO",
            .saved: "AHORRADO",
            .save: "Guardar",
            .cancel: "Cancelar",
            .languageSearchPlaceholder: "Buscar idiomas",
            .languageEmptyState: "Ningún idioma coincide con tu búsqueda.",
            .selectLanguage: "Seleccionar idioma",
            .photos: "Fotos",
            .videos: "Vídeos",
            .duplicates: "Duplicados",
            .similarPhotos: "Fotos similares",
            .similarScreenshots: "Capturas similares",
            .screenshots: "Capturas de pantalla",
            .blurredPhotos: "Fotos borrosas",
            .otherPhotos: "Otras fotos",
            .similarVideos: "Vídeos similares",
            .screenRecordings: "Grabaciones de pantalla",
            .shortRecordings: "Grabaciones cortas",
            .longVideos: "Vídeos largos",
            .allClear: "Todo limpio",
            .compress: "Comprimir",
            .noPhotosFound: "No hay fotos",
            .noPhotosFoundSubtitle: "Toma o importa una foto para\ncomenzar a comprimir.",
            .noVideosFound: "No hay vídeos",
            .noVideosFoundSubtitle: "Graba o importa un vídeo para\ncomenzar a comprimir.",
            .email: "Correo",
            .backendOffline: "Servidor desconectado",
            .backendOfflineSubtitle: "Inicia el servidor:\ncd apps/backend && npm run dev",
            .tryAgain: "Reintentar",
            .signInWithGoogle: "Iniciar sesión con Google",
            .chartColors: "Colores de gráficos",
            .activity: "Actividad",
            .itemsCleaned: "Elementos limpiados",
            .bestDay: "Mejor día",
            .deleteDuplicatePhotosFormat: "Eliminar %1$d fotos duplicadas (%2$@)",
            .deleteSimilarPhotosFormat: "Eliminar %1$d fotos similares (%2$@)",
            .deleteSimilarVideosFormat: "Eliminar %1$d vídeos similares (%2$@)",
            .deleteSimilarScreenshotsFormat: "Eliminar %1$d capturas similares (%2$@)",
            .beeName: "Nombre de la abeja",
            .quickAccess: "Acceso rápido",
            .spaceToClean: "Espacio para limpiar",
            .totalSpaceToClean: "Espacio total para limpiar",
            .done: "Listo",
            .delete: "Eliminar",
            .edit: "Editar",
            .share: "Compartir",
            .retry: "Reintentar",
            .apply: "Aplicar",
            .filters: "Filtros",
            .select: "Seleccionar",
            .openSettings: "Abrir ajustes",
            .keep: "Conservar",
            .best: "Mejor",
            .quickCleanup: "Limpieza rápida",
            .allDone: "¡Todo listo!",
            .notNow: "Ahora no",
            .goPro: "Hazte Pro"
        ],

        // MARK: fr
        .french: [
            .settings: "Réglages",
            .yourName: "Votre nom",
            .yourNameSubtitle: "Distinct du nom de votre abeille.",
            .preferences: "Préférences",
            .account: "Compte",
            .supportAndLegal: "Assistance et mentions légales",
            .notifications: "Notifications",
            .hapticFeedback: "Retour haptique",
            .theme: "Thème",
            .language: "Langue",
            .auto: "Automatique",
            .autoSubtitle: "Selon l'heure de la journée",
            .light: "Clair",
            .lightSubtitle: "Toujours en thème clair",
            .dark: "Sombre",
            .darkSubtitle: "Toujours en thème sombre",
            .manageSubscription: "Gérer l'abonnement",
            .signOut: "Se déconnecter",
            .signOutConfirmTitle: "Se déconnecter ?",
            .helpAndFaq: "Aide et FAQ",
            .privacyPolicy: "Politique de confidentialité",
            .termsOfService: "Conditions d'utilisation",
            .unlockProTitle: "Débloquer BeeClean Pro",
            .unlockProSubtitle: "Nettoyages illimités, toutes catégories",
            .upgrade: "Passer Pro",
            .deleteAccount: "Supprimer le compte",
            .streak: "SÉRIE",
            .cleaned: "NETTOYÉS",
            .saved: "ÉCONOMISÉ",
            .save: "Enregistrer",
            .cancel: "Annuler",
            .languageSearchPlaceholder: "Rechercher des langues",
            .languageEmptyState: "Aucune langue ne correspond à votre recherche.",
            .selectLanguage: "Choisir la langue",
            .photos: "Photos",
            .videos: "Vidéos",
            .duplicates: "Doublons",
            .similarPhotos: "Photos similaires",
            .similarScreenshots: "Captures similaires",
            .screenshots: "Captures d'écran",
            .blurredPhotos: "Photos floues",
            .otherPhotos: "Autres photos",
            .similarVideos: "Vidéos similaires",
            .screenRecordings: "Enregistrements d'écran",
            .shortRecordings: "Enregistrements courts",
            .longVideos: "Vidéos longues",
            .allClear: "Tout propre",
            .compress: "Compresser",
            .noPhotosFound: "Aucune photo",
            .noPhotosFoundSubtitle: "Prenez ou importez une photo pour\ncommencer la compression.",
            .noVideosFound: "Aucune vidéo",
            .noVideosFoundSubtitle: "Enregistrez ou importez une vidéo pour\ncommencer la compression.",
            .email: "E-mail",
            .backendOffline: "Serveur hors ligne",
            .backendOfflineSubtitle: "Démarrez le serveur :\ncd apps/backend && npm run dev",
            .tryAgain: "Réessayer",
            .signInWithGoogle: "Se connecter avec Google",
            .chartColors: "Couleurs des graphiques",
            .activity: "Activité",
            .itemsCleaned: "Éléments nettoyés",
            .bestDay: "Meilleur jour",
            .deleteDuplicatePhotosFormat: "Supprimer %1$d photos en double (%2$@)",
            .deleteSimilarPhotosFormat: "Supprimer %1$d photos similaires (%2$@)",
            .deleteSimilarVideosFormat: "Supprimer %1$d vidéos similaires (%2$@)",
            .deleteSimilarScreenshotsFormat: "Supprimer %1$d captures similaires (%2$@)",
            .beeName: "Nom de l'abeille",
            .quickAccess: "Accès rapide",
            .spaceToClean: "Espace à nettoyer",
            .totalSpaceToClean: "Espace total à nettoyer",
            .done: "Terminé",
            .delete: "Supprimer",
            .edit: "Modifier",
            .share: "Partager",
            .retry: "Réessayer",
            .apply: "Appliquer",
            .filters: "Filtres",
            .select: "Sélectionner",
            .openSettings: "Ouvrir Réglages",
            .keep: "Garder",
            .best: "Meilleur",
            .quickCleanup: "Nettoyage rapide",
            .allDone: "Terminé !",
            .notNow: "Pas maintenant",
            .goPro: "Passer à Pro"
        ],

        // MARK: de
        .german: [
            .settings: "Einstellungen",
            .yourName: "Dein Name",
            .yourNameSubtitle: "Unabhängig vom Namen deiner Biene.",
            .preferences: "Einstellungen",
            .account: "Konto",
            .supportAndLegal: "Support & Rechtliches",
            .notifications: "Benachrichtigungen",
            .hapticFeedback: "Haptisches Feedback",
            .theme: "Erscheinungsbild",
            .language: "Sprache",
            .auto: "Automatisch",
            .autoSubtitle: "Folgt der Tageszeit",
            .light: "Hell",
            .lightSubtitle: "Immer helles Design",
            .dark: "Dunkel",
            .darkSubtitle: "Immer dunkles Design",
            .manageSubscription: "Abo verwalten",
            .signOut: "Abmelden",
            .signOutConfirmTitle: "Abmelden?",
            .helpAndFaq: "Hilfe & FAQ",
            .privacyPolicy: "Datenschutz",
            .termsOfService: "Nutzungsbedingungen",
            .unlockProTitle: "BeeClean Pro freischalten",
            .unlockProSubtitle: "Unbegrenztes Aufräumen, jede Kategorie",
            .upgrade: "Upgrade",
            .deleteAccount: "Konto löschen",
            .streak: "SERIE",
            .cleaned: "AUFGERÄUMT",
            .saved: "GESPART",
            .save: "Speichern",
            .cancel: "Abbrechen",
            .languageSearchPlaceholder: "Sprachen suchen",
            .languageEmptyState: "Keine Sprache entspricht deiner Suche.",
            .selectLanguage: "Sprache wählen",
            .photos: "Fotos",
            .videos: "Videos",
            .duplicates: "Duplikate",
            .similarPhotos: "Ähnliche Fotos",
            .similarScreenshots: "Ähnliche Screenshots",
            .screenshots: "Screenshots",
            .blurredPhotos: "Unscharfe Fotos",
            .otherPhotos: "Andere Fotos",
            .similarVideos: "Ähnliche Videos",
            .screenRecordings: "Bildschirmaufnahmen",
            .shortRecordings: "Kurze Aufnahmen",
            .longVideos: "Lange Videos",
            .allClear: "Alles aufgeräumt",
            .compress: "Komprimieren",
            .noPhotosFound: "Keine Fotos",
            .noPhotosFoundSubtitle: "Mache oder importiere ein Foto, um\nmit dem Komprimieren zu starten.",
            .noVideosFound: "Keine Videos",
            .noVideosFoundSubtitle: "Nimm ein Video auf oder importiere eines,\num mit dem Komprimieren zu starten.",
            .email: "E-Mail",
            .backendOffline: "Server offline",
            .backendOfflineSubtitle: "Starte den Server:\ncd apps/backend && npm run dev",
            .tryAgain: "Erneut versuchen",
            .signInWithGoogle: "Mit Google anmelden",
            .chartColors: "Diagrammfarben",
            .activity: "Aktivität",
            .itemsCleaned: "Aufgeräumte Elemente",
            .bestDay: "Bester Tag",
            .deleteDuplicatePhotosFormat: "%1$d doppelte Fotos löschen (%2$@)",
            .deleteSimilarPhotosFormat: "%1$d ähnliche Fotos löschen (%2$@)",
            .deleteSimilarVideosFormat: "%1$d ähnliche Videos löschen (%2$@)",
            .deleteSimilarScreenshotsFormat: "%1$d ähnliche Screenshots löschen (%2$@)",
            .beeName: "Name der Biene",
            .quickAccess: "Schnellzugriff",
            .spaceToClean: "Speicher freigeben",
            .totalSpaceToClean: "Gesamter Speicher zum Freigeben",
            .done: "Fertig",
            .delete: "Löschen",
            .edit: "Bearbeiten",
            .share: "Teilen",
            .retry: "Wiederholen",
            .apply: "Anwenden",
            .filters: "Filter",
            .select: "Auswählen",
            .openSettings: "Einstellungen öffnen",
            .keep: "Behalten",
            .best: "Beste",
            .quickCleanup: "Schnelle Bereinigung",
            .allDone: "Alles erledigt!",
            .notNow: "Nicht jetzt",
            .goPro: "Pro werden"
        ],

        // MARK: it
        .italian: [
            .settings: "Impostazioni",
            .yourName: "Il tuo nome",
            .yourNameSubtitle: "Diverso dal nome della tua ape.",
            .preferences: "Preferenze",
            .account: "Account",
            .supportAndLegal: "Supporto e note legali",
            .notifications: "Notifiche",
            .hapticFeedback: "Feedback aptico",
            .theme: "Tema",
            .language: "Lingua",
            .auto: "Automatico",
            .autoSubtitle: "Segue l'ora del giorno",
            .light: "Chiaro",
            .lightSubtitle: "Sempre tema chiaro",
            .dark: "Scuro",
            .darkSubtitle: "Sempre tema scuro",
            .manageSubscription: "Gestisci abbonamento",
            .signOut: "Esci",
            .signOutConfirmTitle: "Uscire?",
            .helpAndFaq: "Aiuto e FAQ",
            .privacyPolicy: "Informativa sulla privacy",
            .termsOfService: "Termini di servizio",
            .unlockProTitle: "Sblocca BeeClean Pro",
            .unlockProSubtitle: "Pulizie illimitate in ogni categoria",
            .upgrade: "Passa a Pro",
            .deleteAccount: "Elimina account",
            .streak: "SERIE",
            .cleaned: "PULITI",
            .saved: "RISPARMIATO",
            .save: "Salva",
            .cancel: "Annulla",
            .languageSearchPlaceholder: "Cerca lingue",
            .languageEmptyState: "Nessuna lingua corrisponde alla ricerca.",
            .selectLanguage: "Seleziona lingua",
            .photos: "Foto",
            .videos: "Video",
            .duplicates: "Duplicati",
            .similarPhotos: "Foto simili",
            .similarScreenshots: "Screenshot simili",
            .screenshots: "Screenshot",
            .blurredPhotos: "Foto sfocate",
            .otherPhotos: "Altre foto",
            .similarVideos: "Video simili",
            .screenRecordings: "Registrazioni schermo",
            .shortRecordings: "Registrazioni brevi",
            .longVideos: "Video lunghi",
            .allClear: "Tutto pulito",
            .compress: "Comprimi",
            .noPhotosFound: "Nessuna foto",
            .noPhotosFoundSubtitle: "Scatta o importa una foto per\niniziare la compressione.",
            .noVideosFound: "Nessun video",
            .noVideosFoundSubtitle: "Registra o importa un video per\niniziare la compressione.",
            .email: "Email",
            .backendOffline: "Server offline",
            .backendOfflineSubtitle: "Avvia il server:\ncd apps/backend && npm run dev",
            .tryAgain: "Riprova",
            .signInWithGoogle: "Accedi con Google",
            .chartColors: "Colori dei grafici",
            .activity: "Attività",
            .itemsCleaned: "Elementi puliti",
            .bestDay: "Giorno migliore",
            .deleteDuplicatePhotosFormat: "Elimina %1$d foto duplicate (%2$@)",
            .deleteSimilarPhotosFormat: "Elimina %1$d foto simili (%2$@)",
            .deleteSimilarVideosFormat: "Elimina %1$d video simili (%2$@)",
            .deleteSimilarScreenshotsFormat: "Elimina %1$d screenshot simili (%2$@)",
            .beeName: "Nome dell'ape",
            .quickAccess: "Accesso rapido",
            .spaceToClean: "Spazio da liberare",
            .totalSpaceToClean: "Spazio totale da liberare",
            .done: "Fatto",
            .delete: "Elimina",
            .edit: "Modifica",
            .share: "Condividi",
            .retry: "Riprova",
            .apply: "Applica",
            .filters: "Filtri",
            .select: "Seleziona",
            .openSettings: "Apri Impostazioni",
            .keep: "Conserva",
            .best: "Migliore",
            .quickCleanup: "Pulizia rapida",
            .allDone: "Tutto fatto!",
            .notNow: "Non ora",
            .goPro: "Passa a Pro"
        ],

        // MARK: pt-BR
        .portugueseBR: [
            .settings: "Ajustes",
            .yourName: "Seu nome",
            .yourNameSubtitle: "Diferente do nome da sua abelha.",
            .preferences: "Preferências",
            .account: "Conta",
            .supportAndLegal: "Suporte e legal",
            .notifications: "Notificações",
            .hapticFeedback: "Vibração",
            .theme: "Tema",
            .language: "Idioma",
            .auto: "Automático",
            .autoSubtitle: "Segue a hora do dia",
            .light: "Claro",
            .lightSubtitle: "Sempre tema claro",
            .dark: "Escuro",
            .darkSubtitle: "Sempre tema escuro",
            .manageSubscription: "Gerenciar assinatura",
            .signOut: "Sair",
            .signOutConfirmTitle: "Sair?",
            .helpAndFaq: "Ajuda e perguntas",
            .privacyPolicy: "Política de privacidade",
            .termsOfService: "Termos de serviço",
            .unlockProTitle: "Desbloqueie o BeeClean Pro",
            .unlockProSubtitle: "Limpezas ilimitadas em todas as categorias",
            .upgrade: "Assinar",
            .deleteAccount: "Excluir conta",
            .streak: "SEQUÊNCIA",
            .cleaned: "LIMPOS",
            .saved: "ECONOMIZADO",
            .save: "Salvar",
            .cancel: "Cancelar",
            .languageSearchPlaceholder: "Pesquisar idiomas",
            .languageEmptyState: "Nenhum idioma corresponde à pesquisa.",
            .selectLanguage: "Selecionar idioma",
            .photos: "Fotos",
            .videos: "Vídeos",
            .duplicates: "Duplicadas",
            .similarPhotos: "Fotos similares",
            .similarScreenshots: "Capturas similares",
            .screenshots: "Capturas de tela",
            .blurredPhotos: "Fotos borradas",
            .otherPhotos: "Outras fotos",
            .similarVideos: "Vídeos similares",
            .screenRecordings: "Gravações de tela",
            .shortRecordings: "Gravações curtas",
            .longVideos: "Vídeos longos",
            .allClear: "Tudo limpo",
            .compress: "Comprimir",
            .noPhotosFound: "Sem fotos",
            .noPhotosFoundSubtitle: "Tire ou importe uma foto para\ncomeçar a compressão.",
            .noVideosFound: "Sem vídeos",
            .noVideosFoundSubtitle: "Grave ou importe um vídeo para\ncomeçar a compressão.",
            .email: "E-mail",
            .backendOffline: "Servidor offline",
            .backendOfflineSubtitle: "Inicie o servidor:\ncd apps/backend && npm run dev",
            .tryAgain: "Tentar novamente",
            .signInWithGoogle: "Entrar com Google",
            .chartColors: "Cores dos gráficos",
            .activity: "Atividade",
            .itemsCleaned: "Itens limpos",
            .bestDay: "Melhor dia",
            .deleteDuplicatePhotosFormat: "Excluir %1$d fotos duplicadas (%2$@)",
            .deleteSimilarPhotosFormat: "Excluir %1$d fotos similares (%2$@)",
            .deleteSimilarVideosFormat: "Excluir %1$d vídeos similares (%2$@)",
            .deleteSimilarScreenshotsFormat: "Excluir %1$d capturas similares (%2$@)",
            .beeName: "Nome da abelha",
            .quickAccess: "Acesso rápido",
            .spaceToClean: "Espaço a limpar",
            .totalSpaceToClean: "Espaço total a limpar",
            .done: "Concluído",
            .delete: "Excluir",
            .edit: "Editar",
            .share: "Compartilhar",
            .retry: "Tentar novamente",
            .apply: "Aplicar",
            .filters: "Filtros",
            .select: "Selecionar",
            .openSettings: "Abrir Ajustes",
            .keep: "Manter",
            .best: "Melhor",
            .quickCleanup: "Limpeza rápida",
            .allDone: "Tudo pronto!",
            .notNow: "Agora não",
            .goPro: "Virar Pro"
        ],

        // MARK: pt-PT
        .portuguesePT: [
            .settings: "Definições",
            .yourName: "O teu nome",
            .yourNameSubtitle: "Diferente do nome da tua abelha.",
            .preferences: "Preferências",
            .account: "Conta",
            .supportAndLegal: "Apoio e legal",
            .notifications: "Notificações",
            .hapticFeedback: "Vibração",
            .theme: "Tema",
            .language: "Idioma",
            .auto: "Automático",
            .autoSubtitle: "Segue a hora do dia",
            .light: "Claro",
            .lightSubtitle: "Tema claro sempre",
            .dark: "Escuro",
            .darkSubtitle: "Tema escuro sempre",
            .manageSubscription: "Gerir subscrição",
            .signOut: "Terminar sessão",
            .signOutConfirmTitle: "Terminar sessão?",
            .helpAndFaq: "Ajuda e FAQ",
            .privacyPolicy: "Política de privacidade",
            .termsOfService: "Termos de serviço",
            .unlockProTitle: "Desbloquear BeeClean Pro",
            .unlockProSubtitle: "Limpezas ilimitadas, todas as categorias",
            .upgrade: "Subscrever",
            .deleteAccount: "Eliminar conta",
            .streak: "SEQUÊNCIA",
            .cleaned: "LIMPOS",
            .saved: "POUPADO",
            .save: "Guardar",
            .cancel: "Cancelar",
            .languageSearchPlaceholder: "Procurar idiomas",
            .languageEmptyState: "Nenhum idioma corresponde à procura.",
            .selectLanguage: "Selecionar idioma",
            .photos: "Fotos",
            .videos: "Vídeos",
            .duplicates: "Duplicadas",
            .similarPhotos: "Fotos semelhantes",
            .similarScreenshots: "Capturas semelhantes",
            .screenshots: "Capturas de ecrã",
            .blurredPhotos: "Fotos desfocadas",
            .otherPhotos: "Outras fotos",
            .similarVideos: "Vídeos semelhantes",
            .screenRecordings: "Gravações de ecrã",
            .shortRecordings: "Gravações curtas",
            .longVideos: "Vídeos longos",
            .allClear: "Tudo limpo",
            .compress: "Comprimir",
            .noPhotosFound: "Sem fotos",
            .noPhotosFoundSubtitle: "Tira ou importa uma foto para\ncomeçar a compressão.",
            .noVideosFound: "Sem vídeos",
            .noVideosFoundSubtitle: "Grava ou importa um vídeo para\ncomeçar a compressão.",
            .email: "E-mail",
            .backendOffline: "Servidor offline",
            .backendOfflineSubtitle: "Inicia o servidor:\ncd apps/backend && npm run dev",
            .tryAgain: "Tentar novamente",
            .signInWithGoogle: "Iniciar sessão com Google",
            .chartColors: "Cores dos gráficos",
            .activity: "Atividade",
            .itemsCleaned: "Itens limpos",
            .bestDay: "Melhor dia",
            .deleteDuplicatePhotosFormat: "Eliminar %1$d fotos duplicadas (%2$@)",
            .deleteSimilarPhotosFormat: "Eliminar %1$d fotos semelhantes (%2$@)",
            .deleteSimilarVideosFormat: "Eliminar %1$d vídeos semelhantes (%2$@)",
            .deleteSimilarScreenshotsFormat: "Eliminar %1$d capturas semelhantes (%2$@)",
            .beeName: "Nome da abelha",
            .quickAccess: "Acesso rápido",
            .spaceToClean: "Espaço para limpar",
            .totalSpaceToClean: "Espaço total para limpar",
            .done: "Concluído",
            .delete: "Eliminar",
            .edit: "Editar",
            .share: "Partilhar",
            .retry: "Tentar novamente",
            .apply: "Aplicar",
            .filters: "Filtros",
            .select: "Selecionar",
            .openSettings: "Abrir Definições",
            .keep: "Manter",
            .best: "Melhor",
            .quickCleanup: "Limpeza rápida",
            .allDone: "Tudo pronto!",
            .notNow: "Agora não",
            .goPro: "Tornar-se Pro"
        ],

        // MARK: ru
        .russian: [
            .settings: "Настройки",
            .yourName: "Ваше имя",
            .yourNameSubtitle: "Отличается от имени вашей пчелы.",
            .preferences: "Предпочтения",
            .account: "Аккаунт",
            .supportAndLegal: "Поддержка и правовая информация",
            .notifications: "Уведомления",
            .hapticFeedback: "Тактильная отдача",
            .theme: "Тема",
            .language: "Язык",
            .auto: "Авто",
            .autoSubtitle: "По времени суток",
            .light: "Светлая",
            .lightSubtitle: "Всегда светлая",
            .dark: "Тёмная",
            .darkSubtitle: "Всегда тёмная",
            .manageSubscription: "Управление подпиской",
            .signOut: "Выйти",
            .signOutConfirmTitle: "Выйти?",
            .helpAndFaq: "Помощь и FAQ",
            .privacyPolicy: "Политика конфиденциальности",
            .termsOfService: "Условия использования",
            .unlockProTitle: "Откройте BeeClean Pro",
            .unlockProSubtitle: "Безлимит во всех категориях",
            .upgrade: "Улучшить",
            .deleteAccount: "Удалить аккаунт",
            .streak: "СЕРИЯ",
            .cleaned: "ОЧИЩЕНО",
            .saved: "СЭКОНОМЛЕНО",
            .save: "Сохранить",
            .cancel: "Отмена",
            .languageSearchPlaceholder: "Поиск языков",
            .languageEmptyState: "Ни один язык не найден.",
            .selectLanguage: "Выберите язык",
            .photos: "Фото",
            .videos: "Видео",
            .duplicates: "Дубликаты",
            .similarPhotos: "Похожие фото",
            .similarScreenshots: "Похожие скриншоты",
            .screenshots: "Скриншоты",
            .blurredPhotos: "Размытые фото",
            .otherPhotos: "Другие фото",
            .similarVideos: "Похожие видео",
            .screenRecordings: "Записи экрана",
            .shortRecordings: "Короткие записи",
            .longVideos: "Длинные видео",
            .allClear: "Всё чисто",
            .compress: "Сжать",
            .noPhotosFound: "Нет фото",
            .noPhotosFoundSubtitle: "Сделайте или импортируйте фото,\nчтобы начать сжатие.",
            .noVideosFound: "Нет видео",
            .noVideosFoundSubtitle: "Запишите или импортируйте видео,\nчтобы начать сжатие.",
            .email: "Почта",
            .backendOffline: "Сервер недоступен",
            .backendOfflineSubtitle: "Запустите сервер:\ncd apps/backend && npm run dev",
            .tryAgain: "Повторить",
            .signInWithGoogle: "Войти через Google",
            .chartColors: "Цвета графиков",
            .activity: "Активность",
            .itemsCleaned: "Очищено",
            .bestDay: "Лучший день",
            .deleteDuplicatePhotosFormat: "Удалить %1$d дубликатов фото (%2$@)",
            .deleteSimilarPhotosFormat: "Удалить %1$d похожих фото (%2$@)",
            .deleteSimilarVideosFormat: "Удалить %1$d похожих видео (%2$@)",
            .deleteSimilarScreenshotsFormat: "Удалить %1$d похожих скриншотов (%2$@)",
            .beeName: "Имя пчелы",
            .quickAccess: "Быстрый доступ",
            .spaceToClean: "Свободное место",
            .totalSpaceToClean: "Всего места для очистки",
            .done: "Готово",
            .delete: "Удалить",
            .edit: "Изменить",
            .share: "Поделиться",
            .retry: "Повторить",
            .apply: "Применить",
            .filters: "Фильтры",
            .select: "Выбрать",
            .openSettings: "Открыть настройки",
            .keep: "Оставить",
            .best: "Лучший",
            .quickCleanup: "Быстрая очистка",
            .allDone: "Всё готово!",
            .notNow: "Не сейчас",
            .goPro: "Перейти на Pro"
        ],

        // MARK: zh-Hans
        .chineseSimplified: [
            .settings: "设置",
            .yourName: "你的名字",
            .yourNameSubtitle: "与你的蜜蜂名字不同。",
            .preferences: "偏好",
            .account: "账户",
            .supportAndLegal: "支持与法律",
            .notifications: "通知",
            .hapticFeedback: "触感反馈",
            .theme: "主题",
            .language: "语言",
            .auto: "自动",
            .autoSubtitle: "跟随时间变化",
            .light: "浅色",
            .lightSubtitle: "始终为浅色",
            .dark: "深色",
            .darkSubtitle: "始终为深色",
            .manageSubscription: "管理订阅",
            .signOut: "退出登录",
            .signOutConfirmTitle: "退出登录？",
            .helpAndFaq: "帮助与常见问题",
            .privacyPolicy: "隐私政策",
            .termsOfService: "服务条款",
            .unlockProTitle: "解锁 BeeClean Pro",
            .unlockProSubtitle: "全类别无限清理",
            .upgrade: "升级",
            .deleteAccount: "删除账户",
            .streak: "连胜",
            .cleaned: "已清理",
            .saved: "已节省",
            .save: "保存",
            .cancel: "取消",
            .languageSearchPlaceholder: "搜索语言",
            .languageEmptyState: "没有匹配的语言。",
            .selectLanguage: "选择语言",
            .photos: "照片",
            .videos: "视频",
            .duplicates: "重复项",
            .similarPhotos: "相似照片",
            .similarScreenshots: "相似截图",
            .screenshots: "截图",
            .blurredPhotos: "模糊照片",
            .otherPhotos: "其他照片",
            .similarVideos: "相似视频",
            .screenRecordings: "屏幕录制",
            .shortRecordings: "短录制",
            .longVideos: "长视频",
            .allClear: "全部清理",
            .compress: "压缩",
            .noPhotosFound: "暂无照片",
            .noPhotosFoundSubtitle: "拍摄或导入一张照片\n开始压缩。",
            .noVideosFound: "暂无视频",
            .noVideosFoundSubtitle: "录制或导入一个视频\n开始压缩。",
            .email: "邮件",
            .backendOffline: "后端离线",
            .backendOfflineSubtitle: "启动后端服务器:\ncd apps/backend && npm run dev",
            .tryAgain: "重试",
            .signInWithGoogle: "使用 Google 登录",
            .chartColors: "图表颜色",
            .activity: "活动",
            .itemsCleaned: "已清理",
            .bestDay: "最佳日",
            .deleteDuplicatePhotosFormat: "删除 %1$d 张重复照片 (%2$@)",
            .deleteSimilarPhotosFormat: "删除 %1$d 张相似照片 (%2$@)",
            .deleteSimilarVideosFormat: "删除 %1$d 个相似视频 (%2$@)",
            .deleteSimilarScreenshotsFormat: "删除 %1$d 张相似截图 (%2$@)",
            .beeName: "蜜蜂的名字",
            .quickAccess: "快速访问",
            .spaceToClean: "待清理空间",
            .totalSpaceToClean: "总清理空间",
            .done: "完成",
            .delete: "删除",
            .edit: "编辑",
            .share: "分享",
            .retry: "重试",
            .apply: "应用",
            .filters: "筛选",
            .select: "选择",
            .openSettings: "打开设置",
            .keep: "保留",
            .best: "最佳",
            .quickCleanup: "快速清理",
            .allDone: "全部完成！",
            .notNow: "暂不",
            .goPro: "升级到 Pro"
        ],

        // MARK: zh-Hant
        .chineseTraditional: [
            .settings: "設定",
            .yourName: "你的名字",
            .yourNameSubtitle: "與你的蜜蜂名字不同。",
            .preferences: "偏好設定",
            .account: "帳號",
            .supportAndLegal: "支援與法律",
            .notifications: "通知",
            .hapticFeedback: "觸覺回饋",
            .theme: "主題",
            .language: "語言",
            .auto: "自動",
            .autoSubtitle: "依時間自動切換",
            .light: "淺色",
            .lightSubtitle: "永遠淺色",
            .dark: "深色",
            .darkSubtitle: "永遠深色",
            .manageSubscription: "管理訂閱",
            .signOut: "登出",
            .signOutConfirmTitle: "登出？",
            .helpAndFaq: "說明與常見問題",
            .privacyPolicy: "隱私權政策",
            .termsOfService: "服務條款",
            .unlockProTitle: "解鎖 BeeClean Pro",
            .unlockProSubtitle: "無限清理、所有類別",
            .upgrade: "升級",
            .deleteAccount: "刪除帳號",
            .streak: "連勝",
            .cleaned: "已清理",
            .saved: "已節省",
            .save: "儲存",
            .cancel: "取消",
            .languageSearchPlaceholder: "搜尋語言",
            .languageEmptyState: "沒有符合的語言。",
            .selectLanguage: "選擇語言",
            .photos: "相片",
            .videos: "影片",
            .duplicates: "重複項目",
            .similarPhotos: "相似相片",
            .similarScreenshots: "相似截圖",
            .screenshots: "截圖",
            .blurredPhotos: "模糊相片",
            .otherPhotos: "其他相片",
            .similarVideos: "相似影片",
            .screenRecordings: "螢幕錄製",
            .shortRecordings: "短錄製",
            .longVideos: "長影片",
            .allClear: "全部清理",
            .compress: "壓縮",
            .noPhotosFound: "沒有相片",
            .noPhotosFoundSubtitle: "拍攝或匯入一張相片\n開始壓縮。",
            .noVideosFound: "沒有影片",
            .noVideosFoundSubtitle: "錄製或匯入影片\n開始壓縮。",
            .email: "電郵",
            .backendOffline: "後端離線",
            .backendOfflineSubtitle: "啟動後端伺服器:\ncd apps/backend && npm run dev",
            .tryAgain: "重試",
            .signInWithGoogle: "使用 Google 登入",
            .chartColors: "圖表顏色",
            .activity: "活動",
            .itemsCleaned: "已清理",
            .bestDay: "最佳日",
            .deleteDuplicatePhotosFormat: "刪除 %1$d 張重複相片 (%2$@)",
            .deleteSimilarPhotosFormat: "刪除 %1$d 張相似相片 (%2$@)",
            .deleteSimilarVideosFormat: "刪除 %1$d 部相似影片 (%2$@)",
            .deleteSimilarScreenshotsFormat: "刪除 %1$d 張相似截圖 (%2$@)",
            .beeName: "蜜蜂的名字",
            .quickAccess: "快速存取",
            .spaceToClean: "待清理空間",
            .totalSpaceToClean: "總清理空間",
            .done: "完成",
            .delete: "刪除",
            .edit: "編輯",
            .share: "分享",
            .retry: "重試",
            .apply: "套用",
            .filters: "篩選",
            .select: "選擇",
            .openSettings: "打開設定",
            .keep: "保留",
            .best: "最佳",
            .quickCleanup: "快速清理",
            .allDone: "全部完成！",
            .notNow: "暫不",
            .goPro: "升級到 Pro"
        ],

        // MARK: ja
        .japanese: [
            .settings: "設定",
            .yourName: "あなたの名前",
            .yourNameSubtitle: "ミツバチの名前とは別です。",
            .preferences: "環境設定",
            .account: "アカウント",
            .supportAndLegal: "サポートと法的情報",
            .notifications: "通知",
            .hapticFeedback: "触覚フィードバック",
            .theme: "テーマ",
            .language: "言語",
            .auto: "自動",
            .autoSubtitle: "時刻に追従",
            .light: "ライト",
            .lightSubtitle: "常にライトテーマ",
            .dark: "ダーク",
            .darkSubtitle: "常にダークテーマ",
            .manageSubscription: "サブスクリプションを管理",
            .signOut: "サインアウト",
            .signOutConfirmTitle: "サインアウトしますか？",
            .helpAndFaq: "ヘルプとよくある質問",
            .privacyPolicy: "プライバシーポリシー",
            .termsOfService: "利用規約",
            .unlockProTitle: "BeeClean Pro を解放",
            .unlockProSubtitle: "全カテゴリ無制限のお掃除",
            .upgrade: "アップグレード",
            .deleteAccount: "アカウントを削除",
            .streak: "連続",
            .cleaned: "片付け",
            .saved: "節約",
            .save: "保存",
            .cancel: "キャンセル",
            .languageSearchPlaceholder: "言語を検索",
            .languageEmptyState: "一致する言語がありません。",
            .selectLanguage: "言語を選択",
            .photos: "写真",
            .videos: "ビデオ",
            .duplicates: "重複",
            .similarPhotos: "類似写真",
            .similarScreenshots: "類似スクショ",
            .screenshots: "スクリーンショット",
            .blurredPhotos: "ぼけ写真",
            .otherPhotos: "その他の写真",
            .similarVideos: "類似ビデオ",
            .screenRecordings: "画面収録",
            .shortRecordings: "短い録画",
            .longVideos: "長いビデオ",
            .allClear: "すべて完了",
            .compress: "圧縮",
            .noPhotosFound: "写真がありません",
            .noPhotosFoundSubtitle: "写真を撮るか読み込んで\n圧縮を開始します。",
            .noVideosFound: "ビデオがありません",
            .noVideosFoundSubtitle: "ビデオを録画するか読み込んで\n圧縮を開始します。",
            .email: "メール",
            .backendOffline: "バックエンドオフライン",
            .backendOfflineSubtitle: "バックエンドサーバーを起動:\ncd apps/backend && npm run dev",
            .tryAgain: "再試行",
            .signInWithGoogle: "Google でサインイン",
            .chartColors: "チャートの色",
            .activity: "アクティビティ",
            .itemsCleaned: "片付けた数",
            .bestDay: "ベストデイ",
            .deleteDuplicatePhotosFormat: "重複写真 %1$d 枚を削除（%2$@）",
            .deleteSimilarPhotosFormat: "類似写真 %1$d 枚を削除（%2$@）",
            .deleteSimilarVideosFormat: "類似ビデオ %1$d 本を削除（%2$@）",
            .deleteSimilarScreenshotsFormat: "類似スクショ %1$d 枚を削除（%2$@）",
            .beeName: "ミツバチの名前",
            .quickAccess: "クイックアクセス",
            .spaceToClean: "整理する容量",
            .totalSpaceToClean: "整理する合計容量",
            .done: "完了",
            .delete: "削除",
            .edit: "編集",
            .share: "共有",
            .retry: "再試行",
            .apply: "適用",
            .filters: "フィルター",
            .select: "選択",
            .openSettings: "設定を開く",
            .keep: "残す",
            .best: "ベスト",
            .quickCleanup: "クイッククリーンアップ",
            .allDone: "完了しました！",
            .notNow: "今はしない",
            .goPro: "Proに登録"
        ],

        // MARK: ko
        .korean: [
            .settings: "설정",
            .yourName: "이름",
            .yourNameSubtitle: "벌의 이름과는 별개입니다.",
            .preferences: "환경설정",
            .account: "계정",
            .supportAndLegal: "지원 및 법적 고지",
            .notifications: "알림",
            .hapticFeedback: "햅틱 피드백",
            .theme: "테마",
            .language: "언어",
            .auto: "자동",
            .autoSubtitle: "시간대에 따라",
            .light: "라이트",
            .lightSubtitle: "항상 밝게",
            .dark: "다크",
            .darkSubtitle: "항상 어둡게",
            .manageSubscription: "구독 관리",
            .signOut: "로그아웃",
            .signOutConfirmTitle: "로그아웃하시겠습니까?",
            .helpAndFaq: "도움말 및 FAQ",
            .privacyPolicy: "개인정보처리방침",
            .termsOfService: "이용약관",
            .unlockProTitle: "BeeClean Pro 잠금 해제",
            .unlockProSubtitle: "모든 카테고리 무제한 정리",
            .upgrade: "업그레이드",
            .deleteAccount: "계정 삭제",
            .streak: "연속",
            .cleaned: "정리됨",
            .saved: "절약됨",
            .save: "저장",
            .cancel: "취소",
            .languageSearchPlaceholder: "언어 검색",
            .languageEmptyState: "검색과 일치하는 언어가 없습니다.",
            .selectLanguage: "언어 선택",
            .photos: "사진",
            .videos: "동영상",
            .duplicates: "중복 항목",
            .similarPhotos: "유사한 사진",
            .similarScreenshots: "유사한 스크린샷",
            .screenshots: "스크린샷",
            .blurredPhotos: "흐릿한 사진",
            .otherPhotos: "기타 사진",
            .similarVideos: "유사한 동영상",
            .screenRecordings: "화면 녹화",
            .shortRecordings: "짧은 녹화",
            .longVideos: "긴 동영상",
            .allClear: "모두 정리됨",
            .compress: "압축",
            .noPhotosFound: "사진이 없습니다",
            .noPhotosFoundSubtitle: "사진을 찍거나 가져와서\n압축을 시작하세요.",
            .noVideosFound: "동영상이 없습니다",
            .noVideosFoundSubtitle: "동영상을 녹화하거나 가져와서\n압축을 시작하세요.",
            .email: "이메일",
            .backendOffline: "백엔드 오프라인",
            .backendOfflineSubtitle: "백엔드 서버를 시작하세요:\ncd apps/backend && npm run dev",
            .tryAgain: "다시 시도",
            .signInWithGoogle: "Google로 로그인",
            .chartColors: "차트 색상",
            .activity: "활동",
            .itemsCleaned: "정리됨",
            .bestDay: "최고의 날",
            .deleteDuplicatePhotosFormat: "중복 사진 %1$d장 삭제 (%2$@)",
            .deleteSimilarPhotosFormat: "유사한 사진 %1$d장 삭제 (%2$@)",
            .deleteSimilarVideosFormat: "유사한 동영상 %1$d개 삭제 (%2$@)",
            .deleteSimilarScreenshotsFormat: "유사한 스크린샷 %1$d장 삭제 (%2$@)",
            .beeName: "벌의 이름",
            .quickAccess: "빠른 액세스",
            .spaceToClean: "정리할 공간",
            .totalSpaceToClean: "총 정리할 공간",
            .done: "완료",
            .delete: "삭제",
            .edit: "편집",
            .share: "공유",
            .retry: "다시 시도",
            .apply: "적용",
            .filters: "필터",
            .select: "선택",
            .openSettings: "설정 열기",
            .keep: "보관",
            .best: "최고",
            .quickCleanup: "빠른 정리",
            .allDone: "모두 완료!",
            .notNow: "나중에",
            .goPro: "Pro로 업그레이드"
        ],

        // MARK: ar
        .arabic: [
            .settings: "الإعدادات",
            .yourName: "اسمك",
            .yourNameSubtitle: "منفصل عن اسم نحلتك.",
            .preferences: "التفضيلات",
            .account: "الحساب",
            .supportAndLegal: "الدعم والمعلومات القانونية",
            .notifications: "الإشعارات",
            .hapticFeedback: "اللمس التفاعلي",
            .theme: "المظهر",
            .language: "اللغة",
            .auto: "تلقائي",
            .autoSubtitle: "حسب وقت اليوم",
            .light: "فاتح",
            .lightSubtitle: "مظهر فاتح دائمًا",
            .dark: "داكن",
            .darkSubtitle: "مظهر داكن دائمًا",
            .manageSubscription: "إدارة الاشتراك",
            .signOut: "تسجيل الخروج",
            .signOutConfirmTitle: "تسجيل الخروج؟",
            .helpAndFaq: "المساعدة والأسئلة الشائعة",
            .privacyPolicy: "سياسة الخصوصية",
            .termsOfService: "شروط الخدمة",
            .unlockProTitle: "افتح BeeClean Pro",
            .unlockProSubtitle: "تنظيف غير محدود، كل الفئات",
            .upgrade: "ترقية",
            .deleteAccount: "حذف الحساب",
            .streak: "سلسلة",
            .cleaned: "تم تنظيفه",
            .saved: "تم توفيره",
            .save: "حفظ",
            .cancel: "إلغاء",
            .languageSearchPlaceholder: "بحث عن اللغات",
            .languageEmptyState: "لا توجد لغات تطابق بحثك.",
            .selectLanguage: "اختر اللغة",
            .photos: "الصور",
            .videos: "الفيديوهات",
            .duplicates: "المكررات",
            .similarPhotos: "صور متشابهة",
            .similarScreenshots: "لقطات متشابهة",
            .screenshots: "لقطات الشاشة",
            .blurredPhotos: "صور ضبابية",
            .otherPhotos: "صور أخرى",
            .similarVideos: "فيديوهات متشابهة",
            .screenRecordings: "تسجيلات الشاشة",
            .shortRecordings: "تسجيلات قصيرة",
            .longVideos: "فيديوهات طويلة",
            .allClear: "كل شيء نظيف",
            .compress: "ضغط",
            .noPhotosFound: "لا توجد صور",
            .noPhotosFoundSubtitle: "التقط أو استورد صورة\nلبدء الضغط.",
            .noVideosFound: "لا توجد فيديوهات",
            .noVideosFoundSubtitle: "سجل أو استورد فيديو\nلبدء الضغط.",
            .email: "البريد",
            .backendOffline: "الخادم غير متصل",
            .backendOfflineSubtitle: "ابدأ الخادم:\ncd apps/backend && npm run dev",
            .tryAgain: "حاول مرة أخرى",
            .signInWithGoogle: "سجل الدخول مع Google",
            .chartColors: "ألوان الرسوم",
            .activity: "النشاط",
            .itemsCleaned: "تم تنظيفها",
            .bestDay: "أفضل يوم",
            .deleteDuplicatePhotosFormat: "حذف %1$d صورة مكررة (%2$@)",
            .deleteSimilarPhotosFormat: "حذف %1$d صورة متشابهة (%2$@)",
            .deleteSimilarVideosFormat: "حذف %1$d فيديو متشابه (%2$@)",
            .deleteSimilarScreenshotsFormat: "حذف %1$d لقطة متشابهة (%2$@)",
            .beeName: "اسم النحلة",
            .quickAccess: "وصول سريع",
            .spaceToClean: "مساحة للتنظيف",
            .totalSpaceToClean: "إجمالي المساحة للتنظيف",
            .done: "تم",
            .delete: "حذف",
            .edit: "تعديل",
            .share: "مشاركة",
            .retry: "إعادة المحاولة",
            .apply: "تطبيق",
            .filters: "عوامل التصفية",
            .select: "تحديد",
            .openSettings: "فتح الإعدادات",
            .keep: "احتفاظ",
            .best: "الأفضل",
            .quickCleanup: "تنظيف سريع",
            .allDone: "تم كل شيء!",
            .notNow: "ليس الآن",
            .goPro: "الترقية إلى Pro"
        ],

        // MARK: hi
        .hindi: [
            .settings: "सेटिंग्स",
            .yourName: "आपका नाम",
            .yourNameSubtitle: "आपकी मधुमक्खी के नाम से अलग।",
            .preferences: "प्राथमिकताएँ",
            .account: "खाता",
            .supportAndLegal: "सहायता और कानूनी",
            .notifications: "सूचनाएँ",
            .hapticFeedback: "हैप्टिक प्रतिक्रिया",
            .theme: "थीम",
            .language: "भाषा",
            .auto: "स्वतः",
            .autoSubtitle: "दिन के समय अनुसार",
            .light: "हल्की",
            .lightSubtitle: "हमेशा हल्की थीम",
            .dark: "गहरी",
            .darkSubtitle: "हमेशा गहरी थीम",
            .manageSubscription: "सदस्यता प्रबंधित करें",
            .signOut: "साइन आउट",
            .signOutConfirmTitle: "साइन आउट करें?",
            .helpAndFaq: "सहायता और FAQ",
            .privacyPolicy: "गोपनीयता नीति",
            .termsOfService: "सेवा की शर्तें",
            .unlockProTitle: "BeeClean Pro अनलॉक करें",
            .unlockProSubtitle: "हर श्रेणी में असीमित सफाई",
            .upgrade: "अपग्रेड",
            .deleteAccount: "खाता हटाएँ",
            .streak: "स्ट्रीक",
            .cleaned: "साफ़",
            .saved: "बचाया",
            .save: "सहेजें",
            .cancel: "रद्द करें",
            .languageSearchPlaceholder: "भाषाएँ खोजें",
            .languageEmptyState: "कोई भाषा नहीं मिली।",
            .selectLanguage: "भाषा चुनें",
            .photos: "फ़ोटो",
            .videos: "वीडियो",
            .duplicates: "डुप्लिकेट",
            .similarPhotos: "समान फ़ोटो",
            .similarScreenshots: "समान स्क्रीनशॉट",
            .screenshots: "स्क्रीनशॉट",
            .blurredPhotos: "धुंधली फ़ोटो",
            .otherPhotos: "अन्य फ़ोटो",
            .similarVideos: "समान वीडियो",
            .screenRecordings: "स्क्रीन रिकॉर्डिंग",
            .shortRecordings: "छोटी रिकॉर्डिंग",
            .longVideos: "लंबे वीडियो",
            .allClear: "सब साफ़",
            .compress: "संपीड़ित करें",
            .noPhotosFound: "कोई फ़ोटो नहीं",
            .noPhotosFoundSubtitle: "एक फ़ोटो लें या आयात करें\nसंपीड़न शुरू करने के लिए।",
            .noVideosFound: "कोई वीडियो नहीं",
            .noVideosFoundSubtitle: "एक वीडियो रिकॉर्ड करें या आयात करें\nसंपीड़न शुरू करने के लिए।",
            .email: "ईमेल",
            .backendOffline: "बैकएंड ऑफ़लाइन",
            .backendOfflineSubtitle: "बैकएंड सर्वर शुरू करें:\ncd apps/backend && npm run dev",
            .tryAgain: "पुनः प्रयास करें",
            .signInWithGoogle: "Google से साइन इन करें",
            .chartColors: "चार्ट रंग",
            .activity: "गतिविधि",
            .itemsCleaned: "साफ़ की गईं",
            .bestDay: "सर्वश्रेष्ठ दिन",
            .deleteDuplicatePhotosFormat: "%1$d डुप्लिकेट फोटो हटाएँ (%2$@)",
            .deleteSimilarPhotosFormat: "%1$d समान फोटो हटाएँ (%2$@)",
            .deleteSimilarVideosFormat: "%1$d समान वीडियो हटाएँ (%2$@)",
            .deleteSimilarScreenshotsFormat: "%1$d समान स्क्रीनशॉट हटाएँ (%2$@)",
            .beeName: "मधुमक्खी का नाम",
            .quickAccess: "त्वरित पहुँच",
            .spaceToClean: "साफ़ करने योग्य स्थान",
            .totalSpaceToClean: "कुल साफ़ करने योग्य स्थान",
            .done: "हो गया",
            .delete: "हटाएँ",
            .edit: "संपादित करें",
            .share: "साझा करें",
            .retry: "पुनः प्रयास",
            .apply: "लागू करें",
            .filters: "फ़िल्टर",
            .select: "चुनें",
            .openSettings: "सेटिंग्स खोलें",
            .keep: "रखें",
            .best: "सर्वश्रेष्ठ",
            .quickCleanup: "त्वरित सफ़ाई",
            .allDone: "सब हो गया!",
            .notNow: "अभी नहीं",
            .goPro: "Pro बनें"
        ],

        // MARK: bn
        .bengali: [
            .settings: "সেটিংস",
            .yourName: "আপনার নাম",
            .yourNameSubtitle: "আপনার মৌমাছির নাম থেকে আলাদা।",
            .preferences: "পছন্দসমূহ",
            .account: "অ্যাকাউন্ট",
            .supportAndLegal: "সহায়তা ও আইনি",
            .notifications: "নোটিফিকেশন",
            .hapticFeedback: "হ্যাপটিক প্রতিক্রিয়া",
            .theme: "থিম",
            .language: "ভাষা",
            .auto: "স্বয়ংক্রিয়",
            .autoSubtitle: "দিনের সময় অনুযায়ী",
            .light: "হালকা",
            .lightSubtitle: "সবসময় হালকা থিম",
            .dark: "গাঢ়",
            .darkSubtitle: "সবসময় গাঢ় থিম",
            .manageSubscription: "সাবস্ক্রিপশন পরিচালনা",
            .signOut: "সাইন আউট",
            .signOutConfirmTitle: "সাইন আউট করবেন?",
            .helpAndFaq: "সাহায্য ও FAQ",
            .privacyPolicy: "গোপনীয়তা নীতি",
            .termsOfService: "পরিষেবার শর্তাবলী",
            .unlockProTitle: "BeeClean Pro আনলক করুন",
            .unlockProSubtitle: "সব ক্যাটেগরিতে অসীম পরিষ্কার",
            .upgrade: "আপগ্রেড",
            .deleteAccount: "অ্যাকাউন্ট মুছে ফেলুন",
            .streak: "ধারা",
            .cleaned: "পরিষ্কার",
            .saved: "সংরক্ষিত",
            .save: "সংরক্ষণ",
            .cancel: "বাতিল",
            .languageSearchPlaceholder: "ভাষা অনুসন্ধান",
            .languageEmptyState: "কোনো ভাষা পাওয়া যায়নি।",
            .selectLanguage: "ভাষা নির্বাচন",
            .deleteDuplicatePhotosFormat: "%1$d ডুপ্লিকেট ফটো মুছুন (%2$@)",
            .deleteSimilarPhotosFormat: "%1$d সমান ফটো মুছুন (%2$@)",
            .deleteSimilarVideosFormat: "%1$d সমান ভিডিও মুছুন (%2$@)",
            .deleteSimilarScreenshotsFormat: "%1$d সমান স্ক্রিনশট মুছুন (%2$@)"
        ],

        // MARK: ur
        .urdu: [
            .settings: "ترتیبات",
            .yourName: "آپ کا نام",
            .yourNameSubtitle: "آپ کی شہد کی مکھی کے نام سے الگ۔",
            .preferences: "ترجیحات",
            .account: "اکاؤنٹ",
            .supportAndLegal: "مدد اور قانونی",
            .notifications: "اطلاعات",
            .hapticFeedback: "ہیپٹک فیڈ بیک",
            .theme: "تھیم",
            .language: "زبان",
            .auto: "خودکار",
            .autoSubtitle: "وقت کے مطابق",
            .light: "ہلکی",
            .lightSubtitle: "ہمیشہ ہلکی تھیم",
            .dark: "گہری",
            .darkSubtitle: "ہمیشہ گہری تھیم",
            .manageSubscription: "سبسکرپشن کا انتظام",
            .signOut: "سائن آؤٹ",
            .signOutConfirmTitle: "سائن آؤٹ کریں؟",
            .helpAndFaq: "مدد اور سوالات",
            .privacyPolicy: "رازداری کی پالیسی",
            .termsOfService: "خدمت کی شرائط",
            .unlockProTitle: "BeeClean Pro کھولیں",
            .unlockProSubtitle: "ہر زمرے میں لامحدود صفائی",
            .upgrade: "اپ گریڈ",
            .deleteAccount: "اکاؤنٹ حذف کریں",
            .streak: "تسلسل",
            .cleaned: "صاف کیا",
            .saved: "بچایا",
            .save: "محفوظ کریں",
            .cancel: "منسوخ",
            .languageSearchPlaceholder: "زبانیں تلاش کریں",
            .languageEmptyState: "کوئی زبان نہیں ملی۔",
            .selectLanguage: "زبان منتخب کریں",
            .deleteDuplicatePhotosFormat: "%1$d ڈپلیکیٹ تصاویر حذف کریں (%2$@)",
            .deleteSimilarPhotosFormat: "%1$d مشابہ تصاویر حذف کریں (%2$@)",
            .deleteSimilarVideosFormat: "%1$d مشابہ ویڈیوز حذف کریں (%2$@)",
            .deleteSimilarScreenshotsFormat: "%1$d مشابہ اسکرین شاٹس حذف کریں (%2$@)"
        ],

        // MARK: nl
        .dutch: [
            .settings: "Instellingen",
            .yourName: "Jouw naam",
            .yourNameSubtitle: "Los van de naam van je bij.",
            .preferences: "Voorkeuren",
            .account: "Account",
            .supportAndLegal: "Ondersteuning & juridisch",
            .notifications: "Meldingen",
            .hapticFeedback: "Haptische feedback",
            .theme: "Thema",
            .language: "Taal",
            .auto: "Automatisch",
            .autoSubtitle: "Volgt het tijdstip",
            .light: "Licht",
            .lightSubtitle: "Altijd licht thema",
            .dark: "Donker",
            .darkSubtitle: "Altijd donker thema",
            .manageSubscription: "Abonnement beheren",
            .signOut: "Uitloggen",
            .signOutConfirmTitle: "Uitloggen?",
            .helpAndFaq: "Help & FAQ",
            .privacyPolicy: "Privacybeleid",
            .termsOfService: "Servicevoorwaarden",
            .unlockProTitle: "Ontgrendel BeeClean Pro",
            .unlockProSubtitle: "Onbeperkt opruimen in elke categorie",
            .upgrade: "Upgrade",
            .deleteAccount: "Account verwijderen",
            .streak: "REEKS",
            .cleaned: "OPGERUIMD",
            .saved: "BESPAARD",
            .save: "Opslaan",
            .cancel: "Annuleer",
            .languageSearchPlaceholder: "Talen zoeken",
            .languageEmptyState: "Geen talen gevonden.",
            .selectLanguage: "Selecteer taal",
            .deleteDuplicatePhotosFormat: "%1$d dubbele foto's verwijderen (%2$@)",
            .deleteSimilarPhotosFormat: "%1$d soortgelijke foto's verwijderen (%2$@)",
            .deleteSimilarVideosFormat: "%1$d soortgelijke video's verwijderen (%2$@)",
            .deleteSimilarScreenshotsFormat: "%1$d soortgelijke screenshots verwijderen (%2$@)"
        ],

        // MARK: pl
        .polish: [
            .settings: "Ustawienia",
            .yourName: "Twoje imię",
            .yourNameSubtitle: "Oddzielnie od imienia twojej pszczoły.",
            .preferences: "Preferencje",
            .account: "Konto",
            .supportAndLegal: "Pomoc i informacje prawne",
            .notifications: "Powiadomienia",
            .hapticFeedback: "Wibracje",
            .theme: "Motyw",
            .language: "Język",
            .auto: "Auto",
            .autoSubtitle: "Zależnie od pory dnia",
            .light: "Jasny",
            .lightSubtitle: "Zawsze jasny motyw",
            .dark: "Ciemny",
            .darkSubtitle: "Zawsze ciemny motyw",
            .manageSubscription: "Zarządzaj subskrypcją",
            .signOut: "Wyloguj się",
            .signOutConfirmTitle: "Wylogować?",
            .helpAndFaq: "Pomoc i FAQ",
            .privacyPolicy: "Polityka prywatności",
            .termsOfService: "Warunki korzystania",
            .unlockProTitle: "Odblokuj BeeClean Pro",
            .unlockProSubtitle: "Nielimitowane czyszczenie w każdej kategorii",
            .upgrade: "Ulepsz",
            .deleteAccount: "Usuń konto",
            .streak: "PASMO",
            .cleaned: "WYCZYSZCZONE",
            .saved: "ZAOSZCZĘDZONE",
            .save: "Zapisz",
            .cancel: "Anuluj",
            .languageSearchPlaceholder: "Szukaj języków",
            .languageEmptyState: "Brak pasujących języków.",
            .selectLanguage: "Wybierz język",
            .deleteDuplicatePhotosFormat: "Usuń %1$d zduplikowanych zdjęć (%2$@)",
            .deleteSimilarPhotosFormat: "Usuń %1$d podobnych zdjęć (%2$@)",
            .deleteSimilarVideosFormat: "Usuń %1$d podobnych filmów (%2$@)",
            .deleteSimilarScreenshotsFormat: "Usuń %1$d podobnych zrzutów (%2$@)"
        ],

        // MARK: tr
        .turkish: [
            .settings: "Ayarlar",
            .yourName: "Adınız",
            .yourNameSubtitle: "Arınızın adından bağımsız.",
            .preferences: "Tercihler",
            .account: "Hesap",
            .supportAndLegal: "Destek ve yasal",
            .notifications: "Bildirimler",
            .hapticFeedback: "Dokunsal geri bildirim",
            .theme: "Tema",
            .language: "Dil",
            .auto: "Otomatik",
            .autoSubtitle: "Saate göre",
            .light: "Açık",
            .lightSubtitle: "Her zaman açık tema",
            .dark: "Koyu",
            .darkSubtitle: "Her zaman koyu tema",
            .manageSubscription: "Aboneliği yönet",
            .signOut: "Çıkış yap",
            .signOutConfirmTitle: "Çıkış yapılsın mı?",
            .helpAndFaq: "Yardım ve SSS",
            .privacyPolicy: "Gizlilik politikası",
            .termsOfService: "Hizmet şartları",
            .unlockProTitle: "BeeClean Pro'yu aç",
            .unlockProSubtitle: "Her kategoride sınırsız temizlik",
            .upgrade: "Yükselt",
            .deleteAccount: "Hesabı sil",
            .streak: "SERİ",
            .cleaned: "TEMİZLENDİ",
            .saved: "BİRİKTİRİLDİ",
            .save: "Kaydet",
            .cancel: "İptal",
            .languageSearchPlaceholder: "Dil ara",
            .languageEmptyState: "Eşleşen dil yok.",
            .selectLanguage: "Dil seç",
            .deleteDuplicatePhotosFormat: "%1$d yinelenen fotoğrafı sil (%2$@)",
            .deleteSimilarPhotosFormat: "%1$d benzer fotoğrafı sil (%2$@)",
            .deleteSimilarVideosFormat: "%1$d benzer videoyu sil (%2$@)",
            .deleteSimilarScreenshotsFormat: "%1$d benzer ekran görüntüsünü sil (%2$@)"
        ],

        // MARK: sv
        .swedish: [
            .settings: "Inställningar",
            .yourName: "Ditt namn",
            .yourNameSubtitle: "Skiljt från ditt bis namn.",
            .preferences: "Inställningar",
            .account: "Konto",
            .supportAndLegal: "Support och juridik",
            .notifications: "Aviseringar",
            .hapticFeedback: "Haptisk feedback",
            .theme: "Tema",
            .language: "Språk",
            .auto: "Auto",
            .autoSubtitle: "Följer tid på dygnet",
            .light: "Ljust",
            .lightSubtitle: "Alltid ljust tema",
            .dark: "Mörkt",
            .darkSubtitle: "Alltid mörkt tema",
            .manageSubscription: "Hantera prenumeration",
            .signOut: "Logga ut",
            .signOutConfirmTitle: "Logga ut?",
            .helpAndFaq: "Hjälp och FAQ",
            .privacyPolicy: "Integritetspolicy",
            .termsOfService: "Användarvillkor",
            .unlockProTitle: "Lås upp BeeClean Pro",
            .unlockProSubtitle: "Obegränsad städning, alla kategorier",
            .upgrade: "Uppgradera",
            .deleteAccount: "Radera konto",
            .streak: "SVIT",
            .cleaned: "RENSAT",
            .saved: "SPARAT",
            .save: "Spara",
            .cancel: "Avbryt",
            .languageSearchPlaceholder: "Sök språk",
            .languageEmptyState: "Inga språk matchar.",
            .selectLanguage: "Välj språk",
            .deleteDuplicatePhotosFormat: "Radera %1$d duplicerade foton (%2$@)",
            .deleteSimilarPhotosFormat: "Radera %1$d liknande foton (%2$@)",
            .deleteSimilarVideosFormat: "Radera %1$d liknande videor (%2$@)",
            .deleteSimilarScreenshotsFormat: "Radera %1$d liknande skärmdumpar (%2$@)"
        ],

        // MARK: nb
        .norwegian: [
            .settings: "Innstillinger",
            .yourName: "Navnet ditt",
            .yourNameSubtitle: "Atskilt fra navnet på bien din.",
            .preferences: "Preferanser",
            .account: "Konto",
            .supportAndLegal: "Støtte og juridisk",
            .notifications: "Varslinger",
            .hapticFeedback: "Haptisk tilbakemelding",
            .theme: "Tema",
            .language: "Språk",
            .auto: "Auto",
            .autoSubtitle: "Følger tid på døgnet",
            .light: "Lyst",
            .lightSubtitle: "Alltid lyst tema",
            .dark: "Mørkt",
            .darkSubtitle: "Alltid mørkt tema",
            .manageSubscription: "Administrer abonnement",
            .signOut: "Logg ut",
            .signOutConfirmTitle: "Logg ut?",
            .helpAndFaq: "Hjelp og FAQ",
            .privacyPolicy: "Personvern",
            .termsOfService: "Tjenestevilkår",
            .unlockProTitle: "Lås opp BeeClean Pro",
            .unlockProSubtitle: "Ubegrenset opprydding, alle kategorier",
            .upgrade: "Oppgrader",
            .deleteAccount: "Slett konto",
            .streak: "REKKE",
            .cleaned: "RYDDET",
            .saved: "SPART",
            .save: "Lagre",
            .cancel: "Avbryt",
            .languageSearchPlaceholder: "Søk språk",
            .languageEmptyState: "Ingen språk passer.",
            .selectLanguage: "Velg språk",
            .deleteDuplicatePhotosFormat: "Slett %1$d duplikatbilder (%2$@)",
            .deleteSimilarPhotosFormat: "Slett %1$d lignende bilder (%2$@)",
            .deleteSimilarVideosFormat: "Slett %1$d lignende videoer (%2$@)",
            .deleteSimilarScreenshotsFormat: "Slett %1$d lignende skjermbilder (%2$@)"
        ],

        // MARK: da
        .danish: [
            .settings: "Indstillinger",
            .yourName: "Dit navn",
            .yourNameSubtitle: "Adskilt fra navnet på din bi.",
            .preferences: "Præferencer",
            .account: "Konto",
            .supportAndLegal: "Support og juridisk",
            .notifications: "Notifikationer",
            .hapticFeedback: "Haptisk feedback",
            .theme: "Tema",
            .language: "Sprog",
            .auto: "Auto",
            .autoSubtitle: "Følger tiden på dagen",
            .light: "Lyst",
            .lightSubtitle: "Altid lyst tema",
            .dark: "Mørkt",
            .darkSubtitle: "Altid mørkt tema",
            .manageSubscription: "Administrer abonnement",
            .signOut: "Log ud",
            .signOutConfirmTitle: "Log ud?",
            .helpAndFaq: "Hjælp og FAQ",
            .privacyPolicy: "Privatlivspolitik",
            .termsOfService: "Servicevilkår",
            .unlockProTitle: "Lås BeeClean Pro op",
            .unlockProSubtitle: "Ubegrænset oprydning, alle kategorier",
            .upgrade: "Opgrader",
            .deleteAccount: "Slet konto",
            .streak: "STIME",
            .cleaned: "RYDDET",
            .saved: "SPARET",
            .save: "Gem",
            .cancel: "Annuller",
            .languageSearchPlaceholder: "Søg sprog",
            .languageEmptyState: "Ingen sprog matcher.",
            .selectLanguage: "Vælg sprog",
            .deleteDuplicatePhotosFormat: "Slet %1$d duplikatbilleder (%2$@)",
            .deleteSimilarPhotosFormat: "Slet %1$d lignende billeder (%2$@)",
            .deleteSimilarVideosFormat: "Slet %1$d lignende videoer (%2$@)",
            .deleteSimilarScreenshotsFormat: "Slet %1$d lignende skærmbilleder (%2$@)"
        ],

        // MARK: fi
        .finnish: [
            .settings: "Asetukset",
            .yourName: "Nimesi",
            .yourNameSubtitle: "Erillinen mehiläisesi nimestä.",
            .preferences: "Mieltymykset",
            .account: "Tili",
            .supportAndLegal: "Tuki ja lakiasiat",
            .notifications: "Ilmoitukset",
            .hapticFeedback: "Tuntopalaute",
            .theme: "Teema",
            .language: "Kieli",
            .auto: "Automaattinen",
            .autoSubtitle: "Vuorokaudenajan mukaan",
            .light: "Vaalea",
            .lightSubtitle: "Aina vaalea teema",
            .dark: "Tumma",
            .darkSubtitle: "Aina tumma teema",
            .manageSubscription: "Hallitse tilausta",
            .signOut: "Kirjaudu ulos",
            .signOutConfirmTitle: "Kirjaudu ulos?",
            .helpAndFaq: "Ohjeet ja UKK",
            .privacyPolicy: "Tietosuojakäytäntö",
            .termsOfService: "Käyttöehdot",
            .unlockProTitle: "Avaa BeeClean Pro",
            .unlockProSubtitle: "Rajaton siivous, kaikki kategoriat",
            .upgrade: "Päivitä",
            .deleteAccount: "Poista tili",
            .streak: "PUTKI",
            .cleaned: "SIIVOTTU",
            .saved: "SÄÄSTETTY",
            .save: "Tallenna",
            .cancel: "Peruuta",
            .languageSearchPlaceholder: "Etsi kieliä",
            .languageEmptyState: "Yhtään kieltä ei löytynyt.",
            .selectLanguage: "Valitse kieli",
            .deleteDuplicatePhotosFormat: "Poista %1$d kaksoiskuvaa (%2$@)",
            .deleteSimilarPhotosFormat: "Poista %1$d samankaltaista kuvaa (%2$@)",
            .deleteSimilarVideosFormat: "Poista %1$d samankaltaista videota (%2$@)",
            .deleteSimilarScreenshotsFormat: "Poista %1$d samankaltaista kuvakaappausta (%2$@)"
        ],

        // MARK: el
        .greek: [
            .settings: "Ρυθμίσεις",
            .yourName: "Το όνομά σου",
            .yourNameSubtitle: "Ξεχωριστό από το όνομα της μέλισσάς σου.",
            .preferences: "Προτιμήσεις",
            .account: "Λογαριασμός",
            .supportAndLegal: "Υποστήριξη & νομικά",
            .notifications: "Ειδοποιήσεις",
            .hapticFeedback: "Απτική ανάδραση",
            .theme: "Θέμα",
            .language: "Γλώσσα",
            .auto: "Αυτόματο",
            .autoSubtitle: "Ακολουθεί την ώρα",
            .light: "Ανοιχτό",
            .lightSubtitle: "Πάντα ανοιχτό θέμα",
            .dark: "Σκοτεινό",
            .darkSubtitle: "Πάντα σκοτεινό θέμα",
            .manageSubscription: "Διαχείριση συνδρομής",
            .signOut: "Αποσύνδεση",
            .signOutConfirmTitle: "Αποσύνδεση;",
            .helpAndFaq: "Βοήθεια & FAQ",
            .privacyPolicy: "Πολιτική απορρήτου",
            .termsOfService: "Όροι χρήσης",
            .unlockProTitle: "Ξεκλείδωσε το BeeClean Pro",
            .unlockProSubtitle: "Απεριόριστα καθαρίσματα σε όλες τις κατηγορίες",
            .upgrade: "Αναβάθμιση",
            .deleteAccount: "Διαγραφή λογαριασμού",
            .streak: "ΣΕΡΙ",
            .cleaned: "ΚΑΘΑΡΙΣΘΗΚΕ",
            .saved: "ΕΞΟΙΚΟΝΟΜΗΘΗΚΕ",
            .save: "Αποθήκευση",
            .cancel: "Ακύρωση",
            .languageSearchPlaceholder: "Αναζήτηση γλωσσών",
            .languageEmptyState: "Καμία γλώσσα δεν ταιριάζει.",
            .selectLanguage: "Επιλογή γλώσσας",
            .deleteDuplicatePhotosFormat: "Διαγραφή %1$d διπλότυπων φωτογραφιών (%2$@)",
            .deleteSimilarPhotosFormat: "Διαγραφή %1$d παρόμοιων φωτογραφιών (%2$@)",
            .deleteSimilarVideosFormat: "Διαγραφή %1$d παρόμοιων βίντεο (%2$@)",
            .deleteSimilarScreenshotsFormat: "Διαγραφή %1$d παρόμοιων στιγμιότυπων (%2$@)"
        ],

        // MARK: cs
        .czech: [
            .settings: "Nastavení",
            .yourName: "Tvé jméno",
            .yourNameSubtitle: "Odděleně od jména tvé včely.",
            .preferences: "Předvolby",
            .account: "Účet",
            .supportAndLegal: "Podpora a právní",
            .notifications: "Oznámení",
            .hapticFeedback: "Haptická odezva",
            .theme: "Motiv",
            .language: "Jazyk",
            .auto: "Auto",
            .autoSubtitle: "Podle denní doby",
            .light: "Světlý",
            .lightSubtitle: "Vždy světlý motiv",
            .dark: "Tmavý",
            .darkSubtitle: "Vždy tmavý motiv",
            .manageSubscription: "Spravovat předplatné",
            .signOut: "Odhlásit",
            .signOutConfirmTitle: "Odhlásit?",
            .helpAndFaq: "Pomoc a FAQ",
            .privacyPolicy: "Zásady ochrany osobních údajů",
            .termsOfService: "Podmínky služby",
            .unlockProTitle: "Odemkněte BeeClean Pro",
            .unlockProSubtitle: "Neomezené úklidy, všechny kategorie",
            .upgrade: "Upgradovat",
            .deleteAccount: "Smazat účet",
            .streak: "SÉRIE",
            .cleaned: "UKLIZENO",
            .saved: "UŠETŘENO",
            .save: "Uložit",
            .cancel: "Zrušit",
            .languageSearchPlaceholder: "Hledat jazyky",
            .languageEmptyState: "Žádný jazyk neodpovídá.",
            .selectLanguage: "Vyberte jazyk",
            .deleteDuplicatePhotosFormat: "Smazat %1$d duplicitních fotek (%2$@)",
            .deleteSimilarPhotosFormat: "Smazat %1$d podobných fotek (%2$@)",
            .deleteSimilarVideosFormat: "Smazat %1$d podobných videí (%2$@)",
            .deleteSimilarScreenshotsFormat: "Smazat %1$d podobných screenshotů (%2$@)"
        ],

        // MARK: uk
        .ukrainian: [
            .settings: "Налаштування",
            .yourName: "Ваше ім'я",
            .yourNameSubtitle: "Окремо від імені вашої бджоли.",
            .preferences: "Налаштування",
            .account: "Обліковий запис",
            .supportAndLegal: "Підтримка та правова інформація",
            .notifications: "Сповіщення",
            .hapticFeedback: "Тактильний відгук",
            .theme: "Тема",
            .language: "Мова",
            .auto: "Авто",
            .autoSubtitle: "За часом доби",
            .light: "Світла",
            .lightSubtitle: "Завжди світла",
            .dark: "Темна",
            .darkSubtitle: "Завжди темна",
            .manageSubscription: "Керувати підпискою",
            .signOut: "Вийти",
            .signOutConfirmTitle: "Вийти?",
            .helpAndFaq: "Допомога й FAQ",
            .privacyPolicy: "Політика конфіденційності",
            .termsOfService: "Умови використання",
            .unlockProTitle: "Розблокуйте BeeClean Pro",
            .unlockProSubtitle: "Безлімітне очищення, усі категорії",
            .upgrade: "Оновити",
            .deleteAccount: "Видалити обліковий запис",
            .streak: "СЕРІЯ",
            .cleaned: "ОЧИЩЕНО",
            .saved: "ЗАОЩАДЖЕНО",
            .save: "Зберегти",
            .cancel: "Скасувати",
            .languageSearchPlaceholder: "Пошук мов",
            .languageEmptyState: "Мови не знайдено.",
            .selectLanguage: "Виберіть мову",
            .deleteDuplicatePhotosFormat: "Видалити %1$d дублікатів фото (%2$@)",
            .deleteSimilarPhotosFormat: "Видалити %1$d схожих фото (%2$@)",
            .deleteSimilarVideosFormat: "Видалити %1$d схожих відео (%2$@)",
            .deleteSimilarScreenshotsFormat: "Видалити %1$d схожих скріншотів (%2$@)"
        ],

        // MARK: id
        .indonesian: [
            .settings: "Pengaturan",
            .yourName: "Nama Anda",
            .yourNameSubtitle: "Terpisah dari nama lebah Anda.",
            .preferences: "Preferensi",
            .account: "Akun",
            .supportAndLegal: "Bantuan & hukum",
            .notifications: "Notifikasi",
            .hapticFeedback: "Umpan balik haptik",
            .theme: "Tema",
            .language: "Bahasa",
            .auto: "Otomatis",
            .autoSubtitle: "Mengikuti waktu",
            .light: "Terang",
            .lightSubtitle: "Selalu tema terang",
            .dark: "Gelap",
            .darkSubtitle: "Selalu tema gelap",
            .manageSubscription: "Kelola langganan",
            .signOut: "Keluar",
            .signOutConfirmTitle: "Keluar?",
            .helpAndFaq: "Bantuan & FAQ",
            .privacyPolicy: "Kebijakan privasi",
            .termsOfService: "Ketentuan layanan",
            .unlockProTitle: "Buka BeeClean Pro",
            .unlockProSubtitle: "Pembersihan tanpa batas, semua kategori",
            .upgrade: "Tingkatkan",
            .deleteAccount: "Hapus akun",
            .streak: "STREAK",
            .cleaned: "DIBERSIHKAN",
            .saved: "DIHEMAT",
            .save: "Simpan",
            .cancel: "Batal",
            .languageSearchPlaceholder: "Cari bahasa",
            .languageEmptyState: "Tidak ada bahasa yang cocok.",
            .selectLanguage: "Pilih bahasa",
            .deleteDuplicatePhotosFormat: "Hapus %1$d foto duplikat (%2$@)",
            .deleteSimilarPhotosFormat: "Hapus %1$d foto serupa (%2$@)",
            .deleteSimilarVideosFormat: "Hapus %1$d video serupa (%2$@)",
            .deleteSimilarScreenshotsFormat: "Hapus %1$d tangkapan layar serupa (%2$@)"
        ],

        // MARK: ms
        .malay: [
            .settings: "Tetapan",
            .yourName: "Nama anda",
            .yourNameSubtitle: "Berasingan dari nama lebah anda.",
            .preferences: "Keutamaan",
            .account: "Akaun",
            .supportAndLegal: "Sokongan & undang-undang",
            .notifications: "Pemberitahuan",
            .hapticFeedback: "Maklum balas haptik",
            .theme: "Tema",
            .language: "Bahasa",
            .auto: "Auto",
            .autoSubtitle: "Mengikut waktu",
            .light: "Cerah",
            .lightSubtitle: "Sentiasa tema cerah",
            .dark: "Gelap",
            .darkSubtitle: "Sentiasa tema gelap",
            .manageSubscription: "Urus langganan",
            .signOut: "Log keluar",
            .signOutConfirmTitle: "Log keluar?",
            .helpAndFaq: "Bantuan & FAQ",
            .privacyPolicy: "Dasar privasi",
            .termsOfService: "Terma perkhidmatan",
            .unlockProTitle: "Buka BeeClean Pro",
            .unlockProSubtitle: "Pembersihan tanpa had, semua kategori",
            .upgrade: "Naik taraf",
            .deleteAccount: "Padam akaun",
            .streak: "STREAK",
            .cleaned: "DIBERSIHKAN",
            .saved: "DIJIMATKAN",
            .save: "Simpan",
            .cancel: "Batal",
            .languageSearchPlaceholder: "Cari bahasa",
            .languageEmptyState: "Tiada bahasa sepadan.",
            .selectLanguage: "Pilih bahasa",
            .deleteDuplicatePhotosFormat: "Padam %1$d foto pendua (%2$@)",
            .deleteSimilarPhotosFormat: "Padam %1$d foto serupa (%2$@)",
            .deleteSimilarVideosFormat: "Padam %1$d video serupa (%2$@)",
            .deleteSimilarScreenshotsFormat: "Padam %1$d tangkapan skrin serupa (%2$@)"
        ],

        // MARK: vi
        .vietnamese: [
            .settings: "Cài đặt",
            .yourName: "Tên của bạn",
            .yourNameSubtitle: "Tách biệt với tên ong của bạn.",
            .preferences: "Tuỳ chọn",
            .account: "Tài khoản",
            .supportAndLegal: "Hỗ trợ & pháp lý",
            .notifications: "Thông báo",
            .hapticFeedback: "Phản hồi xúc giác",
            .theme: "Giao diện",
            .language: "Ngôn ngữ",
            .auto: "Tự động",
            .autoSubtitle: "Theo thời gian trong ngày",
            .light: "Sáng",
            .lightSubtitle: "Luôn sáng",
            .dark: "Tối",
            .darkSubtitle: "Luôn tối",
            .manageSubscription: "Quản lý đăng ký",
            .signOut: "Đăng xuất",
            .signOutConfirmTitle: "Đăng xuất?",
            .helpAndFaq: "Trợ giúp & FAQ",
            .privacyPolicy: "Chính sách bảo mật",
            .termsOfService: "Điều khoản dịch vụ",
            .unlockProTitle: "Mở khoá BeeClean Pro",
            .unlockProSubtitle: "Dọn dẹp không giới hạn, mọi danh mục",
            .upgrade: "Nâng cấp",
            .deleteAccount: "Xoá tài khoản",
            .streak: "CHUỖI",
            .cleaned: "ĐÃ DỌN",
            .saved: "ĐÃ TIẾT KIỆM",
            .save: "Lưu",
            .cancel: "Huỷ",
            .languageSearchPlaceholder: "Tìm ngôn ngữ",
            .languageEmptyState: "Không có ngôn ngữ phù hợp.",
            .selectLanguage: "Chọn ngôn ngữ",
            .deleteDuplicatePhotosFormat: "Xoá %1$d ảnh trùng lặp (%2$@)",
            .deleteSimilarPhotosFormat: "Xoá %1$d ảnh tương tự (%2$@)",
            .deleteSimilarVideosFormat: "Xoá %1$d video tương tự (%2$@)",
            .deleteSimilarScreenshotsFormat: "Xoá %1$d ảnh chụp màn hình tương tự (%2$@)"
        ],

        // MARK: th
        .thai: [
            .settings: "การตั้งค่า",
            .yourName: "ชื่อของคุณ",
            .yourNameSubtitle: "แยกจากชื่อผึ้งของคุณ",
            .preferences: "การกำหนดลักษณะ",
            .account: "บัญชี",
            .supportAndLegal: "ช่วยเหลือและกฎหมาย",
            .notifications: "การแจ้งเตือน",
            .hapticFeedback: "การตอบสนองทางสัมผัส",
            .theme: "ธีม",
            .language: "ภาษา",
            .auto: "อัตโนมัติ",
            .autoSubtitle: "ตามช่วงเวลาของวัน",
            .light: "สว่าง",
            .lightSubtitle: "ธีมสว่างเสมอ",
            .dark: "มืด",
            .darkSubtitle: "ธีมมืดเสมอ",
            .manageSubscription: "จัดการการสมัครสมาชิก",
            .signOut: "ออกจากระบบ",
            .signOutConfirmTitle: "ออกจากระบบ?",
            .helpAndFaq: "ช่วยเหลือและคำถาม",
            .privacyPolicy: "นโยบายความเป็นส่วนตัว",
            .termsOfService: "ข้อกำหนดในการให้บริการ",
            .unlockProTitle: "ปลดล็อก BeeClean Pro",
            .unlockProSubtitle: "การล้างไม่จำกัดทุกหมวด",
            .upgrade: "อัปเกรด",
            .deleteAccount: "ลบบัญชี",
            .streak: "สตรีค",
            .cleaned: "ทำความสะอาดแล้ว",
            .saved: "ประหยัด",
            .save: "บันทึก",
            .cancel: "ยกเลิก",
            .languageSearchPlaceholder: "ค้นหาภาษา",
            .languageEmptyState: "ไม่พบภาษาที่ตรงกัน",
            .selectLanguage: "เลือกภาษา",
            .deleteDuplicatePhotosFormat: "ลบรูปซ้ำ %1$d รูป (%2$@)",
            .deleteSimilarPhotosFormat: "ลบรูปคล้ายกัน %1$d รูป (%2$@)",
            .deleteSimilarVideosFormat: "ลบวิดีโอคล้ายกัน %1$d รายการ (%2$@)",
            .deleteSimilarScreenshotsFormat: "ลบภาพหน้าจอคล้ายกัน %1$d ภาพ (%2$@)"
        ],

        // MARK: he
        .hebrew: [
            .settings: "הגדרות",
            .yourName: "השם שלך",
            .yourNameSubtitle: "נפרד משם הדבורה שלך.",
            .preferences: "העדפות",
            .account: "חשבון",
            .supportAndLegal: "תמיכה ומשפטי",
            .notifications: "התראות",
            .hapticFeedback: "משוב מישוש",
            .theme: "ערכת נושא",
            .language: "שפה",
            .auto: "אוטומטי",
            .autoSubtitle: "לפי השעה ביום",
            .light: "בהיר",
            .lightSubtitle: "תמיד ערכה בהירה",
            .dark: "כהה",
            .darkSubtitle: "תמיד ערכה כהה",
            .manageSubscription: "ניהול מנוי",
            .signOut: "התנתקות",
            .signOutConfirmTitle: "להתנתק?",
            .helpAndFaq: "עזרה ושאלות",
            .privacyPolicy: "מדיניות פרטיות",
            .termsOfService: "תנאי שירות",
            .unlockProTitle: "פתח את BeeClean Pro",
            .unlockProSubtitle: "ניקיון ללא הגבלה בכל הקטגוריות",
            .upgrade: "שדרוג",
            .deleteAccount: "מחיקת חשבון",
            .streak: "רצף",
            .cleaned: "נוקה",
            .saved: "נחסך",
            .save: "שמור",
            .cancel: "ביטול",
            .languageSearchPlaceholder: "חיפוש שפות",
            .languageEmptyState: "לא נמצאה שפה תואמת.",
            .selectLanguage: "בחר שפה",
            .deleteDuplicatePhotosFormat: "מחק %1$d תמונות כפולות (%2$@)",
            .deleteSimilarPhotosFormat: "מחק %1$d תמונות דומות (%2$@)",
            .deleteSimilarVideosFormat: "מחק %1$d סרטונים דומים (%2$@)",
            .deleteSimilarScreenshotsFormat: "מחק %1$d צילומי מסך דומים (%2$@)"
        ],

        // MARK: ro
        .romanian: [
            .settings: "Setări",
            .yourName: "Numele tău",
            .yourNameSubtitle: "Diferit de numele albinei tale.",
            .preferences: "Preferințe",
            .account: "Cont",
            .supportAndLegal: "Suport și juridic",
            .notifications: "Notificări",
            .hapticFeedback: "Răspuns tactil",
            .theme: "Temă",
            .language: "Limbă",
            .auto: "Automat",
            .autoSubtitle: "După ora zilei",
            .light: "Luminos",
            .lightSubtitle: "Mereu tema luminoasă",
            .dark: "Întunecat",
            .darkSubtitle: "Mereu tema întunecată",
            .manageSubscription: "Gestionează abonamentul",
            .signOut: "Deconectare",
            .signOutConfirmTitle: "Deconectare?",
            .helpAndFaq: "Ajutor și FAQ",
            .privacyPolicy: "Politica de confidențialitate",
            .termsOfService: "Termenii serviciului",
            .unlockProTitle: "Deblochează BeeClean Pro",
            .unlockProSubtitle: "Curățări nelimitate, toate categoriile",
            .upgrade: "Upgrade",
            .deleteAccount: "Șterge contul",
            .streak: "SERIE",
            .cleaned: "CURĂȚAT",
            .saved: "ECONOMISIT",
            .save: "Salvează",
            .cancel: "Anulează",
            .languageSearchPlaceholder: "Caută limbi",
            .languageEmptyState: "Nicio limbă nu se potrivește.",
            .selectLanguage: "Alege limba",
            .deleteDuplicatePhotosFormat: "Șterge %1$d fotografii duplicate (%2$@)",
            .deleteSimilarPhotosFormat: "Șterge %1$d fotografii similare (%2$@)",
            .deleteSimilarVideosFormat: "Șterge %1$d videoclipuri similare (%2$@)",
            .deleteSimilarScreenshotsFormat: "Șterge %1$d capturi de ecran similare (%2$@)"
        ],

        // MARK: hu
        .hungarian: [
            .settings: "Beállítások",
            .yourName: "A neved",
            .yourNameSubtitle: "Külön a méhed nevétől.",
            .preferences: "Beállítások",
            .account: "Fiók",
            .supportAndLegal: "Támogatás és jogi",
            .notifications: "Értesítések",
            .hapticFeedback: "Tapintható visszajelzés",
            .theme: "Téma",
            .language: "Nyelv",
            .auto: "Automatikus",
            .autoSubtitle: "Napszak szerint",
            .light: "Világos",
            .lightSubtitle: "Mindig világos téma",
            .dark: "Sötét",
            .darkSubtitle: "Mindig sötét téma",
            .manageSubscription: "Előfizetés kezelése",
            .signOut: "Kijelentkezés",
            .signOutConfirmTitle: "Kijelentkezés?",
            .helpAndFaq: "Súgó és GYIK",
            .privacyPolicy: "Adatvédelmi nyilatkozat",
            .termsOfService: "Szolgáltatási feltételek",
            .unlockProTitle: "BeeClean Pro feloldása",
            .unlockProSubtitle: "Korlátlan takarítás minden kategóriában",
            .upgrade: "Frissítés",
            .deleteAccount: "Fiók törlése",
            .streak: "SOROZAT",
            .cleaned: "MEGTISZTÍTVA",
            .saved: "MEGSPÓROLVA",
            .save: "Mentés",
            .cancel: "Mégse",
            .languageSearchPlaceholder: "Nyelvek keresése",
            .languageEmptyState: "Nincs találat.",
            .selectLanguage: "Válassz nyelvet",
            .deleteDuplicatePhotosFormat: "%1$d duplikált fotó törlése (%2$@)",
            .deleteSimilarPhotosFormat: "%1$d hasonló fotó törlése (%2$@)",
            .deleteSimilarVideosFormat: "%1$d hasonló videó törlése (%2$@)",
            .deleteSimilarScreenshotsFormat: "%1$d hasonló képernyőkép törlése (%2$@)"
        ],

        // MARK: fil
        .filipino: [
            .settings: "Mga Setting",
            .yourName: "Iyong pangalan",
            .yourNameSubtitle: "Hiwalay sa pangalan ng iyong bubuyog.",
            .preferences: "Mga Kagustuhan",
            .account: "Account",
            .supportAndLegal: "Suporta at legal",
            .notifications: "Mga Abiso",
            .hapticFeedback: "Haptic feedback",
            .theme: "Tema",
            .language: "Wika",
            .auto: "Awtomatiko",
            .autoSubtitle: "Sumusunod sa oras",
            .light: "Maliwanag",
            .lightSubtitle: "Palaging maliwanag",
            .dark: "Madilim",
            .darkSubtitle: "Palaging madilim",
            .manageSubscription: "Pamahalaan ang subscription",
            .signOut: "Mag-sign out",
            .signOutConfirmTitle: "Mag-sign out?",
            .helpAndFaq: "Tulong at FAQ",
            .privacyPolicy: "Patakaran sa privacy",
            .termsOfService: "Mga tuntunin ng serbisyo",
            .unlockProTitle: "I-unlock ang BeeClean Pro",
            .unlockProSubtitle: "Walang limitasyong paglilinis, lahat ng kategorya",
            .upgrade: "Mag-upgrade",
            .deleteAccount: "Tanggalin ang account",
            .streak: "STREAK",
            .cleaned: "NALINIS",
            .saved: "NATIPID",
            .save: "I-save",
            .cancel: "Kanselahin",
            .languageSearchPlaceholder: "Maghanap ng wika",
            .languageEmptyState: "Walang tumutugmang wika.",
            .selectLanguage: "Pumili ng wika"
        ],

        // MARK: az
        .azerbaijani: [
            .settings: "Parametrlər",
            .yourName: "Adınız",
            .yourNameSubtitle: "Arınızın adından ayrı.",
            .preferences: "Tərcihlər",
            .account: "Hesab",
            .supportAndLegal: "Dəstək və hüquqi",
            .notifications: "Bildirişlər",
            .hapticFeedback: "Haptik geribildirim",
            .theme: "Mövzu",
            .language: "Dil",
            .auto: "Avtomatik",
            .autoSubtitle: "Günün vaxtına uyğun",
            .light: "Açıq",
            .lightSubtitle: "Həmişə açıq mövzu",
            .dark: "Qaranlıq",
            .darkSubtitle: "Həmişə qaranlıq mövzu",
            .manageSubscription: "Abunəliyi idarə et",
            .signOut: "Çıxış",
            .signOutConfirmTitle: "Çıxış edək?",
            .helpAndFaq: "Yardım və FAQ",
            .privacyPolicy: "Məxfilik siyasəti",
            .termsOfService: "Xidmət şərtləri",
            .unlockProTitle: "BeeClean Pro-nu aç",
            .unlockProSubtitle: "Bütün kateqoriyalarda limitsiz təmizlik",
            .upgrade: "Yenilə",
            .deleteAccount: "Hesabı sil",
            .streak: "SERİYA",
            .cleaned: "TƏMİZLƏNDİ",
            .saved: "QƏNAƏT",
            .save: "Yadda saxla",
            .cancel: "Ləğv et",
            .languageSearchPlaceholder: "Dil axtar",
            .languageEmptyState: "Uyğun dil tapılmadı.",
            .selectLanguage: "Dil seçin"
        ],

        // MARK: fa
        .persian: [
            .settings: "تنظیمات",
            .yourName: "نام شما",
            .yourNameSubtitle: "جدا از نام زنبور شما.",
            .preferences: "ترجیحات",
            .account: "حساب",
            .supportAndLegal: "پشتیبانی و حقوقی",
            .notifications: "اعلان‌ها",
            .hapticFeedback: "بازخورد لمسی",
            .theme: "تم",
            .language: "زبان",
            .auto: "خودکار",
            .autoSubtitle: "بر اساس زمان روز",
            .light: "روشن",
            .lightSubtitle: "همیشه تم روشن",
            .dark: "تیره",
            .darkSubtitle: "همیشه تم تیره",
            .manageSubscription: "مدیریت اشتراک",
            .signOut: "خروج",
            .signOutConfirmTitle: "خروج؟",
            .helpAndFaq: "راهنما و سوالات",
            .privacyPolicy: "سیاست حریم خصوصی",
            .termsOfService: "شرایط خدمات",
            .unlockProTitle: "BeeClean Pro را باز کنید",
            .unlockProSubtitle: "پاکسازی نامحدود در همه دسته‌ها",
            .upgrade: "ارتقاء",
            .deleteAccount: "حذف حساب",
            .streak: "زنجیره",
            .cleaned: "پاک شده",
            .saved: "ذخیره شده",
            .save: "ذخیره",
            .cancel: "لغو",
            .languageSearchPlaceholder: "جستجوی زبان",
            .languageEmptyState: "زبانی یافت نشد.",
            .selectLanguage: "انتخاب زبان"
        ],

        // MARK: ca
        .catalan: [
            .settings: "Configuració",
            .yourName: "El teu nom",
            .yourNameSubtitle: "Diferent del nom de la teva abella.",
            .preferences: "Preferències",
            .account: "Compte",
            .supportAndLegal: "Suport i legal",
            .notifications: "Notificacions",
            .hapticFeedback: "Resposta hàptica",
            .theme: "Tema",
            .language: "Idioma",
            .auto: "Automàtic",
            .autoSubtitle: "Segons l'hora del dia",
            .light: "Clar",
            .lightSubtitle: "Sempre tema clar",
            .dark: "Fosc",
            .darkSubtitle: "Sempre tema fosc",
            .manageSubscription: "Gestiona la subscripció",
            .signOut: "Tanca la sessió",
            .signOutConfirmTitle: "Tancar la sessió?",
            .helpAndFaq: "Ajuda i FAQ",
            .privacyPolicy: "Política de privacitat",
            .termsOfService: "Condicions del servei",
            .unlockProTitle: "Desbloqueja BeeClean Pro",
            .unlockProSubtitle: "Neteges il·limitades, totes les categories",
            .upgrade: "Millora",
            .deleteAccount: "Elimina el compte",
            .streak: "RATXA",
            .cleaned: "NETEJAT",
            .saved: "ESTALVIAT",
            .save: "Desa",
            .cancel: "Cancel·la",
            .languageSearchPlaceholder: "Cerca idiomes",
            .languageEmptyState: "Cap idioma coincideix.",
            .selectLanguage: "Selecciona l'idioma"
        ],

        // MARK: sk
        .slovak: [
            .settings: "Nastavenia",
            .yourName: "Tvoje meno",
            .yourNameSubtitle: "Odlišné od mena tvojej včely.",
            .preferences: "Predvoľby",
            .account: "Účet",
            .supportAndLegal: "Podpora a právne",
            .notifications: "Upozornenia",
            .hapticFeedback: "Hmatová odozva",
            .theme: "Téma",
            .language: "Jazyk",
            .auto: "Automaticky",
            .autoSubtitle: "Podľa dennej doby",
            .light: "Svetlá",
            .lightSubtitle: "Vždy svetlá téma",
            .dark: "Tmavá",
            .darkSubtitle: "Vždy tmavá téma",
            .manageSubscription: "Spravovať predplatné",
            .signOut: "Odhlásiť",
            .signOutConfirmTitle: "Odhlásiť?",
            .helpAndFaq: "Pomoc a FAQ",
            .privacyPolicy: "Zásady ochrany súkromia",
            .termsOfService: "Podmienky služby",
            .unlockProTitle: "Odomknite BeeClean Pro",
            .unlockProSubtitle: "Neobmedzené upratovanie, všetky kategórie",
            .upgrade: "Upgradovať",
            .deleteAccount: "Zmazať účet",
            .streak: "SÉRIA",
            .cleaned: "UPRATANÉ",
            .saved: "UŠETRENÉ",
            .save: "Uložiť",
            .cancel: "Zrušiť",
            .languageSearchPlaceholder: "Hľadať jazyky",
            .languageEmptyState: "Žiadny jazyk nevyhovuje.",
            .selectLanguage: "Vyberte jazyk"
        ],

        // MARK: hr
        .croatian: [
            .settings: "Postavke",
            .yourName: "Tvoje ime",
            .yourNameSubtitle: "Odvojeno od imena tvoje pčele.",
            .preferences: "Postavke",
            .account: "Račun",
            .supportAndLegal: "Podrška i pravno",
            .notifications: "Obavijesti",
            .hapticFeedback: "Haptičke povratne informacije",
            .theme: "Tema",
            .language: "Jezik",
            .auto: "Auto",
            .autoSubtitle: "Prema dobu dana",
            .light: "Svijetlo",
            .lightSubtitle: "Uvijek svijetla tema",
            .dark: "Tamno",
            .darkSubtitle: "Uvijek tamna tema",
            .manageSubscription: "Upravljaj pretplatom",
            .signOut: "Odjava",
            .signOutConfirmTitle: "Odjaviti se?",
            .helpAndFaq: "Pomoć i FAQ",
            .privacyPolicy: "Pravila privatnosti",
            .termsOfService: "Uvjeti korištenja",
            .unlockProTitle: "Otključajte BeeClean Pro",
            .unlockProSubtitle: "Neograničeno čišćenje, sve kategorije",
            .upgrade: "Nadogradi",
            .deleteAccount: "Obriši račun",
            .streak: "NIZ",
            .cleaned: "OČIŠĆENO",
            .saved: "UŠTEĐENO",
            .save: "Spremi",
            .cancel: "Odustani",
            .languageSearchPlaceholder: "Traži jezike",
            .languageEmptyState: "Nema jezika koji odgovara.",
            .selectLanguage: "Odaberi jezik"
        ],

        // MARK: bg
        .bulgarian: [
            .settings: "Настройки",
            .yourName: "Вашето име",
            .yourNameSubtitle: "Отделно от името на вашата пчела.",
            .preferences: "Предпочитания",
            .account: "Акаунт",
            .supportAndLegal: "Поддръжка и правни",
            .notifications: "Известия",
            .hapticFeedback: "Хаптична обратна връзка",
            .theme: "Тема",
            .language: "Език",
            .auto: "Авто",
            .autoSubtitle: "Според часа на деня",
            .light: "Светла",
            .lightSubtitle: "Винаги светла тема",
            .dark: "Тъмна",
            .darkSubtitle: "Винаги тъмна тема",
            .manageSubscription: "Управление на абонамента",
            .signOut: "Изход",
            .signOutConfirmTitle: "Изход?",
            .helpAndFaq: "Помощ и ЧЗВ",
            .privacyPolicy: "Политика за поверителност",
            .termsOfService: "Условия за ползване",
            .unlockProTitle: "Отключете BeeClean Pro",
            .unlockProSubtitle: "Неограничено почистване, всички категории",
            .upgrade: "Надстройка",
            .deleteAccount: "Изтрий акаунта",
            .streak: "СЕРИЯ",
            .cleaned: "ПОЧИСТЕНИ",
            .saved: "СПЕСТЕНИ",
            .save: "Запази",
            .cancel: "Отказ",
            .languageSearchPlaceholder: "Търсене на езици",
            .languageEmptyState: "Няма съвпадащ език.",
            .selectLanguage: "Изберете език"
        ],

        // MARK: sl
        .slovenian: [
            .settings: "Nastavitve",
            .yourName: "Tvoje ime",
            .yourNameSubtitle: "Ločeno od imena tvoje čebele.",
            .preferences: "Nastavitve",
            .account: "Račun",
            .supportAndLegal: "Podpora in pravno",
            .notifications: "Obvestila",
            .hapticFeedback: "Haptične povratne informacije",
            .theme: "Tema",
            .language: "Jezik",
            .auto: "Samodejno",
            .autoSubtitle: "Glede na uro dneva",
            .light: "Svetlo",
            .lightSubtitle: "Vedno svetla tema",
            .dark: "Temno",
            .darkSubtitle: "Vedno temna tema",
            .manageSubscription: "Upravljaj naročnino",
            .signOut: "Odjava",
            .signOutConfirmTitle: "Odjavi se?",
            .helpAndFaq: "Pomoč in FAQ",
            .privacyPolicy: "Pravilnik o zasebnosti",
            .termsOfService: "Pogoji storitve",
            .unlockProTitle: "Odklenite BeeClean Pro",
            .unlockProSubtitle: "Neomejeno čiščenje, vse kategorije",
            .upgrade: "Nadgradi",
            .deleteAccount: "Izbriši račun",
            .streak: "NIZ",
            .cleaned: "POČIŠČENO",
            .saved: "PRIHRANJENO",
            .save: "Shrani",
            .cancel: "Prekliči",
            .languageSearchPlaceholder: "Iskanje jezikov",
            .languageEmptyState: "Noben jezik se ne ujema.",
            .selectLanguage: "Izberite jezik"
        ],

        // MARK: lt
        .lithuanian: [
            .settings: "Nustatymai",
            .yourName: "Jūsų vardas",
            .yourNameSubtitle: "Atskirai nuo bitės vardo.",
            .preferences: "Nuostatos",
            .account: "Paskyra",
            .supportAndLegal: "Pagalba ir teisinė",
            .notifications: "Pranešimai",
            .hapticFeedback: "Lytėjimo atsakas",
            .theme: "Tema",
            .language: "Kalba",
            .auto: "Auto",
            .autoSubtitle: "Pagal paros laiką",
            .light: "Šviesi",
            .lightSubtitle: "Visada šviesi tema",
            .dark: "Tamsi",
            .darkSubtitle: "Visada tamsi tema",
            .manageSubscription: "Valdyti prenumeratą",
            .signOut: "Atsijungti",
            .signOutConfirmTitle: "Atsijungti?",
            .helpAndFaq: "Pagalba ir DUK",
            .privacyPolicy: "Privatumo politika",
            .termsOfService: "Paslaugų sąlygos",
            .unlockProTitle: "Atrakinkite BeeClean Pro",
            .unlockProSubtitle: "Neribota tvarka, visos kategorijos",
            .upgrade: "Atnaujinti",
            .deleteAccount: "Ištrinti paskyrą",
            .streak: "SERIJA",
            .cleaned: "SUTVARKYTA",
            .saved: "SUTAUPYTA",
            .save: "Išsaugoti",
            .cancel: "Atšaukti",
            .languageSearchPlaceholder: "Ieškoti kalbų",
            .languageEmptyState: "Nerasta atitinkančių kalbų.",
            .selectLanguage: "Pasirinkite kalbą"
        ],

        // MARK: lv
        .latvian: [
            .settings: "Iestatījumi",
            .yourName: "Jūsu vārds",
            .yourNameSubtitle: "Atsevišķi no bites vārda.",
            .preferences: "Preferences",
            .account: "Konts",
            .supportAndLegal: "Atbalsts un juridiskie",
            .notifications: "Paziņojumi",
            .hapticFeedback: "Haptiskā atgriezeniskā saite",
            .theme: "Tēma",
            .language: "Valoda",
            .auto: "Auto",
            .autoSubtitle: "Atkarībā no diennakts laika",
            .light: "Gaiša",
            .lightSubtitle: "Vienmēr gaiša tēma",
            .dark: "Tumša",
            .darkSubtitle: "Vienmēr tumša tēma",
            .manageSubscription: "Pārvaldīt abonementu",
            .signOut: "Iziet",
            .signOutConfirmTitle: "Iziet?",
            .helpAndFaq: "Palīdzība un BUJ",
            .privacyPolicy: "Privātuma politika",
            .termsOfService: "Pakalpojuma noteikumi",
            .unlockProTitle: "Atbloķēt BeeClean Pro",
            .unlockProSubtitle: "Neierobežota tīrīšana, visas kategorijas",
            .upgrade: "Jaunināt",
            .deleteAccount: "Dzēst kontu",
            .streak: "SĒRIJA",
            .cleaned: "NOTĪRĪTS",
            .saved: "IETAUPĪTS",
            .save: "Saglabāt",
            .cancel: "Atcelt",
            .languageSearchPlaceholder: "Meklēt valodas",
            .languageEmptyState: "Nav atbilstošu valodu.",
            .selectLanguage: "Izvēlieties valodu"
        ],

        // MARK: et
        .estonian: [
            .settings: "Seaded",
            .yourName: "Sinu nimi",
            .yourNameSubtitle: "Eraldi sinu mesilase nimest.",
            .preferences: "Eelistused",
            .account: "Konto",
            .supportAndLegal: "Tugi ja juriidiline",
            .notifications: "Teavitused",
            .hapticFeedback: "Haptiline tagasiside",
            .theme: "Teema",
            .language: "Keel",
            .auto: "Auto",
            .autoSubtitle: "Vastavalt päevaajale",
            .light: "Hele",
            .lightSubtitle: "Alati hele teema",
            .dark: "Tume",
            .darkSubtitle: "Alati tume teema",
            .manageSubscription: "Halda tellimust",
            .signOut: "Logi välja",
            .signOutConfirmTitle: "Logi välja?",
            .helpAndFaq: "Abi ja KKK",
            .privacyPolicy: "Privaatsuspoliitika",
            .termsOfService: "Teenusetingimused",
            .unlockProTitle: "Avage BeeClean Pro",
            .unlockProSubtitle: "Piiramatu koristamine, kõik kategooriad",
            .upgrade: "Uuenda",
            .deleteAccount: "Kustuta konto",
            .streak: "SEERIA",
            .cleaned: "PUHASTATUD",
            .saved: "SÄÄSTETUD",
            .save: "Salvesta",
            .cancel: "Tühista",
            .languageSearchPlaceholder: "Otsi keeli",
            .languageEmptyState: "Vastavaid keeli ei leitud.",
            .selectLanguage: "Vali keel"
        ],

        // MARK: sw
        .swahili: [
            .settings: "Mipangilio",
            .yourName: "Jina lako",
            .yourNameSubtitle: "Tofauti na jina la nyuki wako.",
            .preferences: "Mapendeleo",
            .account: "Akaunti",
            .supportAndLegal: "Msaada na kisheria",
            .notifications: "Arifa",
            .hapticFeedback: "Mrejesho wa mguso",
            .theme: "Mandhari",
            .language: "Lugha",
            .auto: "Otomatiki",
            .autoSubtitle: "Hufuata wakati wa siku",
            .light: "Nyepesi",
            .lightSubtitle: "Daima mandhari nyepesi",
            .dark: "Giza",
            .darkSubtitle: "Daima mandhari giza",
            .manageSubscription: "Dhibiti usajili",
            .signOut: "Ondoka",
            .signOutConfirmTitle: "Ondoka?",
            .helpAndFaq: "Usaidizi na FAQ",
            .privacyPolicy: "Sera ya faragha",
            .termsOfService: "Masharti ya huduma",
            .unlockProTitle: "Fungua BeeClean Pro",
            .unlockProSubtitle: "Usafishaji usio na kikomo, kategoria zote",
            .upgrade: "Boresha",
            .deleteAccount: "Futa akaunti",
            .streak: "MFULULIZO",
            .cleaned: "IMESAFISHWA",
            .saved: "IMEOKOLEWA",
            .save: "Hifadhi",
            .cancel: "Ghairi",
            .languageSearchPlaceholder: "Tafuta lugha",
            .languageEmptyState: "Hakuna lugha inayolingana.",
            .selectLanguage: "Chagua lugha"
        ],

        // MARK: af
        .afrikaans: [
            .settings: "Instellings",
            .yourName: "Jou naam",
            .yourNameSubtitle: "Apart van jou by se naam.",
            .preferences: "Voorkeure",
            .account: "Rekening",
            .supportAndLegal: "Ondersteuning en wetlik",
            .notifications: "Kennisgewings",
            .hapticFeedback: "Haptiese terugvoer",
            .theme: "Tema",
            .language: "Taal",
            .auto: "Outomaties",
            .autoSubtitle: "Volg tyd van die dag",
            .light: "Lig",
            .lightSubtitle: "Altyd ligte tema",
            .dark: "Donker",
            .darkSubtitle: "Altyd donker tema",
            .manageSubscription: "Bestuur intekening",
            .signOut: "Teken uit",
            .signOutConfirmTitle: "Teken uit?",
            .helpAndFaq: "Hulp en FAQ",
            .privacyPolicy: "Privaatheidsbeleid",
            .termsOfService: "Diensbepalings",
            .unlockProTitle: "Ontsluit BeeClean Pro",
            .unlockProSubtitle: "Onbeperkte skoonmaak, alle kategorieë",
            .upgrade: "Opgradeer",
            .deleteAccount: "Vee rekening uit",
            .streak: "REEKS",
            .cleaned: "SKOONGEMAAK",
            .saved: "GESPAAR",
            .save: "Stoor",
            .cancel: "Kanselleer",
            .languageSearchPlaceholder: "Soek tale",
            .languageEmptyState: "Geen tale stem ooreen nie.",
            .selectLanguage: "Kies taal"
        ],

        // MARK: ta
        .tamil: [
            .settings: "அமைப்புகள்",
            .yourName: "உங்கள் பெயர்",
            .yourNameSubtitle: "உங்கள் தேனீயின் பெயரிலிருந்து வேறானது.",
            .preferences: "விருப்பங்கள்",
            .account: "கணக்கு",
            .supportAndLegal: "ஆதரவு மற்றும் சட்டபூர்வம்",
            .notifications: "அறிவிப்புகள்",
            .hapticFeedback: "தொடு கருத்து",
            .theme: "தீம்",
            .language: "மொழி",
            .auto: "தானியங்கி",
            .autoSubtitle: "நாள் நேரத்திற்கு ஏற்ப",
            .light: "ஒளி",
            .lightSubtitle: "எப்போதும் ஒளி தீம்",
            .dark: "இருண்ட",
            .darkSubtitle: "எப்போதும் இருண்ட தீம்",
            .manageSubscription: "சந்தாவை நிர்வகிக்கவும்",
            .signOut: "வெளியேறு",
            .signOutConfirmTitle: "வெளியேறவா?",
            .helpAndFaq: "உதவி & FAQ",
            .privacyPolicy: "தனியுரிமைக் கொள்கை",
            .termsOfService: "சேவை விதிமுறைகள்",
            .unlockProTitle: "BeeClean Pro-ஐ திற",
            .unlockProSubtitle: "வரம்பற்ற சுத்தம், அனைத்து வகைகள்",
            .upgrade: "மேம்படுத்து",
            .deleteAccount: "கணக்கை நீக்கு",
            .streak: "வரிசை",
            .cleaned: "சுத்தம் செய்யப்பட்டது",
            .saved: "சேமிக்கப்பட்டது",
            .save: "சேமி",
            .cancel: "ரத்து",
            .languageSearchPlaceholder: "மொழிகளைத் தேடு",
            .languageEmptyState: "மொழி எதுவும் பொருந்தவில்லை.",
            .selectLanguage: "மொழியைத் தேர்வுசெய்க"
        ],

        // MARK: mr
        .marathi: [
            .settings: "सेटिंग्ज",
            .yourName: "तुमचे नाव",
            .yourNameSubtitle: "तुमच्या मधमाशीच्या नावापेक्षा वेगळे.",
            .preferences: "प्राधान्ये",
            .account: "खाते",
            .supportAndLegal: "मदत आणि कायदेशीर",
            .notifications: "सूचना",
            .hapticFeedback: "स्पर्श प्रतिसाद",
            .theme: "थीम",
            .language: "भाषा",
            .auto: "स्वयं",
            .autoSubtitle: "दिवसाच्या वेळेनुसार",
            .light: "हलकी",
            .lightSubtitle: "नेहमी हलकी थीम",
            .dark: "गडद",
            .darkSubtitle: "नेहमी गडद थीम",
            .manageSubscription: "सदस्यता व्यवस्थापित करा",
            .signOut: "साइन आउट",
            .signOutConfirmTitle: "साइन आउट करायचे?",
            .helpAndFaq: "मदत आणि FAQ",
            .privacyPolicy: "गोपनीयता धोरण",
            .termsOfService: "सेवा अटी",
            .unlockProTitle: "BeeClean Pro अनलॉक करा",
            .unlockProSubtitle: "प्रत्येक श्रेणीत अमर्याद स्वच्छता",
            .upgrade: "अपग्रेड",
            .deleteAccount: "खाते हटवा",
            .streak: "स्ट्रीक",
            .cleaned: "स्वच्छ",
            .saved: "वाचवले",
            .save: "जतन करा",
            .cancel: "रद्द करा",
            .languageSearchPlaceholder: "भाषा शोधा",
            .languageEmptyState: "कोणतीही भाषा जुळत नाही.",
            .selectLanguage: "भाषा निवडा"
        ]
    ]
}
