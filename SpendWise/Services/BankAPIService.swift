import Foundation

// Thin compatibility wrapper — delegates everything to EnableBankingService
// which calls api.enablebanking.com directly (no proxy server needed).

class BankAPIService {
    static let shared = BankAPIService()
    private let eb = EnableBankingService.shared
    private init() {}

    func verifyCredentials() async throws -> EBApplication {
        try await eb.verifyCredentials()
    }

    func getInstitutions(country: String = "IT") async throws -> [BankInstitution] {
        try await eb.getInstitutions(country: country)
    }

    func initiateLink(aspspName: String, country: String, redirectURL: String) async throws -> String {
        try await eb.initiateLink(aspspName: aspspName, country: country, redirectURL: redirectURL)
    }

    func exchangeCode(_ code: String) async throws -> EBSessionResponse {
        try await eb.exchangeCode(code)
    }

    func getSessionStatus(sessionId: String) async throws -> EBGetSessionResponse {
        try await eb.getSessionStatus(sessionId: sessionId)
    }

    func deleteSession(sessionId: String) async throws {
        try await eb.deleteSession(sessionId: sessionId)
    }

    func getAccounts(sessionToken: String? = nil) async throws -> [EBAccount] {
        try await eb.getAccounts(sessionToken: sessionToken)
    }

    func getBalances(accountId: String, sessionToken: String? = nil) async throws -> [EBBalance] {
        try await eb.getBalances(accountId: accountId, sessionToken: sessionToken)
    }

    func getTransactions(
        accountId: String,
        sessionToken: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        continuationKey: String? = nil,
        transactionStatus: String? = nil
    ) async throws -> EBTransactionsResponse {
        try await eb.getTransactions(
            accountId: accountId,
            sessionToken: sessionToken,
            dateFrom: dateFrom,
            dateTo: dateTo,
            continuationKey: continuationKey,
            transactionStatus: transactionStatus
        )
    }

    func getExchangeRate(date: String, from: String, to: String = "EUR") async throws -> Double {
        try await eb.getExchangeRate(date: date, from: from, to: to)
    }
}
