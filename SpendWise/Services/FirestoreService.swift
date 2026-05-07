import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class FirestoreService: ObservableObject {
    static let shared = FirestoreService()
    private let db = Firestore.firestore(database: "ai-studio-4c91960a-949c-4665-a4a0-0be7bfe458bd")

    // Active listeners
    private var transactionListener: ListenerRegistration?
    private var categoryListener: ListenerRegistration?
    private var accountSettingsListener: ListenerRegistration?
    private var bankAccountsListener: ListenerRegistration?

    private init() {}

    // MARK: - Transactions

    func subscribeTransactions(userId: String, onChange: @escaping ([Transaction]) -> Void) {
        transactionListener?.remove()
        let q = db.collection("transactions")
            .whereField("userId", isEqualTo: userId)
            .order(by: "date", descending: true)

        transactionListener = q.addSnapshotListener { snapshot, error in
            guard let docs = snapshot?.documents else { return }
            let transactions = docs.compactMap { doc -> Transaction? in
                try? doc.data(as: Transaction.self)
            }
            Task { @MainActor in onChange(transactions) }
        }
    }

    func stopTransactionListener() {
        transactionListener?.remove()
        transactionListener = nil
    }

    func addTransaction(_ transaction: Transaction) async throws {
        var data = try Firestore.Encoder().encode(transaction)
        data.removeValue(forKey: "id")
        data["createdAt"] = FieldValue.serverTimestamp()

        if let bankId = transaction.bankTransactionId {
            let docId = "bank_\(bankId)"
            try await db.collection("transactions").document(docId).setData(data)
        } else {
            try await db.collection("transactions").addDocument(data: data)
        }
    }

    /// Writes up to ~450 transactions per Firestore batch (limit is 500 ops/batch).
    /// Splits automatically for larger arrays. Uses setData (no merge) for full overwrite/create.
    func batchAddTransactions(_ transactions: [Transaction]) async throws {
        guard !transactions.isEmpty else { return }
        let encoder = Firestore.Encoder()
        let chunks = stride(from: 0, to: transactions.count, by: 450).map {
            Array(transactions[$0..<min($0 + 450, transactions.count)])
        }
        for chunk in chunks {
            let batch = db.batch()
            for tx in chunk {
                var data = try encoder.encode(tx)
                data.removeValue(forKey: "id")
                data["createdAt"] = FieldValue.serverTimestamp()
                // Always use auto-generated IDs to avoid cross-user document collisions.
                // Dedup is handled before this call via fetchExistingBankTransactionIds.
                let ref = db.collection("transactions").document()
                batch.setData(data, forDocument: ref)
            }
            try await batch.commit()
        }
    }

    /// Fetches all `bankTransactionId` values already stored for this user (any account/source).
    /// Used to skip duplicates before a batch import.
    func fetchExistingBankTransactionIds(userId: String) async throws -> Set<String> {
        let snapshot = try await db.collection("transactions")
            .whereField("userId", isEqualTo: userId)
            .limit(to: 10000)
            .getDocuments()
        let ids = snapshot.documents.compactMap { $0.data()["bankTransactionId"] as? String }
        return Set(ids)
    }

    func updateTransaction(id: String, updates: [String: Any]) async throws {
        var sanitized = updates
        sanitized.removeValue(forKey: "id")
        sanitized.removeValue(forKey: "createdAt")
        try await db.collection("transactions").document(id).updateData(sanitized)
    }

    func deleteTransaction(id: String) async throws {
        try await db.collection("transactions").document(id).delete()
    }

    func deleteAllTransactions(userId: String) async throws {
        let snapshot = try await db.collection("transactions")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        let batch = db.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    func deleteImportedTransactions(userId: String) async throws {
        let snapshot = try await db.collection("transactions")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        let batch = db.batch()
        snapshot.documents
            .filter { $0.data()["bankTransactionId"] != nil }
            .forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    // MARK: - Categories

    func subscribeCategories(userId: String, onChange: @escaping ([AppCategory]) -> Void) {
        categoryListener?.remove()
        let q = db.collection("categories")
            .whereField("userId", in: ["system", userId])

        categoryListener = q.addSnapshotListener { snapshot, error in
            guard let docs = snapshot?.documents else { return }
            let categories = docs.compactMap { doc -> AppCategory? in
                try? doc.data(as: AppCategory.self)
            }
            Task { @MainActor in onChange(categories) }
        }
    }

    func stopCategoryListener() {
        categoryListener?.remove()
        categoryListener = nil
    }

    func addCategory(_ category: AppCategory) async throws {
        let data = try Firestore.Encoder().encode(category)
        try await db.collection("categories").addDocument(data: data)
    }

    func updateCategory(id: String, updates: [String: Any]) async throws {
        try await db.collection("categories").document(id).updateData(updates)
    }

    func deleteCategory(id: String) async throws {
        try await db.collection("categories").document(id).delete()
    }

    /// Fetches all categories for a user (including system) as a one-shot read
    func fetchAllCategories(userId: String) async throws -> [AppCategory] {
        let snap = try await db.collection("categories")
            .whereField("userId", in: ["system", userId])
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AppCategory.self) }
    }

    /// Saves the default category tree to Firestore under userId.
    /// Parents are saved first; children reference the real Firestore doc IDs.
    /// Returns count of categories added (skips duplicates by name+type).
    @discardableResult
    func importDefaultCategories(userId: String, existing: [AppCategory]) async throws -> Int {
        let existingKeys = Set(existing.filter { $0.userId == userId }.map { "\($0.name)|\($0.type.rawValue)" })
        let defaults = AppCategory.makeDefaults()
        let parents = defaults.filter { $0.parentId == nil }
        var added = 0

        // Map: localId → real Firestore docId
        var localToFirestoreId: [String: String] = [:]

        for var parent in parents {
            let key = "\(parent.name)|\(parent.type.rawValue)"
            if existingKeys.contains(key) {
                // Already exists — find its Firestore ID for child linking
                if let existing = existing.first(where: { $0.name == parent.name && $0.type == parent.type && $0.parentId == nil }) {
                    if let fid = existing.firestoreId, let lid = parent.localId {
                        localToFirestoreId[lid] = fid
                    }
                }
                continue
            }
            parent.userId = userId
            let data = try Firestore.Encoder().encode(parent)
            let ref = try await db.collection("categories").addDocument(data: data)
            if let lid = parent.localId { localToFirestoreId[lid] = ref.documentID }
            added += 1
        }

        let children = defaults.filter { $0.parentId != nil }
        for var child in children {
            let key = "\(child.name)|\(child.type.rawValue)"
            if existingKeys.contains(key) { continue }
            guard let localParentId = child.parentId,
                  let firestoreParentId = localToFirestoreId[localParentId] else { continue }
            child.userId = userId
            child.parentId = firestoreParentId
            let data = try Firestore.Encoder().encode(child)
            try await db.collection("categories").addDocument(data: data)
            added += 1
        }
        return added
    }

    // MARK: - Account Settings

    func updateAccountSettings(accountId: String, userId: String, settings: BankAccountSettings) async throws {
        let data = try Firestore.Encoder().encode(settings)
        try await db.collection("users").document(userId)
            .collection("accountSettings").document(accountId)
            .setData(data, merge: true)
    }

    func subscribeAccountSettings(userId: String, onChange: @escaping ([String: BankAccountSettings]) -> Void) {
        accountSettingsListener?.remove()
        let ref = db.collection("users").document(userId).collection("accountSettings")

        accountSettingsListener = ref.addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else { return }
            var result: [String: BankAccountSettings] = [:]
            docs.forEach { doc in
                if let s = try? doc.data(as: BankAccountSettings.self) {
                    result[doc.documentID] = s
                }
            }
            Task { @MainActor in onChange(result) }
        }
    }

    // MARK: - Bank Sessions

    func saveBankSession(userId: String, session: [String: Any]) async throws {
        try await db.collection("users").document(userId)
            .collection("bank_sessions")
            .addDocument(data: session)
    }

    // MARK: - Manual Bank Accounts (CSV import)

    /// Fixed IDs for the Trade Republic manual account so we can find them across imports.
    static let manualTRDocId = "manual_trade_republic"

    /// Finds or creates a manual (non-Open-Banking) bank session and account for Trade Republic.
    /// Returns the bank account document ID to use as `accountId` on imported transactions.
    @discardableResult
    func findOrCreateManualTRAccount(userId: String) async throws -> String {
        let docId = FirestoreService.manualTRDocId
        let userRef = db.collection("users").document(userId)

        // ── Session ─────────────────────────────────────────────────────────
        let sessionRef = userRef.collection("bank_sessions").document(docId)
        let sessionSnap = try await sessionRef.getDocument()
        if !sessionSnap.exists {
            try await sessionRef.setData([
                "sessionId":       docId,
                "institutionName": "Trade Republic",
                "status":          "MANUAL",
                "isManual":        true,
                "createdAt":       ISO8601DateFormatter().string(from: Date()),
                "aspsp": ["name": "Trade Republic", "country": "EU"]
            ])
        }

        // ── Account ──────────────────────────────────────────────────────────
        let accountRef = userRef.collection("bank_accounts").document(docId)
        let accountSnap = try await accountRef.getDocument()
        if !accountSnap.exists {
            try await accountRef.setData([
                "id":              docId,
                "name":            "Trade Republic",
                "institutionName": "Trade Republic",
                "sessionId":       docId,
                "type":            "CACC",
                "currency":        "EUR",
                "isManual":        true,
                "balances":        []
            ])
        }

        return docId
    }

    func getBankSessions(userId: String) async throws -> [[String: Any]] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("bank_sessions")
            .getDocuments()
        return snapshot.documents.map { $0.data() }
    }

    func getBankSessionsTyped(userId: String) async throws -> [BankSession] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("bank_sessions")
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: BankSession.self) }
    }

    func updateBankSessionStatus(userId: String, sessionId: String, status: String) async throws {
        let snapshot = try await db.collection("users").document(userId)
            .collection("bank_sessions")
            .whereField("sessionId", isEqualTo: sessionId)
            .getDocuments()
        for doc in snapshot.documents {
            try await doc.reference.updateData(["status": status])
        }
    }

    func deleteBankSession(userId: String, sessionId: String) async throws {
        let snapshot = try await db.collection("users").document(userId)
            .collection("bank_sessions")
            .whereField("sessionId", isEqualTo: sessionId)
            .getDocuments()
        let batch = db.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    // MARK: - Bank Accounts (cached per user)

    func subscribeBankAccounts(userId: String, onChange: @escaping ([BankAccount]) -> Void) {
        bankAccountsListener?.remove()
        bankAccountsListener = db.collection("users").document(userId)
            .collection("bank_accounts")
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let accounts = docs.compactMap { doc -> BankAccount? in
                    if let a = try? doc.data(as: BankAccount.self) { return a }
                    if let raw = try? doc.data(as: RawFirestoreBankAccount.self) { return raw.toBankAccount(id: doc.documentID) }
                    return nil
                }
                Task { @MainActor in onChange(accounts) }
            }
    }

    func saveBankAccounts(userId: String, accounts: [[String: Any]]) async throws {
        // Fetch existing accounts to merge by IBAN — avoids duplicates when reconnecting sessions
        let existing: [BankAccount]
        do { existing = try await getBankAccounts(userId: userId) }
        catch { existing = [] }

        let batch = db.batch()
        for account in accounts {
            guard let id = account["id"] as? String else { continue }
            let iban = (account["officialName"] as? String) ?? ""

            // If an existing account already has the same IBAN, reuse its document ID
            // (this handles session reconnects where the API may return a different UID)
            let docId: String
            if !iban.isEmpty,
               let match = existing.first(where: { ($0.officialName ?? "").uppercased() == iban.uppercased() }) {
                docId = match.id
            } else {
                docId = id
            }

            let ref = db.collection("users").document(userId)
                .collection("bank_accounts").document(docId)
            batch.setData(account, forDocument: ref, merge: true)
        }
        try await batch.commit()
    }

    func getBankAccounts(userId: String) async throws -> [BankAccount] {
        let snapshot = try await db.collection("users").document(userId)
            .collection("bank_accounts")
            .getDocuments()
        return snapshot.documents.compactMap { doc -> BankAccount? in
            if let a = try? doc.data(as: BankAccount.self) { return a }
            if let raw = try? doc.data(as: RawFirestoreBankAccount.self) { return raw.toBankAccount(id: doc.documentID) }
            return nil
        }
    }

    // MARK: - Reset

    func resetUserData(userId: String) async throws {
        async let deleteTx: Void = deleteAllTransactions(userId: userId)
        async let deleteSessions: Void = deleteAllSubcollection(userId: userId, name: "bank_sessions")
        async let deleteAccounts: Void = deleteAllSubcollection(userId: userId, name: "bank_accounts")
        async let deleteSettings: Void = deleteAllSubcollection(userId: userId, name: "accountSettings")
        _ = try await (deleteTx, deleteSessions, deleteAccounts, deleteSettings)
    }

    private func deleteAllSubcollection(userId: String, name: String) async throws {
        let snapshot = try await db.collection("users").document(userId)
            .collection(name).getDocuments()
        let batch = db.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    // MARK: - Recurrings

    private var recurringsListener: ListenerRegistration?
    private var budgetsListener: ListenerRegistration?

    func subscribeRecurrings(userId: String, onChange: @escaping ([RecurringPayment]) -> Void) {
        recurringsListener?.remove()
        recurringsListener = db.collection("recurrings")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let items = docs.compactMap { try? $0.data(as: RecurringPayment.self) }
                DispatchQueue.main.async { onChange(items) }
            }
    }

    func stopRecurringsListener() { recurringsListener?.remove(); recurringsListener = nil }

    func addRecurring(_ recurring: RecurringPayment) async throws -> String {
        let data = try Firestore.Encoder().encode(recurring)
        let ref = try await db.collection("recurrings").addDocument(data: data)
        return ref.documentID
    }

    func updateRecurring(id: String, updates: [String: Any]) async throws {
        try await db.collection("recurrings").document(id).updateData(updates)
    }

    func deleteRecurring(id: String, userId: String) async throws {
        // Remove junction links first
        let links = try await db.collection("recurring_transaction_links")
            .whereField("recurringId", isEqualTo: id)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        let batch = db.batch()
        links.documents.forEach { batch.deleteDocument($0.reference) }
        batch.deleteDocument(db.collection("recurrings").document(id))
        try await batch.commit()
    }

    // MARK: - Budgets

    func subscribeBudgets(userId: String, onChange: @escaping ([Budget]) -> Void) {
        budgetsListener?.remove()
        budgetsListener = db.collection("budgets")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, _ in
                let items = snapshot?.documents.compactMap { try? $0.data(as: Budget.self) } ?? []
                DispatchQueue.main.async { onChange(items) }
            }
    }

    func stopBudgetsListener() { budgetsListener?.remove(); budgetsListener = nil }

    func addBudget(_ budget: Budget) async throws -> String {
        let data = try Firestore.Encoder().encode(budget)
        let ref = try await db.collection("budgets").addDocument(data: data)
        return ref.documentID
    }

    func updateBudget(id: String, updates: [String: Any]) async throws {
        try await db.collection("budgets").document(id).updateData(updates)
    }

    func deleteBudget(id: String) async throws {
        try await db.collection("budgets").document(id).delete()
    }

    // MARK: - Junction: recurring ↔ transaction links

    func linkTransaction(recurringId: String, transactionId: String, userId: String) async throws {
        // Upsert junction row
        let link = RecurringTransactionLink(userId: userId, recurringId: recurringId, transactionId: transactionId)
        let linkData = try Firestore.Encoder().encode(link)
        try await db.collection("recurring_transaction_links").addDocument(data: linkData)

        // Append to recurring's transactionIds array (denormalized for fast reads)
        try await db.collection("recurrings").document(recurringId)
            .updateData(["transactionIds": FieldValue.arrayUnion([transactionId])])

        // Tag transaction with recurringId
        try await db.collection("transactions").document(transactionId)
            .updateData(["recurringId": recurringId, "recurring": true])
    }

    func unlinkTransaction(recurringId: String, transactionId: String, userId: String) async throws {
        // Find and delete the junction row
        let links = try await db.collection("recurring_transaction_links")
            .whereField("recurringId", isEqualTo: recurringId)
            .whereField("transactionId", isEqualTo: transactionId)
            .getDocuments()
        let batch = db.batch()
        links.documents.forEach { batch.deleteDocument($0.reference) }
        // Remove from denormalized array
        let recRef = db.collection("recurrings").document(recurringId)
        batch.updateData(["transactionIds": FieldValue.arrayRemove([transactionId])], forDocument: recRef)
        // Untag transaction
        let txRef = db.collection("transactions").document(transactionId)
        batch.updateData(["recurringId": FieldValue.delete(), "recurring": false], forDocument: txRef)
        try await batch.commit()
    }

    func getLinkedTransactions(recurringId: String, userId: String) async throws -> [Transaction] {
        let links = try await db.collection("recurring_transaction_links")
            .whereField("recurringId", isEqualTo: recurringId)
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        let ids = links.documents.compactMap {
            try? $0.data(as: RecurringTransactionLink.self)
        }.map(\.transactionId)
        guard !ids.isEmpty else { return [] }
        // Firestore `in` supports up to 30 items per query
        let chunks = stride(from: 0, to: ids.count, by: 30).map { Array(ids[$0..<min($0+30, ids.count)]) }
        var result: [Transaction] = []
        for chunk in chunks {
            let snap = try await db.collection("transactions")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            result += snap.documents.compactMap { try? $0.data(as: Transaction.self) }
        }
        return result
    }

    func stopAllListeners() {
        transactionListener?.remove()
        categoryListener?.remove()
        accountSettingsListener?.remove()
        bankAccountsListener?.remove()
        recurringsListener?.remove()
        budgetsListener?.remove()
        transactionListener = nil
        categoryListener = nil
        accountSettingsListener = nil
        bankAccountsListener = nil
        recurringsListener = nil
        budgetsListener = nil
    }
}
