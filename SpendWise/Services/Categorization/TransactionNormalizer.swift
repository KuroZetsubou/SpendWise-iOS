import Foundation
import CryptoKit

// MARK: - Normalized Transaction

struct NormalizedTx {
    let fingerprint: String
    let canonicalText: String
    let description: String
    let amount: Double
    let direction: String?   // "CRDT" | "DBIT"
    let creditorName: String?
    let debtorName: String?
    let creditorIban: String?
    let debtorIban: String?
    let bankCode: String?

    var isCredit: Bool { direction == "CRDT" }
    var counterpartyName: String? { isCredit ? debtorName : creditorName }
    var counterpartyIban: String? { isCredit ? debtorIban : creditorIban }
}

// MARK: - Normalizer

enum TransactionNormalizer {

    /// Normalize text: lowercase, strip accents, collapse spaces
    static func normalize(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return value
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "*", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Extract meaningful tokens (length > 1)
    static func tokens(_ text: String) -> Set<String> {
        Set(normalize(text).split(separator: " ").map(String.init).filter { $0.count > 1 })
    }

    /// Jaccard similarity between two canonical texts
    static func jaccard(_ a: String, _ b: String) -> Double {
        let setA = tokens(a)
        let setB = tokens(b)
        guard !setA.isEmpty || !setB.isEmpty else { return 1 }
        guard !setA.isEmpty && !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }

    /// SHA-256 fingerprint (hex, first 20 chars = enough for a key)
    static func fingerprint(amount: Double, direction: String?, canonicalText: String) -> String {
        let base = "\(String(format: "%.2f", amount))|\(direction ?? "")|\(canonicalText)"
        let digest = SHA256.hash(data: Data(base.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Build a NormalizedTx from a plain Transaction
    static func normalize(transaction tx: Transaction) -> NormalizedTx {
        let desc = normalize(tx.description)
        let canonical = desc
        let direction: String? = tx.type == .income ? "CRDT" : "DBIT"
        let fp = fingerprint(amount: tx.amount, direction: direction, canonicalText: canonical)
        return NormalizedTx(
            fingerprint: fp,
            canonicalText: canonical,
            description: desc,
            amount: tx.amount,
            direction: direction,
            creditorName: nil,
            debtorName: nil,
            creditorIban: nil,
            debtorIban: nil,
            bankCode: nil
        )
    }

    /// Build a NormalizedTx from a raw bank transaction (EBTransaction)
    static func normalize(ebTransaction tx: EBTransaction, direction: String? = nil) -> NormalizedTx {
        let remittance = tx.remittance_information?.joined(separator: " | ")
        let parts: [String?] = [
            remittance,
            tx.note,
            tx.bank_transaction_code?.description,
            tx.creditor?.name,
            tx.debtor?.name
        ]
        let raw = parts.compactMap { $0 }.joined(separator: " | ")
        let canonical = normalize(raw)
        let dir = direction ?? (tx.amountDouble >= 0 ? "CRDT" : "DBIT")
        let fp = fingerprint(amount: abs(tx.amountDouble), direction: dir, canonicalText: canonical)
        return NormalizedTx(
            fingerprint: fp,
            canonicalText: canonical,
            description: raw,
            amount: abs(tx.amountDouble),
            direction: dir,
            creditorName: tx.creditor?.name,
            debtorName: tx.debtor?.name,
            creditorIban: nil,
            debtorIban: nil,
            bankCode: nil
        )
    }
}

// MARK: - Transfer Detection

private let transferKeywords = [
    "giroconto", "trasferimento", "bonifico", "top up", "topup",
    "ricarica", "revolut", "paypal", "apple pay", "satispay", "wise"
]

enum TransferDetector {
    static func detect(tx: NormalizedTx, allTxs: [NormalizedTx], ownedIbans: Set<String>) -> (isPotential: Bool, confidence: Double, reason: String) {
        var score = 0.0
        var reasons: [String] = []

        let hasKeyword = transferKeywords.contains { tx.canonicalText.contains($0) }
        if hasKeyword { score += 0.35; reasons.append("keyword") }

        if let iban = tx.creditorIban, ownedIbans.contains(iban) { score += 0.4; reasons.append("own_creditor_iban") }
        if let iban = tx.debtorIban,   ownedIbans.contains(iban) { score += 0.4; reasons.append("own_debtor_iban") }

        // Look for matching counterpart (same amount, opposite direction, within ±3 days)
        let counterpartFound = allTxs.contains { c in
            c.fingerprint != tx.fingerprint
            && c.direction != tx.direction
            && abs(c.amount - tx.amount) < 0.01
            && transferKeywords.contains(where: { c.canonicalText.contains($0) })
        }
        if counterpartFound { score += 0.35; reasons.append("counterpart") }

        return (score >= 0.5, min(score, 0.99), reasons.joined(separator: ", "))
    }
}
