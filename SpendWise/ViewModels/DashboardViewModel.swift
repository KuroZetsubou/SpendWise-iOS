import Foundation
import FirebaseAuth
import Combine

struct MonthlyData: Identifiable {
    var id: String { "\(month)-\(type)" }
    var month: String
    var amount: Double
    var type: String // "Entrate" | "Uscite"
}

struct CategoryBreakdown: Identifiable {
    var id: String { category }
    var category: String
    var amount: Double
    var color: String
    var percentage: Double
}

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published State
    @Published var transactions: [Transaction] = []
    @Published var categories: [AppCategory] = []
    @Published var bankAccounts: [BankAccount] = []
    @Published var bankSessions: [BankSession] = []
    @Published var accountSettings: [String: BankAccountSettings] = [:]
    @Published var insights: [FinancialInsight] = []
    @Published var recurrings: [RecurringPayment] = []

    @Published var isLoadingInsights = false
    @Published var isLoadingTransactions = false
    @Published var isSyncingTransactions = false
    @Published var syncProgress: TransactionSyncService.SyncProgress?
    @Published var errorMessage: String?
    @Published var selectedTab: Tab = .dashboard

    enum Tab: Int, CaseIterable {
        case dashboard = 0, transactions, insights, bank, settings
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .transactions: return "Transazioni"
            case .insights: return "Insights"
            case .bank: return "Banca"
            case .settings: return "Impostazioni"
            }
        }
        var icon: String {
            switch self {
            case .dashboard: return "house"
            case .transactions: return "list.bullet"
            case .insights: return "chart.pie"
            case .bank: return "building.columns"
            case .settings: return "gearshape"
            }
        }
    }

    private let firestoreService = FirestoreService.shared
    private let authService = AuthService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                if let user = user {
                    self?.setupListeners(userId: user.uid)
                } else {
                    self?.firestoreService.stopAllListeners()
                    self?.transactions = []
                    self?.categories = []
                }
            }
            .store(in: &cancellables)
        setupDataProcessing()
    }

    // MARK: - Listeners Setup

    private func setupListeners(userId: String) {
        firestoreService.subscribeTransactions(userId: userId) { [weak self] txs in
            self?.transactions = txs
        }
        firestoreService.subscribeCategories(userId: userId) { [weak self] cats in
            self?.categories = cats
            if cats.isEmpty {
                // No categories in Firestore, use built-in defaults for display
            }
        }
        firestoreService.subscribeAccountSettings(userId: userId) { [weak self] settings in
            self?.accountSettings = settings
        }
        firestoreService.subscribeRecurrings(userId: userId) { [weak self] items in
            self?.recurrings = items
        }
        firestoreService.subscribeBankAccounts(userId: userId) { [weak self] accounts in
            self?.bankAccounts = accounts
        }

        Task { await loadBankSessions(userId: userId) }
    }

    private func loadBankSessions(userId: String) async {
        do {
            bankSessions = try await firestoreService.getBankSessionsTyped(userId: userId)
        } catch {
            // Non-fatal
        }
    }

    func refreshBankSessions() async {
        guard let userId = userId else { return }
        await loadBankSessions(userId: userId)
    }

    // MARK: - Resolved Bank Accounts (merges raw + settings + institution name)

    var resolvedBankAccounts: [BankAccount] {
        bankAccounts.map { account in
            var r = account
            if let s = accountSettings[account.id] {
                if let cn = s.customName { r.customName = cn }
                r.isCreditCard = s.isCreditCard
                r.creditLimit = s.creditLimit
                r.paymentDay = s.paymentDay
                r.excludeFromTotal = s.excludeFromTotal
                r.warningThreshold = s.warningThreshold
                r.dangerThreshold = s.dangerThreshold
            }
            if r.institutionName == nil, let sid = r.sessionId,
               let session = bankSessions.first(where: { $0.sessionId == sid }) {
                r.institutionName = session.displayInstitutionName
            }
            // For manual accounts, compute balance live from linked transactions
            if r.isManual == true {
                let linked = transactions.filter { $0.accountId == r.id && $0.ignored != true }
                let income  = linked.filter { $0.type == .income  }.reduce(0) { $0 + $1.amount }
                let expense = linked.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
                r.calculatedBalance = income - expense
            }
            return r
        }
    }

    func resolvedBankAccount(for accountId: String) -> BankAccount? {
        // Primary: match from bank_accounts (with settings + institution overlaid)
        if let found = resolvedBankAccounts.first(where: { $0.id == accountId }) {
            return found
        }
        // Fallback: build a minimal BankAccount from accountSettings alone
        // (happens when bank_accounts doc ID differs from accountSettings doc ID)
        if let s = accountSettings[accountId] {
            let session = bankSessions.first(where: { _ in true }) // best-effort institution
            return BankAccount(
                id: accountId,
                name: s.customName ?? accountId,
                officialName: nil,
                type: s.isCreditCard ? "CACC" : "CACC",
                subtype: nil,
                balances: [],
                institutionId: nil,
                institutionName: session?.displayInstitutionName,
                isCreditCard: s.isCreditCard,
                creditLimit: s.creditLimit,
                paymentDay: s.paymentDay,
                excludeFromTotal: s.excludeFromTotal,
                customName: s.customName,
                warningThreshold: s.warningThreshold,
                dangerThreshold: s.dangerThreshold,
                sessionId: nil,
                currency: "EUR",
                calculatedBalance: nil,
                cashAccountType: s.isCreditCard ? "CACC" : "CACC"
            )
        }
        return nil
    }

    // MARK: - Selected Month Navigation

    @Published var selectedMonthOffset: Int = 0  // 0 = current, -1 = last month, etc.

    var canGoForward: Bool { selectedMonthOffset < 0 }
    var canGoBack: Bool {
        // Allow up to 24 months back
        selectedMonthOffset > -24
    }

    func goToPreviousMonth() {
        guard canGoBack else { return }
        selectedMonthOffset -= 1
    }

    func goToNextMonth() {
        guard canGoForward else { return }
        selectedMonthOffset += 1
    }

    private var selectedMonthDate: Date {
        Calendar.current.date(byAdding: .month, value: selectedMonthOffset, to: Date()) ?? Date()
    }

    var selectedMonthLabel: String {
        Self._fmtMonthLabel.string(from: selectedMonthDate).capitalized
    }

    var isCurrentMonth: Bool { selectedMonthOffset == 0 }

    // MARK: - Static date formatters (created once, accessed only from @MainActor)
    // DateFormatter is not thread-safe; these are safe because the ViewModel is @MainActor.
    nonisolated(unsafe) private static let _fmtDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    nonisolated(unsafe) private static let _fmtDateTime: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    nonisolated(unsafe) private static let _fmtDateTimeTZ: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    nonisolated(unsafe) private static let _fmtISO8601 = ISO8601DateFormatter()
    nonisolated(unsafe) private static let _fmtMonthLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; f.locale = Locale(identifier: "it_IT"); return f
    }()

    // MARK: - Cached derived state
    // Updated by Combine pipeline — views always read pre-computed values.
    @Published private(set) var currentMonthTransactions: [Transaction] = []
    @Published private(set) var monthlyChartData: [MonthlyData] = []

    // MARK: - Computed Properties (derived from cached arrays — fast O(n) on small subsets)

    var userId: String? { authService.currentUser?.uid }

    var currentMonthIncome: Double {
        currentMonthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    var currentMonthExpenses: Double {
        currentMonthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    var currentMonthBalance: Double { currentMonthIncome - currentMonthExpenses }

    var recentTransactions: [Transaction] { Array(currentMonthTransactions.prefix(10)) }

    var totalBankBalance: Double {
        bankAccounts.filter { !$0.isExcluded }.reduce(0) { $0 + $1.currentBalance }
    }

    // MARK: - Category Breakdown (on-demand for specific month, e.g. InsightsView)

    func expenseCategoryBreakdown(for date: Date) -> [CategoryBreakdown] {
        let calendar = Calendar.current
        let expenses = transactions.filter { tx in
            guard !tx.isIgnored, tx.type == .expense else { return false }
            guard let txDate = dateFromString(tx.date) else { return false }
            return calendar.isDate(txDate, equalTo: date, toGranularity: .month)
        }
        return Self.buildCategoryBreakdown(expenses: expenses)
    }

    // MARK: - Cache recomputation (triggered by Combine pipeline)

    private func setupDataProcessing() {
        Publishers.CombineLatest($transactions, $selectedMonthOffset)
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] (txs, offset) in
                self?.recomputeCaches(transactions: txs, monthOffset: offset)
            }
            .store(in: &cancellables)
    }

    private func recomputeCaches(transactions: [Transaction], monthOffset: Int) {
        let calendar = Calendar.current
        let ref = calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()

        // Single pass: filter current month
        currentMonthTransactions = transactions.filter { tx in
            guard !tx.isIgnored, !tx.isTransfer else { return false }
            guard let txDate = dateFromString(tx.date) else { return false }
            return calendar.isDate(txDate, equalTo: ref, toGranularity: .month)
        }

        // Monthly chart data — 6 full scans, run on background thread
        let txsCopy = transactions
        Task.detached(priority: .userInitiated) {
            let result = Self.buildMonthlyChartData(transactions: txsCopy)
            await MainActor.run { [weak self] in self?.monthlyChartData = result }
        }
    }

    // Nonisolated so it can run inside Task.detached — creates local formatters (thread-safe)
    private nonisolated static func buildMonthlyChartData(transactions: [Transaction]) -> [MonthlyData] {
        let f1 = DateFormatter(); f1.dateFormat = "yyyy-MM-dd"; f1.locale = Locale(identifier: "en_US_POSIX")
        let f2 = DateFormatter(); f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f2.locale = Locale(identifier: "en_US_POSIX")
        let isoF = ISO8601DateFormatter()
        func parse(_ s: String) -> Date? { f1.date(from: s) ?? f2.date(from: s) ?? isoF.date(from: s) }

        let labelFmt = DateFormatter(); labelFmt.dateFormat = "MMM"; labelFmt.locale = Locale(identifier: "it_IT")
        let calendar = Calendar.current
        var result: [MonthlyData] = []

        for i in stride(from: 5, through: 0, by: -1) {
            guard let monthDate = calendar.date(byAdding: .month, value: -i, to: Date()) else { continue }
            let label = labelFmt.string(from: monthDate).capitalized
            var income: Double = 0; var expenses: Double = 0
            for tx in transactions {
                guard !tx.isIgnored, !tx.isTransfer else { continue }
                guard let d = parse(tx.date), calendar.isDate(d, equalTo: monthDate, toGranularity: .month) else { continue }
                if tx.type == .income { income += tx.amount } else { expenses += tx.amount }
            }
            result.append(MonthlyData(month: label, amount: income, type: "Entrate"))
            result.append(MonthlyData(month: label, amount: expenses, type: "Uscite"))
        }
        return result
    }

    private nonisolated static func buildCategoryBreakdown(expenses: [Transaction]) -> [CategoryBreakdown] {
        let total = expenses.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }
        var grouped: [String: Double] = [:]
        for tx in expenses { grouped[tx.category, default: 0] += tx.amount }
        return grouped.map { category, amount in
            CategoryBreakdown(
                category: category,
                amount: amount,
                color: AppCategory.categoryColors[category] ?? "#6B7280",
                percentage: (amount / total) * 100
            )
        }.sorted { $0.amount > $1.amount }
    }

    // MARK: - Recurring payments (from dedicated collection)

    var activeRecurrings: [RecurringPayment] { recurrings.filter(\.isActive) }

    var monthlyRecurringCost: Double {
        activeRecurrings.filter { $0.type == .expense }
            .reduce(0) { $0 + $1.monthlyCost }
    }

    func addRecurring(_ recurring: RecurringPayment) async {
        guard let userId = userId else { return }
        var r = recurring
        r.userId = userId
        do { _ = try await firestoreService.addRecurring(r) }
        catch { errorMessage = error.localizedDescription }
    }

    func updateRecurring(id: String, updates: [String: Any]) async {
        do { try await firestoreService.updateRecurring(id: id, updates: updates) }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteRecurring(id: String) async {
        guard let userId = userId else { return }
        do { try await firestoreService.deleteRecurring(id: id, userId: userId) }
        catch { errorMessage = error.localizedDescription }
    }

    func linkTransaction(recurringId: String, transactionId: String) async {
        guard let userId = userId else { return }
        do { try await firestoreService.linkTransaction(recurringId: recurringId, transactionId: transactionId, userId: userId) }
        catch { errorMessage = error.localizedDescription }
    }

    func unlinkTransaction(recurringId: String, transactionId: String) async {
        guard let userId = userId else { return }
        do { try await firestoreService.unlinkTransaction(recurringId: recurringId, transactionId: transactionId, userId: userId) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Transaction Sync

    func syncBankTransactions(days: Int = 30) async -> TransactionSyncService.SyncResult {
        guard let userId = userId else {
            return TransactionSyncService.SyncResult(errors: ["Utente non autenticato"])
        }
        isSyncingTransactions = true
        syncProgress = nil

        let result = await TransactionSyncService.shared.syncAll(
            userId: userId,
            days: days
        ) { [weak self] progress in
            self?.syncProgress = progress
        }

        isSyncingTransactions = false
        syncProgress = nil
        return result
    }

    // MARK: - Actions

    func addTransaction(_ transaction: Transaction) async {
        do {
            try await firestoreService.addTransaction(transaction)
        } catch {
            errorMessage = "Errore aggiunta transazione: \(error.localizedDescription)"
        }
    }

    func updateTransaction(id: String, updates: [String: Any]) async {
        do {
            try await firestoreService.updateTransaction(id: id, updates: updates)
        } catch {
            errorMessage = "Errore aggiornamento transazione: \(error.localizedDescription)"
        }
    }

    func deleteTransaction(id: String) async {
        do {
            try await firestoreService.deleteTransaction(id: id)
        } catch {
            errorMessage = "Errore eliminazione transazione: \(error.localizedDescription)"
        }
    }

    func loadInsights() async {
        guard !transactions.isEmpty else { return }
        isLoadingInsights = true
        defer { isLoadingInsights = false }

        do {
            let name = authService.userDisplayName
            insights = try await AIService.shared.getFinancialInsights(
                transactions: transactions,
                userName: name
            )
        } catch {
            errorMessage = "Errore caricamento insights: \(error.localizedDescription)"
        }
    }

    func addCategory(_ category: AppCategory) async {
        do {
            try await firestoreService.addCategory(category)
        } catch {
            errorMessage = "Errore aggiunta categoria: \(error.localizedDescription)"
        }
    }

    func deleteCategory(id: String) async {
        do {
            try await firestoreService.deleteCategory(id: id)
        } catch {
            errorMessage = "Errore eliminazione categoria: \(error.localizedDescription)"
        }
    }

    /// Imports the default category tree into Firestore.
    /// Returns count of categories added (skips duplicates by name+type).
    func importDefaultCategories() async -> Int {
        guard let userId = userId else { return 0 }
        do {
            return try await firestoreService.importDefaultCategories(userId: userId, existing: categories)
        } catch {
            errorMessage = "Errore importazione categorie: \(error.localizedDescription)"
            return 0
        }
    }

    func resetAllData() async {
        guard let userId = userId else { return }
        do {
            try await firestoreService.resetUserData(userId: userId)
        } catch {
            errorMessage = "Errore reset dati: \(error.localizedDescription)"
        }
    }

    func dismissError() { errorMessage = nil }

    // MARK: - Helpers

    func allCategories(ofType type: AppCategory.CategoryType) -> [AppCategory] {
        // Top-level = no parentId, matching type (user-owned first, then system)
        let fromFirestore = categories.filter { $0.type == type && $0.parentId == nil }
        if fromFirestore.isEmpty {
            return AppCategory.makeDefaults().filter { $0.type == type && $0.parentId == nil }
        }
        return fromFirestore.sorted { lhs, rhs in
            if lhs.userId == "system" && rhs.userId != "system" { return false }
            if lhs.userId != "system" && rhs.userId == "system" { return true }
            return lhs.name < rhs.name
        }
    }

    func subCategories(ofParent parentId: String) -> [AppCategory] {
        // parentId is a real Firestore doc ID for DB categories,
        // or a localId string for in-memory defaults
        let fromFirestore = categories.filter { $0.parentId == parentId }
        if fromFirestore.isEmpty {
            return AppCategory.makeDefaults().filter { $0.parentId == parentId }
        }
        return fromFirestore.sorted { $0.name < $1.name }
    }

    private func dateFromString(_ string: String) -> Date? {
        if let d = Self._fmtDate.date(from: string) { return d }
        if let d = Self._fmtDateTime.date(from: string) { return d }
        if let d = Self._fmtDateTimeTZ.date(from: string) { return d }
        return Self._fmtISO8601.date(from: string)
    }
}
