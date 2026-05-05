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

    enum Colors {
        static let income = "#22C55E"
        static let expense = "#EF4444"
        static let neutral = "#6B7280"
        static let primary = "#3B82F6"
        static let secondary = "#8B5CF6"
    }

    enum Animation {
        static let springDamping: Double = 0.8
        static let springVelocity: Double = 0.5
    }

    enum Pagination {
        static let transactionsPageSize = 50
    }
}
