import Foundation
import Security
import OSLog

private let ebLog = Logger(subsystem: "com.kurozetsubou.spendwise", category: "EnableBanking")
// Replaces the Express proxy server by calling api.enablebanking.com directly.
// JWT RS256 signing is done on-device using the Security framework.

final class EnableBankingService {
    static let shared = EnableBankingService()
    private init() {}

    private let baseURL = "https://api.enablebanking.com"

    // JWT cache: appId → (token, expiry)
    private var jwtCache: [String: (token: String, exp: TimeInterval)] = [:]

    // MARK: - Credentials (from UserDefaults / Keychain)

    private var appId: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ebAppId) ?? ""
    }

    private var appSecret: String {
        UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.ebAppSecret) ?? ""
    }

    // MARK: - Public API

    func verifyCredentials() async throws -> EBApplication {
        let data = try await get("/application")
        return try JSONDecoder().decode(EBApplication.self, from: data)
    }

    func getInstitutions(country: String = "IT") async throws -> [BankInstitution] {
        let data = try await get("/aspsps?country=\(country)")
        let wrapper = try JSONDecoder().decode(ASPSPWrapper.self, from: data)
        return wrapper.aspsps
    }

    func initiateLink(aspspName: String, country: String, redirectURL: String) async throws -> String {
        let validUntil = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(10 * 24 * 3600)
        )
        let body: [String: Any] = [
            "aspsp": ["name": aspspName, "country": country],
            "access": ["valid_until": validUntil],
            "redirect_url": redirectURL,
            "state": "spendwise-\(Int(Date().timeIntervalSince1970))",
            "psu_type": "personal"
        ]
        let data = try await post("/auth", body: body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let url = json?["url"] as? String else {
            throw EBError.invalidResponse("Missing url in /auth response")
        }
        return url
    }

    func exchangeCode(_ code: String) async throws -> EBSessionResponse {
        let body: [String: Any] = ["code": code]
        let data = try await post("/sessions", body: body)
        return try JSONDecoder().decode(EBSessionResponse.self, from: data)
    }

    func getSessionStatus(sessionId: String) async throws -> EBGetSessionResponse {
        let data = try await get("/sessions/\(sessionId)")
        return try JSONDecoder().decode(EBGetSessionResponse.self, from: data)
    }

    func deleteSession(sessionId: String) async throws {
        _ = try await delete("/sessions/\(sessionId)")
    }

    func getAccounts(sessionToken: String? = nil) async throws -> [EBAccount] {
        let data = try await get("/accounts", sessionToken: sessionToken)
        let wrapper = try JSONDecoder().decode(AccountsWrapper.self, from: data)
        return wrapper.accounts
    }

    func getAccountDetails(accountId: String, sessionToken: String? = nil) async throws -> EBAccount {
        let data = try await get("/accounts/\(accountId)", sessionToken: sessionToken)
        return try JSONDecoder().decode(EBAccount.self, from: data)
    }

    func getBalances(accountId: String, sessionToken: String? = nil) async throws -> [EBBalance] {
        let data = try await get("/accounts/\(accountId)/balances", sessionToken: sessionToken)
        let wrapper = try JSONDecoder().decode(BalancesWrapper.self, from: data)
        return wrapper.balances
    }

    func getTransactions(
        accountId: String,
        sessionToken: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        continuationKey: String? = nil,
        transactionStatus: String? = nil
    ) async throws -> EBTransactionsResponse {
        var components = URLComponents(string: "\(baseURL)/accounts/\(accountId)/transactions")!
        var queryItems: [URLQueryItem] = []
        if let continuationKey {
            queryItems.append(URLQueryItem(name: "continuation_key", value: continuationKey))
        } else {
            if let dateFrom { queryItems.append(URLQueryItem(name: "date_from", value: dateFrom)) }
            if let dateTo   { queryItems.append(URLQueryItem(name: "date_to",   value: dateTo))   }
        }
        if let transactionStatus {
            queryItems.append(URLQueryItem(name: "transaction_status", value: transactionStatus))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        let data = try await request(url: components.url!, method: "GET", sessionToken: sessionToken)
        return try JSONDecoder().decode(EBTransactionsResponse.self, from: data)
    }

    // MARK: - Exchange Rate (Frankfurter — no auth needed)

    func getExchangeRate(date: String, from: String, to: String = "EUR") async throws -> Double {
        let url = URL(string: "https://api.frankfurter.app/\(date)?from=\(from)&to=\(to)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return 1.0 }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rates = json?["rates"] as? [String: Double]
        return rates?[to] ?? 1.0
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String, sessionToken: String? = nil) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        return try await request(url: url, method: "GET", sessionToken: sessionToken)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        return try await request(url: url, method: "POST", body: body)
    }

    private func delete(_ path: String) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        return try await request(url: url, method: "DELETE")
    }

    private func request(
        url: URL,
        method: String,
        body: [String: Any]? = nil,
        sessionToken: String? = nil
    ) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Authorization
        let token = try sessionToken.map { $0 } ?? (try buildAppJWT())
        let bearer = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
        req.setValue(bearer, forHTTPHeaderField: "Authorization")

        // PSU headers (required by Enable Banking)
        req.setValue("0.0.0.0", forHTTPHeaderField: "psu-ip-address")
        req.setValue("SpendWise/1.0 iOS", forHTTPHeaderField: "psu-user-agent")

        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            if let bodyStr = String(data: req.httpBody!, encoding: .utf8) {
                ebLog.debug("📤 \(method) \(url.path) body: \(bodyStr)")
            }
        }

        ebLog.info("➡️ \(method) \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            ebLog.error("❌ \(method) \(url.path) — no HTTP response")
            throw EBError.networkError("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            ebLog.error("❌ \(method) \(url.path) → HTTP \(http.statusCode): \(msg)")
            throw EBError.apiError(http.statusCode, msg)
        }
        ebLog.info("✅ \(method) \(url.path) → HTTP \(http.statusCode) (\(data.count) bytes)")
        if let pretty = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: pretty, options: .prettyPrinted),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            ebLog.debug("📦 Response body:\n\(prettyStr)")
        }
        return data
    }

    // MARK: - JWT RS256 Builder

    private func buildAppJWT() throws -> String {
        guard !appId.isEmpty, !appSecret.isEmpty else {
            ebLog.error("❌ Missing Enable Banking credentials (appId or private key empty)")
            throw EBError.missingCredentials
        }

        let now = Date().timeIntervalSince1970
        // Return cached token if still valid (60s buffer)
        if let cached = jwtCache[appId], cached.exp > now + 60 {
            ebLog.debug("🔑 Using cached JWT for appId=\(self.appId)")
            return cached.token
        }

        let iat = Int(now) - 30
        let exp = Int(now) + 3600
        let jti = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        let header: [String: Any] = ["alg": "RS256", "kid": appId]
        let payload: [String: Any] = [
            "iss": "enablebanking.com",
            "aud": "api.enablebanking.com",
            "iat": iat,
            "exp": exp,
            "jti": jti
        ]

        let token = try RSA256JWT.sign(header: header, payload: payload, pem: appSecret)
        ebLog.info("🔑 JWT built for appId=\(self.appId), exp=\(exp)")
        jwtCache[appId] = (token, TimeInterval(exp))
        return token
    }
}

