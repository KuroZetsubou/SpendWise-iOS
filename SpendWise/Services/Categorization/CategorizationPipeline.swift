import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

private let catLog = Logger(subsystem: "com.kurozetsubou.spendwise", category: "Categorization")

// MARK: - Result

struct CategorizationResult {
    var category: String
    var confidence: Double
    var isInternalTransfer: Bool
    var needsReview: Bool
    var shortReason: String
    var source: String  // "memory.exact" | "rule.transfer" | "memory.similar" | "ai.apple" | "rule.heuristic"
}

// MARK: - Category Map (web-app compatible keys → display names)

struct CategoryMap {
    /// Maps the canonical key (e.g. "expense.food") to the AppCategory name used in the app
    static let mapping: [String: String] = [
        "income.salary":           "Stipendio",
        "income.refund":           "Rimborso",
        "income.other":            "Altre Entrate",
        "expense.groceries":       "Spesa",
        "expense.food":            "Ristoranti",
        "expense.transport":       "Trasporti",
        "expense.shopping":        "Shopping",
        "expense.bills":           "Bollette",
        "expense.health":          "Salute",
        "expense.entertainment":   "Intrattenimento",
        "expense.cash_withdrawal": "Prelievo",
        "expense.fees":            "Commissioni",
        "transfer.internal":       "Giroconto",
        "transfer.external":       "Trasferimento",
        "uncategorized":           "Altro"
    ]

    static func displayName(for key: String, availableCategories: [String]) -> String {
        // First try exact mapping
        if let mapped = mapping[key], availableCategories.contains(mapped) { return mapped }
        // Try case-insensitive match against available
        let lower = key.lowercased()
        if let match = availableCategories.first(where: { $0.lowercased() == lower }) { return match }
        // Partial match (e.g. "food" → "Ristoranti")
        if let match = availableCategories.first(where: { lower.contains($0.lowercased()) || $0.lowercased().contains(lower) }) { return match }
        return availableCategories.first ?? "Altro"
    }
}

// MARK: - Categorization Pipeline

@MainActor
final class CategorizationPipeline {
    static let shared = CategorizationPipeline()
    private init() {}

    private var memoryStore: CategorizationMemoryStore?

    func prepare(userId: String) async {
        let store = CategorizationMemoryStore(userId: userId)
        await store.load()
        self.memoryStore = store
    }

    // MARK: - Main entry point

