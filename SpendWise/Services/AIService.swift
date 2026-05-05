import Foundation
import Vision

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable struct InsightItem {
    @Guide(description: "Titolo breve del consiglio finanziario") var title: String
    @Guide(description: "Spiegazione pratica del consiglio") var advice: String
    @Guide(description: "Livello impatto: low, medium o high") var impact: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable struct InsightList {
    @Guide(description: "Lista di esattamente 3 consigli finanziari") var insights: [InsightItem]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable struct ReceiptLine {
    @Guide(description: "Nome dell'articolo sullo scontrino") var name: String
    @Guide(description: "Prezzo come numero decimale") var price: Double
}

@available(iOS 26.0, macOS 26.0, *)
@Generable struct ReceiptOutput {
    @Guide(description: "Articoli sullo scontrino") var items: [ReceiptLine]
    @Guide(description: "Totale scontrino in euro") var total: Double
}
#endif

// MARK: - AIService

class AIService {
    static let shared = AIService()
    private init() {}

    var isOnDeviceAIAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) { return true }
        #endif
        return false
    }

    // MARK: - Financial Insights

    func getFinancialInsights(transactions: [Transaction], userName: String) async throws -> [FinancialInsight] {
        let summary = transactions.prefix(50).map {
            "\($0.type.rawValue == "expense" ? "Uscita" : "Entrata") €\(String(format: "%.2f", $0.amount)) – \($0.category) – \($0.description) (\($0.date))"
        }.joined(separator: "\n")

        let prompt = """
        Sei un consulente finanziario per l'app SpendWise. \
        Analizza queste transazioni di \(userName) e fornisci esattamente 3 consigli \
        pratici e specifici per migliorare la gestione del budget. \
        Basa i consigli sui dati reali.

        Transazioni:
        \(summary)
        """

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                return try await generateInsightsOnDevice(prompt: prompt)
            } catch {
                // FoundationModels not available on this device/simulator — use rule-based fallback
            }
        }
        #endif
        return generateInsightsRuleBased(transactions: transactions)
    }

    // MARK: - Rule-based insights fallback (no AI required)

    private func generateInsightsRuleBased(transactions: [Transaction]) -> [FinancialInsight] {
        var insights: [FinancialInsight] = []
        let expenses = transactions.filter { $0.type == .expense }
        let income   = transactions.filter { $0.type == .income }
        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let totalInc = income.reduce(0)   { $0 + $1.amount }

        // 1. Savings rate
        if totalInc > 0 {
            let rate = (totalInc - totalExp) / totalInc * 100
            if rate < 10 {
                insights.append(FinancialInsight(
                    title: "Tasso di risparmio basso",
                    advice: "Stai risparmiando il \(String(format: "%.0f", max(0, rate)))% del reddito. Prova a ridurre le spese discrezionali per raggiungere almeno il 20%.",
                    impact: .high
                ))
            } else {
                insights.append(FinancialInsight(
                    title: "Buon tasso di risparmio",
                    advice: "Stai risparmiando il \(String(format: "%.0f", rate))% del reddito. Considera di investire la parte eccedente.",
                    impact: .low
                ))
            }
        }

        // 2. Top spending category
        let byCategory = Dictionary(grouping: expenses, by: { $0.category })
        if let top = byCategory.max(by: { a, b in
            a.value.reduce(0) { $0 + $1.amount } < b.value.reduce(0) { $0 + $1.amount }
        }) {
            let catTotal = top.value.reduce(0) { $0 + $1.amount }
            insights.append(FinancialInsight(
                title: "Categoria principale: \(top.key)",
                advice: "Hai speso €\(String(format: "%.2f", catTotal)) in \(top.key). Analizza se ci sono opportunità di riduzione in questa categoria.",
                impact: catTotal > totalExp * 0.4 ? .high : .medium
            ))
        }

        // 3. Spending trend
        if expenses.count >= 5 {
            let recent = expenses.prefix(5).reduce(0) { $0 + $1.amount } / 5
            let older  = expenses.dropFirst(5).prefix(5).reduce(0) { $0 + $1.amount } / max(1, Double(min(5, expenses.count - 5)))
            if older > 0 && recent > older * 1.15 {
                insights.append(FinancialInsight(
                    title: "Spese in aumento",
                    advice: "Le ultime transazioni mostrano una media di €\(String(format: "%.2f", recent)) vs €\(String(format: "%.2f", older)) precedenti. Tieni sotto controllo le spese.",
                    impact: .medium
                ))
            } else {
                insights.append(FinancialInsight(
                    title: "Spese stabili",
                    advice: "Le tue spese recenti sono in linea con la media storica. Continua a monitorare regolarmente.",
                    impact: .low
                ))
            }
        }

        return insights.isEmpty ? [
            FinancialInsight(title: "Aggiungi transazioni", advice: "Aggiungi almeno 5 transazioni per ricevere consigli personalizzati.", impact: .low)
        ] : insights
    }

    // MARK: - Receipt Scan

    func scanReceipt(cgImage: CGImage) async throws -> ReceiptScanResult {
        let ocrText = try await recognizeText(in: cgImage)
        guard !ocrText.isEmpty else { return ReceiptScanResult(items: [], total: 0) }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await parseReceiptOnDevice(ocrText: ocrText)
        }
        #endif
        return parseReceiptHeuristic(from: ocrText)
    }

    // MARK: - Auto Categorize

    func categorizeTransaction(description: String, amount: Double, categories: [String]) async throws -> String {
        let prompt = """
        Transazione: "\(description)", €\(String(format: "%.2f", amount))
        Categorie: \(categories.joined(separator: ", "))
        Rispondi SOLO con il nome esatto della categoria più adatta.
        """
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return categories.first { $0.lowercased() == cleaned.lowercased() } ?? categories.first ?? "Altro"
        }
        #endif
        throw AIError.notAvailable
    }

    // MARK: - On-device helpers (only compiled when FoundationModels is available)

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func generateInsightsOnDevice(prompt: String) async throws -> [FinancialInsight] {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt, generating: InsightList.self)
        return response.content.insights.map { item in
            FinancialInsight(
                title: item.title,
                advice: item.advice,
                impact: FinancialInsight.ImpactLevel(rawValue: item.impact) ?? .medium
            )
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func parseReceiptOnDevice(ocrText: String) async throws -> ReceiptScanResult {
        let prompt = "Analizza questo scontrino ed estrai articoli e prezzi:\n\(ocrText)"
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt, generating: ReceiptOutput.self)
        let items = response.content.items.map { ReceiptItem(name: $0.name, price: $0.price) }
        return ReceiptScanResult(items: items, total: response.content.total)
    }
    #endif

    // MARK: - Vision OCR (iOS 17+ / macOS 14+)

    private func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["it", "en"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: - Heuristic receipt parser (fallback)

    private func parseReceiptHeuristic(from text: String) -> ReceiptScanResult {
        var items: [ReceiptItem] = []
        var total: Double = 0
        let regex = try? NSRegularExpression(pattern: #"(.+?)\s+[\€]?\s*(\d+[.,]\d{2})\s*$"#)
        for line in text.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            if let m = regex?.firstMatch(in: line, range: range),
               let nr = Range(m.range(at: 1), in: line),
               let pr = Range(m.range(at: 2), in: line) {
                let name = String(line[nr]).trimmingCharacters(in: .whitespaces)
                let price = Double(String(line[pr]).replacingOccurrences(of: ",", with: ".")) ?? 0
                guard price > 0, !name.isEmpty else { continue }
                let lower = name.lowercased()
                if lower.contains("totale") || lower.contains("total") { total = price }
                else { items.append(ReceiptItem(name: name, price: price)) }
            }
        }
        if total == 0 { total = items.reduce(0) { $0 + $1.price } }
        return ReceiptScanResult(items: items, total: total)
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case notAvailable
    var errorDescription: String? {
        "Apple Intelligence richiede iOS 26+ con Apple Intelligence abilitato nelle Impostazioni."
    }
}
