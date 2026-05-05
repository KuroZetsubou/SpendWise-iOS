import Foundation
import FirebaseFirestore

struct BankAccount: Codable, Identifiable {
    var id: String
    var name: String
    var officialName: String?
    var type: String
    var subtype: String?
    var balances: [BankBalance]
    var institutionId: String?
    var institutionName: String?
    var isCreditCard: Bool?
    var creditLimit: Double?
    var paymentDay: Int?
    var excludeFromTotal: Bool?
    var customName: String?
    var warningThreshold: Double?
    var dangerThreshold: Double?
    var sessionId: String?
    var currency: String?
    var calculatedBalance: Double?
    var cashAccountType: String?

    var displayName: String { customName ?? officialName ?? name }
    var isExcluded: Bool { excludeFromTotal == true }
    var displayCurrency: String { currency ?? "EUR" }

    var currentBalance: Double {
        if let calc = calculatedBalance { return calc }
        return balances.first?.amount ?? 0
    }

    var balanceStatus: BalanceStatus {
        guard let warning = warningThreshold else { return .normal }
        let danger = dangerThreshold ?? (warning * 0.5)
        if currentBalance <= danger { return .danger }
        if currentBalance <= warning { return .warning }
        return .normal
    }

    enum BalanceStatus {
        case normal, warning, danger
    }
}

struct BankBalance: Codable {
    var amount: Double?
    var currency: String?
    var type: String?
}

struct BankAccountSettings: Codable {
    var id: String
    var userId: String
    var isCreditCard: Bool
    var creditLimit: Double
    var paymentDay: Int
    var excludeFromTotal: Bool
    var customName: String?
    var warningThreshold: Double?
    var dangerThreshold: Double?
    var updatedAt: String?
}

struct BankSession: Codable, Identifiable {
    @DocumentID var id: String?
    var sessionId: String?
    var accessToken: String?
    var expiresAt: String?
    var institutionName: String?
    var createdAt: String?
    var status: String?
}

struct BankInstitution: Codable, Identifiable {
    var id: String { bic ?? name }
    var name: String
    var full_name: String?
    var logo: String?
    var country: String
    var bic: String?

    var displayName: String { full_name ?? name }
}
