import Foundation
import FirebaseFirestore

struct BankAccount: Codable, Identifiable, Hashable {
    static func == (lhs: BankAccount, rhs: BankAccount) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var id: String
    var name: String
    var officialName: String?   // IBAN or account identification
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

    /// Human-readable account type label
    var accountTypeLabel: String {
        switch cashAccountType ?? type {
        case "CACC": return "Conto corrente"
        case "CARD": return "Carta di pagamento"
        case "CASH": return "Conto contante"
        case "LOAN": return "Prestito"
        case "SVGS": return "Conto risparmio"
        case "OTHR", "OTHI": return "Altro"
        default: return cashAccountType ?? type
        }
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

// MARK: - Raw Firestore format (saved by web app via Enable Banking API)

struct RawFirestoreBankAccount: Codable {
    struct AccountIdMap: Codable {
        var iban: String?
        var other: OtherRef?
        struct OtherRef: Codable {
            var identification: String?
            var scheme_name: String?
        }
    }
    struct RawBalance: Codable {
        struct BalanceAmount: Codable {
            var amount: String?
            var currency: String?
        }
        var balance_amount: BalanceAmount?
        var balance_type: String?
        var reference_date: String?
        var name: String?
    }

    var account_id: AccountIdMap?
    var balances: [RawBalance]?
    var cashAccountType: String?
    var currency: String?
    var lastSynced: String?
    var name: String?
    var sessionId: String?
    var account_type: String?

    var displayIban: String? { account_id?.iban ?? account_id?.other?.identification }

    var bestBalanceAmount: Double {
        let pick = balances?.first(where: { $0.balance_type == "ITAV" }) ?? balances?.first
        return Double(pick?.balance_amount?.amount ?? "0") ?? 0
    }

    func toBankAccount(id: String) -> BankAccount {
        BankAccount(
            id: id,
            name: name ?? id,
            officialName: displayIban,
            type: cashAccountType ?? account_type ?? "CACC",
            subtype: nil,
            balances: [BankBalance(amount: bestBalanceAmount, currency: currency ?? "EUR", type: "current")],
            institutionId: nil,
            institutionName: nil,
            isCreditCard: nil,
            creditLimit: nil,
            paymentDay: nil,
            excludeFromTotal: nil,
            customName: nil,
            warningThreshold: nil,
            dangerThreshold: nil,
            sessionId: sessionId,
            currency: currency ?? "EUR",
            calculatedBalance: bestBalanceAmount,
            cashAccountType: cashAccountType
        )
    }
}

// MARK: - Account Settings

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

// MARK: - Bank Session

struct BankSession: Codable, Identifiable, Hashable {
    static func == (lhs: BankSession, rhs: BankSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    @DocumentID var id: String?
    var sessionId: String?
    var accessToken: String?
    var expiresAt: String?
    var institutionName: String?
    var createdAt: String?
    var status: String?
    var description: String?
    var aspsp: Aspsp?

    struct Aspsp: Codable {
        var name: String?
        var country: String?
    }

    var displayInstitutionName: String? { aspsp?.name ?? institutionName }
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