// MARK: - RSA-256 JWT Signer

private enum RSA256JWT {
    static func sign(header: [String: Any], payload: [String: Any], pem: String) throws -> String {
        let hData = try JSONSerialization.data(withJSONObject: header, options: .sortedKeys)
        let pData = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
        let signingInput = "\(b64url(hData)).\(b64url(pData))"

        guard let inputData = signingInput.data(using: .utf8) else {
            throw EBError.jwtError("Cannot encode signing input")
        }

        let key = try importRSAPrivateKey(pem: pem)

        var cfError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            inputData as CFData,
            &cfError
        ) as Data? else {
            let msg = cfError.map { ($0.takeRetainedValue() as Error).localizedDescription } ?? "Unknown"
            throw EBError.jwtError("Signing failed: \(msg)")
        }

        return "\(signingInput).\(b64url(signature))"
    }

    private static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func importRSAPrivateKey(pem: String) throws -> SecKey {
        // Normalize all whitespace variants and escaped newlines
        let normalized = pem
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Detect key type from any header present (even on a single line)
        let isEC    = normalized.contains("BEGIN EC PRIVATE KEY")
        let isPKCS8 = normalized.contains("BEGIN PRIVATE KEY")   // not EC
        let isPKCS1 = normalized.contains("BEGIN RSA PRIVATE KEY")
        ebLog.info("🔐 PEM format: PKCS8=\(isPKCS8) PKCS1=\(isPKCS1) EC=\(isEC)")

        // Extract base64 payload between any -----BEGIN...----- and -----END...----- markers
        // Works whether stored as multiline or as a single space-separated string
        let pattern = #"-----BEGIN [^-]+-----\s*([\s\S]+?)\s*-----END [^-]+-----"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let b64Range = Range(match.range(at: 1), in: normalized)
        else {
            ebLog.error("❌ Cannot find PEM markers in key string (length=\(pem.count))")
            throw EBError.jwtError("Cannot parse PEM: missing BEGIN/END markers")
        }

        // Remove all whitespace from base64 payload
        let b64 = String(normalized[b64Range])
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        ebLog.info("🔐 Base64 payload length: \(b64.count) chars")

        guard var keyData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
              !keyData.isEmpty else {
            ebLog.error("❌ Cannot base64-decode private key (b64 length=\(b64.count))")
            throw EBError.jwtError("Cannot base64-decode private key")
        }

        ebLog.info("🔐 DER size before strip: \(keyData.count) bytes — first: \(keyData.prefix(4).map { String(format: "%02x", $0) }.joined(separator: " "))")

        if isPKCS8 {
            do {
                keyData = try stripPKCS8Header(keyData)
                ebLog.info("🔐 After PKCS#8 strip: \(keyData.count) bytes — first: \(keyData.prefix(4).map { String(format: "%02x", $0) }.joined(separator: " "))")
            } catch {
                ebLog.error("❌ PKCS#8 strip failed: \(error.localizedDescription)")
                throw error
            }
        }

        if keyData.first != 0x30 {
            ebLog.error("❌ Key doesn't start with SEQUENCE (0x30). Got: 0x\(String(format: "%02x", keyData.first ?? 0))")
        }

        let keyType = isEC ? kSecAttrKeyTypeEC : kSecAttrKeyTypeRSA
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: keyType,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var cfError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &cfError) else {
            let msg = cfError.map { ($0.takeRetainedValue() as Error).localizedDescription } ?? "Unknown"
            ebLog.error("❌ SecKeyCreateWithData failed: \(msg) — keySize=\(keyData.count)")
            throw EBError.jwtError("Cannot create SecKey: \(msg)")
        }
        ebLog.info("✅ SecKey created successfully (type=\(isEC ? "EC" : "RSA"), size=\(keyData.count))")
        return key
    }

    /// Extracts RSAPrivateKey from PKCS#8 DER wrapper via minimal ASN.1 parsing.
    private static func stripPKCS8Header(_ der: Data) throws -> Data {
        var bytes = Array(der)
        var idx = 0
        ebLog.debug("🔐 stripPKCS8Header: input \(der.count) bytes")

        func readTag() throws -> UInt8 {
            guard idx < bytes.count else { throw EBError.jwtError("ASN.1 parse: unexpected end") }
            let t = bytes[idx]; idx += 1; return t
        }

        func readLength() throws -> Int {
            guard idx < bytes.count else { throw EBError.jwtError("ASN.1 parse: unexpected end") }
            let first = bytes[idx]; idx += 1
            if first < 0x80 { return Int(first) }
            let numBytes = Int(first & 0x7F)
            guard idx + numBytes <= bytes.count else { throw EBError.jwtError("ASN.1 parse: length overflow") }
            var len = 0
            for _ in 0..<numBytes { len = (len << 8) | Int(bytes[idx]); idx += 1 }
            return len
        }

        // SEQUENCE (outer)
        let outerTag = try readTag()
        guard outerTag == 0x30 else {
            ebLog.error("❌ PKCS#8: expected outer SEQUENCE (0x30), got 0x\(String(format: "%02x", outerTag))")
            throw EBError.jwtError("PKCS#8: expected outer SEQUENCE")
        }
        let outerLen = try readLength()
        ebLog.debug("🔐 outer SEQUENCE len=\(outerLen) at idx=\(idx)")

        // INTEGER (version = 0) — PKCS#8 has this before AlgorithmIdentifier
        let versionTag = try readTag()
        guard versionTag == 0x02 else {
            ebLog.error("❌ PKCS#8: expected version INTEGER (0x02), got 0x\(String(format: "%02x", versionTag))")
            throw EBError.jwtError("PKCS#8: expected version INTEGER")
        }
        let versionLen = try readLength()
        idx += versionLen // skip version bytes
        ebLog.debug("🔐 version INTEGER len=\(versionLen), skipped")

        // SEQUENCE (AlgorithmIdentifier)
        let algTag = try readTag()
        guard algTag == 0x30 else {
            ebLog.error("❌ PKCS#8: expected AlgorithmIdentifier SEQUENCE (0x30), got 0x\(String(format: "%02x", algTag))")
            throw EBError.jwtError("PKCS#8: expected AlgorithmIdentifier SEQUENCE")
        }
        let algLen = try readLength()
        ebLog.debug("🔐 AlgorithmIdentifier len=\(algLen) at idx=\(idx), skipping")
        idx += algLen // skip algorithm identifier

        // OCTET STRING (contains RSAPrivateKey)
        let octetTag = try readTag()
        guard octetTag == 0x04 else {
            ebLog.error("❌ PKCS#8: expected OCTET STRING (0x04), got 0x\(String(format: "%02x", octetTag)) at idx=\(idx)")
            throw EBError.jwtError("PKCS#8: expected OCTET STRING")
        }
        let keyLen = try readLength()
        guard idx + keyLen <= bytes.count else {
            ebLog.error("❌ PKCS#8: key data truncated (need \(keyLen), have \(bytes.count - idx))")
            throw EBError.jwtError("PKCS#8: key data truncated")
        }
        ebLog.debug("🔐 inner RSAPrivateKey at idx=\(idx), len=\(keyLen)")
        return Data(bytes[idx..<idx + keyLen])
    }
}

