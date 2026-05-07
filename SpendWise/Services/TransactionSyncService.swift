import Foundation
import FirebaseFirestore
import OSLog

private let syncLog = Logger(subsystem: "com.kurozetsubou.spendwise", category: "TransactionSync")

/// Syncs bank transactions from Enable Banking API to Firestore.
/// Deduplicates via deterministic doc ID `bank_{bankTransactionId}`.
/// Handles pagination (continuation_key), currency conversion, and giroconto detection.
@MainActor
class TransactionSyncService {
    static let shared = TransactionSyncService()
    private let bankService = BankAPIService.shared
    private let firestoreService = FirestoreService.shared

    private init() {}

    struct SyncResult {
        var imported: Int = 0
        var skipped: Int = 0
        var errors: [String] = []
        var accountsProcessed: Int = 0
    }

    struct SyncProgress {
        var currentAccount: String = ""
        var accountIndex: Int = 0
        var totalAccounts: Int = 0
        var transactionsImported: Int = 0
        var currentPage: Int = 0
    }

    /// Sync all transactions for all connected bank sessions
    func syncAll(
        userId: String,
        days: Int = 30,
        disabledAccountIds: Set<String> = [],
        onProgress: ((SyncProgress) -> Void)? = nil
    ) async -> SyncResult {
        var result = SyncResult()

        let sessions: [[String: Any]]
        do {
            sessions = try await firestoreService.getBankSessions(userId: userId)
        } catch {
            result.errors.append("Errore caricamento sessioni: \(error.localizedDescription)")
            return result
        }

        syncLog.info("🔄 Starting sync: \(sessions.count) sessions, \(days) days back")
        let dateFrom = dateString(daysAgo: days)

        for session in sessions {
            let token = session["accessToken"] as? String
            let sessionId = session["sessionId"] as? String
            let aspspName = (session["aspsp"] as? [String: Any])?["name"] as? String ?? "Banca"
            let firestoreStatus = session["status"] as? String ?? ""

            syncLog.info("📋 Session: \(aspspName), firestoreStatus=\(firestoreStatus)")

            // Skip already-known non-authorized sessions
            let knownBadStatuses = ["EXPIRED", "REVOKED", "UNAUTHORIZED", "DELETED"]
            if knownBadStatuses.contains(firestoreStatus.uppercased()) {
                result.errors.append("⚠️ \(aspspName): sessione scaduta (riconnetti la banca)")
                continue
            }

            // Verify real-time status with Enable Banking API (catches silently-expired sessions)
            if let sessionId {
                do {
                    let liveStatus = try await bankService.getSessionStatus(sessionId: sessionId)
                    syncLog.info("📡 Live session status for \(aspspName): \(liveStatus.status ?? "?")")
                    if liveStatus.isExpired {
                        // Update Firestore so the UI shows the reconnect button
                        try? await firestoreService.updateBankSessionStatus(userId: userId, sessionId: sessionId, status: "EXPIRED")
                        result.errors.append("⏰ \(aspspName): sessione scaduta — riconnetti la banca dall'app")
                        continue
                    }
                } catch {
                    syncLog.warning("⚠️ Couldn't verify session status for \(aspspName): \(error.localizedDescription)")
                    // Don't abort; try the sync anyway
                }
            }

            // Use the effective token: accessToken from session, or nil (App JWT fallback)
            let effectiveToken: String? = (token != nil && !token!.isEmpty) ? token : nil

            // Get accounts: prefer the accounts array stored in the session doc,
            // otherwise try fetching from Enable Banking API
            var accountIds: [(id: String, name: String)] = []

            if let sessionAccounts = session["accounts"] as? [[String: Any]] {
                for acc in sessionAccounts {
                    let uid = acc["uid"] as? String
                        ?? acc["resourceId"] as? String
                        ?? (acc["account_id"] as? [String: Any])?["iban"] as? String
                    if let uid {
                        let name = acc["name"] as? String
                            ?? (acc["account_id"] as? [String: Any])?["iban"] as? String
                            ?? uid
                        accountIds.append((id: uid, name: name))
                    }
                }
            }

            // Fallback: fetch from API if no accounts in session doc
            if accountIds.isEmpty {
                syncLog.info("📡 No accounts in session doc, fetching from API...")
                do {
                    let ebAccounts = try await bankService.getAccounts(sessionToken: effectiveToken)
                    accountIds = ebAccounts.map { (id: $0.id, name: $0.displayName) }
                } catch let error as EBError {
                    if isExpiredSessionError(error) {
                        if let sessionId {
                            try? await firestoreService.updateBankSessionStatus(userId: userId, sessionId: sessionId, status: "EXPIRED")
                        }
                        result.errors.append("⏰ \(aspspName): sessione scaduta — riconnetti la banca dall'app")
                    } else {
                        result.errors.append("\(aspspName): \(error.localizedDescription)")
                    }
                    continue
                } catch {
                    result.errors.append("\(aspspName): \(error.localizedDescription)")
                    continue
                }
            }

            syncLog.info("💳 Found \(accountIds.count) accounts for \(aspspName): \(accountIds.map { $0.name }.joined(separator: ", "))")

            for (accountIndex, account) in accountIds.enumerated() {
                // Skip accounts where sync has been disabled in settings
                if disabledAccountIds.contains(account.id) {
                    syncLog.info("⏭ Skipping \(account.name) — sync disabled in account settings")
                    continue
                }

                onProgress?(SyncProgress(
                    currentAccount: account.name,
                    accountIndex: accountIndex,
                    totalAccounts: accountIds.count,
                    transactionsImported: result.imported,
                    currentPage: 0
                ))

                do {
                    let imported = try await syncAccountTransactions(
                        userId: userId,
                        accountId: account.id,
                        sessionToken: effectiveToken,
                        dateFrom: dateFrom,
                        accountSessionId: sessionId,
                        onProgress: { page, total in
                            onProgress?(SyncProgress(
                                currentAccount: account.name,
                                accountIndex: accountIndex,
                                totalAccounts: accountIds.count,
                                transactionsImported: result.imported + total,
                                currentPage: page
                            ))
                        }
                    )
                    result.imported += imported
                    result.accountsProcessed += 1
                } catch let error as EBError {
                    if isExpiredSessionError(error) {
                        if let sessionId {
                            try? await firestoreService.updateBankSessionStatus(userId: userId, sessionId: sessionId, status: "EXPIRED")
                        }
                        result.errors.append("⏰ \(aspspName): sessione scaduta — riconnetti la banca dall'app")
                        break  // No point trying other accounts in the same session
                    } else {
                        result.errors.append("\(account.name): \(error.localizedDescription)")
                    }
                } catch {
                    result.errors.append("\(account.name): \(error.localizedDescription)")
                }
            }
        }

        return result
    }