    func categorize(
        description: String,
        amount: Double,
        type: Transaction.TransactionType,
        availableCategories: [String],
        allTransactions: [Transaction] = []
    ) async -> CategorizationResult {
        let direction: String = type == .income ? "CRDT" : "DBIT"
        let canonical = TransactionNormalizer.normalize(description)
        let fingerprint = TransactionNormalizer.fingerprint(amount: amount, direction: direction, canonicalText: canonical)

        catLog.info("🔍 Categorizing: '\(description)' €\(amount) [\(direction)]")

        // STEP 1: Exact memory match
        if let exact = memoryStore?.findExact(fingerprint) {
            catLog.info("✅ Step 1 — Exact memory hit: \(exact.category)")
            return CategorizationResult(
                category: CategoryMap.displayName(for: exact.category, availableCategories: availableCategories),
                confidence: exact.confidence,
                isInternalTransfer: exact.isInternalTransfer,
                needsReview: exact.needsReview,
                shortReason: exact.shortReason,
                source: "memory.exact"
            )
        }

        // STEP 2: Transfer detection
        let normalizedAll = allTransactions.map { TransactionNormalizer.normalize(transaction: $0) }
        let ownedIbans: Set<String> = [] // TODO: populate from bank accounts
        let tx = NormalizedTx(
            fingerprint: fingerprint, canonicalText: canonical,
            description: canonical, amount: amount, direction: direction,
            creditorName: nil, debtorName: nil,
            creditorIban: nil, debtorIban: nil, bankCode: nil
        )
        let transfer = TransferDetector.detect(tx: tx, allTxs: normalizedAll, ownedIbans: ownedIbans)
        if transfer.isPotential {
            catLog.info("✅ Step 2 — Transfer detected (conf=\(transfer.confidence)): \(transfer.reason)")
            let entry = ExactMatchEntry(
                category: "transfer.internal",
                confidence: transfer.confidence,
                isInternalTransfer: true,
                needsReview: transfer.confidence < 0.75,
                shortReason: "Giroconto: \(transfer.reason)",
                source: "rule.transfer",
                updatedAt: ""
            )
            await memoryStore?.saveExact(fingerprint, entry: entry)
            return CategorizationResult(
                category: CategoryMap.displayName(for: "transfer.internal", availableCategories: availableCategories),
                confidence: transfer.confidence,
                isInternalTransfer: true,
                needsReview: transfer.confidence < 0.75,
                shortReason: entry.shortReason,
                source: "rule.transfer"
            )
        }

        // STEP 3: Similar learned pattern (Jaccard ≥ 0.82)
        if let store = memoryStore {
            let patterns = store.learnedPatterns
            var bestSimilarity = 0.0
            var bestPattern: LearnedPattern? = nil
            for pattern in patterns {
                let sim = TransactionNormalizer.jaccard(canonical, pattern.canonicalText)
                if sim > bestSimilarity { bestSimilarity = sim; bestPattern = pattern }
            }
            if bestSimilarity >= 0.82, let best = bestPattern {
                let conf = min(0.75 + bestSimilarity * 0.2, 0.95)
                catLog.info("✅ Step 3 — Similar pattern (sim=\(String(format: "%.2f", bestSimilarity))): \(best.category)")
                let entry = ExactMatchEntry(
                    category: best.category, confidence: conf,
                    isInternalTransfer: false, needsReview: false,
                    shortReason: "Pattern simile (\(String(format: "%.0f", bestSimilarity * 100))%)",
                    source: "memory.similar", updatedAt: ""
                )
                await memoryStore?.saveExact(fingerprint, entry: entry)
                return CategorizationResult(
                    category: CategoryMap.displayName(for: best.category, availableCategories: availableCategories),
                    confidence: conf, isInternalTransfer: false, needsReview: false,
                    shortReason: entry.shortReason, source: "memory.similar"
                )
            }
        }

        // STEP 4a: Apple Intelligence
        let aiResult = await categorizeWithAI(
            description: description, amount: amount, direction: direction,
            canonical: canonical, availableCategories: availableCategories
        )

        // Save to memory if valid
        if aiResult.category != "Altro" || aiResult.confidence > 0.5 {
            let entry = ExactMatchEntry(
                category: aiResult.category, confidence: aiResult.confidence,
                isInternalTransfer: aiResult.isInternalTransfer, needsReview: aiResult.needsReview,
                shortReason: aiResult.shortReason, source: aiResult.source, updatedAt: ""
            )
            await memoryStore?.saveExact(fingerprint, entry: entry)
            await memoryStore?.addLearnedPattern(canonicalText: canonical, category: aiResult.category)
        }

        return aiResult
    }

    // MARK: - AI Step