// MARK: - Response Models

struct EBApplication: Codable {
    var name: String?
    var environment: String?
    var certificate_expiry: String?
}

struct EBSessionResponse: Codable {
    var access_token: String?
    var session_id: String?
    var accounts: [EBAccount]?
}

struct EBGetSessionResponse: Codable {
    var session_id: String?
    var status: String?         // e.g. "AUTHORIZED", "EXPIRED", "REVOKED"
    var aspsp: EBAspsp?
    var valid_until: String?
    var accounts: [EBAccount]?
    var expires_at: String?

    struct EBAspsp: Codable {
        var name: String?
        var country: String?
    }

    var isExpired: Bool {
        guard let status else { return false }
        let upper = status.uppercased()
        return upper == "EXPIRED" || upper == "REVOKED" || upper == "UNAUTHORIZED"
    }
}

struct EBAccount: Codable, Identifiable {
    var uid: String?
    var account_id: AccountId?
    var name: String?
    var details: String?
    var product: String?
    var cash_account_type: String?
    var currency: String?
    var balances: [EBBalance]?

    struct AccountId: Codable {
        var iban: String?
    }

    var id: String { uid ?? UUID().uuidString }
    var displayName: String { name ?? account_id?.iban ?? id }
}

struct EBBalance: Codable {
    var name: String?
    var balance_amount: BalanceAmount?
    var balance_type: String?

