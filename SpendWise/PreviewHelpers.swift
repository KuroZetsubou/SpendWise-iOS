import Foundation

// MARK: - Preview mock data shared across all SwiftUI #Preview blocks

extension DashboardViewModel {
    /// A pre-populated ViewModel for use in Xcode Previews.
    /// Firebase listeners won't fire (no authenticated user in preview).
    static var preview: DashboardViewModel {
        let vm = DashboardViewModel()
        vm.transactions = MockData.transactions
        vm.categories   = MockData.categories
        vm.bankAccounts = MockData.bankAccounts
        vm.bankSessions = MockData.bankSessions
        vm.recurrings   = MockData.recurrings
        vm.budgets      = MockData.budgets
        return vm
    }
}

enum MockData {
    // MARK: Transactions
    static let transactions: [Transaction] = {
        var t1 = Transaction(userId: "preview", amount: 1850.0, type: .income,
                             category: "Stipendio", description: "Stipendio mensile",
                             date: "2026-05-01")
        var t2 = Transaction(userId: "preview", amount: 45.80, type: .expense,
                             category: "Cibo & Spesa", description: "Supermercato Esselunga",
                             date: "2026-05-03")
        var t3 = Transaction(userId: "preview", amount: 9.99, type: .expense,
                             category: "Intrattenimento", description: "Netflix",
                             date: "2026-05-04")
        t3.recurring = true
        var t4 = Transaction(userId: "preview", amount: 120.0, type: .expense,
                             category: "Trasporti", description: "Carburante Q8",
                             date: "2026-05-05")
        var t5 = Transaction(userId: "preview", amount: 9.95, type: .income,
                             category: "Investimenti", description: "Stock Perk – Walt Disney",
                             date: "2026-05-04")
        t5.bankTransactionId = "019df377-0000-0000-0000-preview01"
        t5.accountId = "manual_trade_republic"
        var t6 = Transaction(userId: "preview", amount: 320.0, type: .expense,
                             category: "Casa", description: "Bolletta luce",
                             date: "2026-04-28")
        return [t1, t2, t3, t4, t5, t6]
    }()

    // MARK: Categories
    static let categories: [AppCategory] = [
        AppCategory(userId: "preview", name: "Stipendio",       type: .income),
        AppCategory(userId: "preview", name: "Investimenti",    type: .income),
        AppCategory(userId: "preview", name: "Cibo & Spesa",    type: .expense,  icon: "cart"),
        AppCategory(userId: "preview", name: "Intrattenimento", type: .expense,  icon: "tv"),
        AppCategory(userId: "preview", name: "Trasporti",       type: .expense,  icon: "car"),
        AppCategory(userId: "preview", name: "Casa",            type: .expense,  icon: "house"),
        AppCategory(userId: "preview", name: "Salute",          type: .expense,  icon: "heart")
    ]

    // MARK: Bank Accounts
    static let bankAccount: BankAccount = {
        var a = BankAccount(id: "acc-preview-1",
                            name: "Conto Corrente",
                            officialName: "IT60 X054 2811 1010 0000 0123 456",
                            type: "CACC",
                            subtype: nil,
                            balances: [BankBalance(amount: 3240.50, currency: "EUR", type: "expected")],
                            institutionId: "n26",
                            institutionName: "N26",
                            isCreditCard: false,
                            creditLimit: nil,
                            paymentDay: nil,
                            excludeFromTotal: nil,
                            customName: nil,
                            warningThreshold: nil,
                            dangerThreshold: nil,
                            sessionId: "sess-preview-1",
                            currency: "EUR")
        return a
    }()

    static let manualAccount: BankAccount = {
        var a = BankAccount(id: "manual_trade_republic",
                            name: "Trade Republic",
                            type: "CACC",
                            balances: [],
                            currency: "EUR")
        a.isManual = true
        return a
    }()

    static let bankAccounts: [BankAccount] = [bankAccount, manualAccount]

    // MARK: Bank Sessions
    static let bankSession: BankSession = {
        var s = BankSession()
        s.sessionId = "sess-preview-1"
        s.institutionName = "N26"
        s.status = "ACTIVE"
        s.aspsp = BankSession.Aspsp(name: "N26", country: "DE")
        return s
    }()

    static let manualSession: BankSession = {
        var s = BankSession()
        s.sessionId = "manual_trade_republic"
        s.institutionName = "Trade Republic"
        s.status = "MANUAL"
        s.isManual = true
        s.aspsp = BankSession.Aspsp(name: "Trade Republic", country: "EU")
        return s
    }()

    static let bankSessions: [BankSession] = [bankSession, manualSession]

    // MARK: Recurrings
    static let recurrings: [RecurringPayment] = [
        RecurringPayment(userId: "preview", name: "Netflix",
                         amount: 9.99, type: .expense, category: "Intrattenimento",
                         recurringDate: 15, recurringTiming: .monthly,
                         transactionIds: [], isActive: true),
        RecurringPayment(userId: "preview", name: "Palestra",
                         amount: 39.0, type: .expense, category: "Salute",
                         recurringDate: 1, recurringTiming: .monthly,
                         transactionIds: [], isActive: true),
        RecurringPayment(userId: "preview", name: "Stipendio",
                         amount: 1850.0, type: .income, category: "Stipendio",
                         recurringDate: 27, recurringTiming: .monthly,
                         transactionIds: [], isActive: true)
    ]

    static let budgets: [Budget] = [
        Budget(userId: "preview", category: "Cibo & Spesa", monthlyLimit: 300, isActive: true),
        Budget(userId: "preview", category: "Intrattenimento", monthlyLimit: 80, isActive: true),
        Budget(userId: "preview", category: "Trasporti", monthlyLimit: 150, isActive: true)
    ]
}
