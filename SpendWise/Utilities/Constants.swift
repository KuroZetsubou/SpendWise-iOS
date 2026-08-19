import Foundation

enum Constants {
    static let geminiAPIKey = "" // Set via Settings or Info.plist
    static let defaultBankAPIBaseURL = "http://localhost:3001"

    enum UserDefaultsKeys {
        static let geminiAPIKey = "gemini_api_key"
        static let bankAPIBaseURL = "bank_api_base_url"
        static let ebAppId = "eb_app_id"
        static let ebAppSecret = "eb_app_secret"
        static let selectedCurrency = "selected_currency"
    }

    enum Currency {
        static let eur = "EUR"
        static let defaultLocale = "it_IT"
    }

    /// Hex values mirroring the FinanceMode design system tokens. Prefer `DS.Colors.*`
    /// in new code; these stay for the string-based category/impact color plumbing.
    enum Colors {
        static let income = "#2FC81E"    // --green-500
        static let expense = "#C10D14"   // --red-500
        static let neutral = "#7A828C"   // --gray-500
        static let primary = "#3856FC"   // --blue-500
        static let secondary = "#8B5CF6" // --purple-500
    }

    enum Animation {
        static let springDamping: Double = 0.8
        static let springVelocity: Double = 0.5
    }

    enum Pagination {
        static let transactionsPageSize = 50
    }
}