    struct BalanceAmount: Codable {
        var amount: String?
        var currency: String?
    }

    var amountDouble: Double {
        Double(balance_amount?.amount ?? "0") ?? 0
    }
    var currency: String { balance_amount?.currency ?? "EUR" }
}

struct EBTransactionsResponse: Codable {
    var transactions: [EBTransaction]?
    var continuation_key: String?
}

struct EBTransaction: Codable {
    var transaction_id: String?
    var entry_reference: String?
    var transaction_amount: TransactionAmount?
    var booking_date: String?
    var value_date: String?
    var transaction_date: String?
    var remittance_information_unstructured: String?
    var merchant_name: String?
    var debtor_name: String?
    var creditor_name: String?
    var purpose_code: String?

    struct TransactionAmount: Codable {
        var amount: String?
        var currency: String?
    }

    var amountDouble: Double { Double(transaction_amount?.amount ?? "0") ?? 0 }
    var currency: String { transaction_amount?.currency ?? "EUR" }
    var description: String {
        remittance_information_unstructured
        ?? merchant_name
        ?? creditor_name
        ?? debtor_name
        ?? "Transazione"
    }
    var date: String { value_date ?? booking_date ?? transaction_date ?? "" }
    var id: String { transaction_id ?? entry_reference ?? UUID().uuidString }
}

struct ASPSPWrapper: Codable { var aspsps: [BankInstitution] }
struct AccountsWrapper: Codable { var accounts: [EBAccount] }
struct BalancesWrapper: Codable { var balances: [EBBalance] }

// MARK: - Errors

enum EBError: LocalizedError {
    case missingCredentials
    case jwtError(String)
    case apiError(Int, String)
    case invalidResponse(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Credenziali Enable Banking mancanti. Vai in Impostazioni."
        case .jwtError(let msg):
            return "Errore JWT: \(msg)"
        case .apiError(let code, let msg):
            return "Errore API (\(code)): \(msg)"
        case .invalidResponse(let msg):
            return "Risposta non valida: \(msg)"
        case .networkError(let msg):
            return "Errore di rete: \(msg)"
        }
    }
}