    /// Sync transactions for a single bank account
    func syncAccountTransactions(
        userId: String,
        accountId: String,
        sessionToken: String? = nil,
        dateFrom: String,
        accountSessionId: String? = nil,
        maxTransactions: Int = 1000,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> Int {
        var continuationKey: String? = nil
        var totalImported = 0
        var page = 0

        repeat {
            let response = try await bankService.getTransactions(
                accountId: accountId,
                sessionToken: sessionToken,
                dateFrom: continuationKey == nil ? dateFrom : nil,
                continuationKey: continuationKey
            )

            let txs = response.transactions ?? []
            continuationKey = response.continuation_key
            page += 1

            for ebTx in txs {
                let transaction = try await mapTransaction(
                    ebTx: ebTx,
                    userId: userId,
                    accountId: accountId
                )
                try await firestoreService.addTransaction(transaction)
                totalImported += 1
            }

            onProgress?(page, totalImported)

            if totalImported >= maxTransactions { break }
        } while continuationKey != nil

        return totalImported
    }

    // MARK: - Mapping

    private func mapTransaction(
        ebTx: EBTransaction,
        userId: String,
        accountId: String
    ) async throws -> Transaction {
        let rawAmount = ebTx.amountDouble
        let currency = ebTx.currency
        let isDebit = rawAmount < 0
        let txType: Transaction.TransactionType = isDebit ? .expense : .income
        let absAmount = abs(rawAmount)

        // Build description from available fields
        var description = ebTx.remittance_information_unstructured ?? ""
        let counterParty = isDebit
            ? ebTx.creditor_name
            : ebTx.debtor_name
        if let cp = counterParty, !cp.isEmpty {
            description = description.isEmpty ? cp : "\(cp) - \(description)"
        }
        if let merchant = ebTx.merchant_name, !merchant.isEmpty, !description.contains(merchant) {
            description = description.isEmpty ? merchant : "\(merchant) - \(description)"
        }
        if description.isEmpty { description = "Transazione bancaria" }

        // Giroconto detection
        let girocontoKeywords = ["giroconto", "girofondo", "storno", "trasferimento", "bonifico interno"]
        let isGiroconto = girocontoKeywords.contains(where: { description.lowercased().contains($0) })

        // Currency conversion
        var finalAmount = absAmount
        var exchangeRate: Double? = nil
        var originalAmount: Double? = nil
        var originalCurrency: String? = nil

        if currency != "EUR" {
            let txDate = ebTx.date
            let rate = try await bankService.getExchangeRate(date: String(txDate.prefix(10)), from: currency)
            finalAmount = absAmount * rate
            exchangeRate = rate
            originalAmount = absAmount
            originalCurrency = currency
        }

        // Transaction ID for dedup
        let bankTxId = ebTx.transaction_id
            ?? ebTx.entry_reference
            ?? "det_\(accountId)_\(ebTx.date)_\(rawAmount)_\(String(description.prefix(20)))"

        return Transaction(
            userId: userId,
            amount: finalAmount,
            type: txType,
            category: isGiroconto ? "Giroconto" : "Altro",
            description: description,
            date: ebTx.date,
            bookingDate: ebTx.booking_date,
            transactionDate: ebTx.transaction_date,
            bankTransactionId: bankTxId,
            accountId: accountId,
            originalAmount: originalAmount,
            originalCurrency: originalCurrency,
            exchangeRate: exchangeRate,
            isInternalTransfer: isGiroconto ? true : nil
        )
    }

    // MARK: - Helpers

    private func isExpiredSessionError(_ error: EBError) -> Bool {
        if case .apiError(let code, let body) = error {
            let upper = body.uppercased()
            return upper.contains("EXPIRED_SESSION") || upper.contains("SESSION_EXPIRED")
                || upper.contains("REVOKED") || (code == 403 && upper.contains("SESSION"))
        }
        return false
    }

    private func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