    private func categorizeWithAI(
        description: String,
        amount: Double,
        direction: String,
        canonical: String,
        availableCategories: [String]
    ) async -> CategorizationResult {
        let categoriesList = availableCategories.joined(separator: ", ")
        let prompt = """
        Sei un esperto di finanza personale italiana. Classifica questa transazione bancaria.

        Transazione:
        - Descrizione: "\(description)"
        - Importo: €\(String(format: "%.2f", amount))
        - Tipo: \(direction == "CRDT" ? "Entrata (CRDT)" : "Uscita (DBIT)")

        Categorie disponibili: \(categoriesList)

        Regole:
        - Supermercato/alimentari → Spesa
        - Ristorante/bar/fast food → Ristoranti
        - Benzina/trasporti/taxi → Trasporti
        - Stipendio/salary/payroll → Stipendio
        - Giroconto/trasferimento tra conti propri → Giroconto
        - Bollette/affitto/utenze → Bollette
        - Farmacia/medico → Salute
        - Netflix/Spotify/cinema → Intrattenimento
        - ATM/prelievo → Prelievo
        - Commissioni bancarie → Commissioni

        Rispondi SOLO col nome esatto di una delle categorie disponibili, nient'altro.
        """

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                // Find best match in available categories
                let matched = availableCategories.first {
                    $0.lowercased() == raw.lowercased()
                } ?? availableCategories.first(where: {
                    raw.lowercased().contains($0.lowercased()) || $0.lowercased().contains(raw.lowercased())
                }) ?? heuristicCategory(canonical: canonical, direction: direction, availableCategories: availableCategories)
                catLog.info("✅ Step 4a — Apple Intelligence: '\(raw)' → '\(matched)'")
                return CategorizationResult(
                    category: matched, confidence: 0.85,
                    isInternalTransfer: matched.lowercased().contains("giroconto"),
                    needsReview: false, shortReason: "Apple Intelligence", source: "ai.apple"
                )
            } catch {
                catLog.warning("⚠️ Apple Intelligence failed: \(error.localizedDescription), using heuristics")
            }
        }
        #endif

        // STEP 4b: Rule-based heuristic fallback
        return heuristicResult(canonical: canonical, direction: direction, availableCategories: availableCategories)
    }

    // MARK: - Heuristic fallback

    private func heuristicResult(canonical: String, direction: String, availableCategories: [String]) -> CategorizationResult {
        let cat = heuristicCategory(canonical: canonical, direction: direction, availableCategories: availableCategories)
        catLog.info("✅ Step 4b — Heuristic: '\(cat)'")
        return CategorizationResult(
            category: cat, confidence: 0.5,
            isInternalTransfer: cat.lowercased().contains("giroconto"),
            needsReview: true, shortReason: "Euristica", source: "rule.heuristic"
        )
    }

    private func heuristicCategory(canonical: String, direction: String, availableCategories: [String]) -> String {
        func has(_ words: [String]) -> Bool { words.contains { canonical.contains($0) } }
        func find(_ name: String) -> String? { availableCategories.first { $0.lowercased().contains(name.lowercased()) } }

        let rules: [(condition: Bool, category: String)] = [
            (direction == "CRDT" && has(["stipendio","salary","payroll","retribuzione"]), "Stipendio"),
            (direction == "CRDT" && has(["rimborso","refund","storno"]),                  "Rimborso"),
            (has(["giroconto","trasferimento","topup","top up"]),                          "Giroconto"),
            (has(["atm","prelievo","cash"]),                                               "Prelievo"),
            (has(["supermercato","esselunga","conad","coop","lidl","carrefour","aldi","spesa"]), "Spesa"),
            (has(["ristorante","pizzeria","mcdonald","burger","sushi","bar ","caffe"]),    "Ristoranti"),
            (has(["benzina","eni","agip","ip ","tamoil","autostrada","taxi","uber","atm","trenitalia","italo","parking","parcheggio"]), "Trasporti"),
            (has(["amazon","zara","h&m","ikea","mediaworld","unieuro","decathlon"]),       "Shopping"),
            (has(["enel","eni gas","snam","telecom","tim ","vodafone","windtre","affitto","condominio"]), "Bollette"),
            (has(["farmacia","medico","ospedale","dentista","ottica"]),                    "Salute"),
            (has(["netflix","spotify","amazon prime","disney","cinema","teatro"]),         "Intrattenimento"),
            (has(["commissione","bollo","canone","fee"]),                                  "Commissioni"),
            (direction == "CRDT",                                                          "Altre Entrate"),
        ]
        for (condition, name) in rules {
            if condition, let match = find(name) ?? availableCategories.first(where: { $0 == name }) { return match }
        }
        return availableCategories.first ?? "Altro"
    }

    // MARK: - Batch categorization for bank transactions

    func batchCategorize(
        transactions: [Transaction],
        availableCategories: [String]
    ) async -> [(id: String, result: CategorizationResult)] {
        var results: [(id: String, result: CategorizationResult)] = []
        for tx in transactions {
            guard let id = tx.id else { continue }
            let result = await categorize(
                description: tx.description, amount: tx.amount,
                type: tx.type, availableCategories: availableCategories,
                allTransactions: transactions
            )
            results.append((id, result))
        }
        return results
    }
}
