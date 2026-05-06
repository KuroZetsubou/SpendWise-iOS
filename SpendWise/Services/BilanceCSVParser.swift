import Foundation

enum BilanceCSVParser {

    struct BilanceTx {
        var titolo: String
        var data: String          // raw "YYYY-MM-DD HH:MM:SS.SSS"
        var importo: Double
        var categoria: String
        var sottocategoria: String
        var tag: String
        var rimessa: String
        var esercente: String
        var conto: String
        var nota: String
    }

    enum ParseError: LocalizedError {
        case emptyFile
        case noRows
        var errorDescription: String? {
            switch self {
            case .emptyFile: return "Il file è vuoto"
            case .noRows:    return "Nessuna transazione trovata nel file"
            }
        }
    }

    // MARK: - Public API

    static func parse(csv: String) throws -> [BilanceTx] {
        let lines = csv
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { throw ParseError.emptyFile }

        // Skip header row
        let rows = lines.dropFirst()
        guard !rows.isEmpty else { throw ParseError.noRows }

        return rows.compactMap { parseLine($0) }
    }

    static func toTransaction(tx: BilanceTx, userId: String) -> Transaction {
        let (category, subCategory, type, isInternal, isIgnored) = mapCategory(
            bilanceCat: tx.categoria,
            bilanceSub: tx.sottocategoria,
            amount: tx.importo
        )

        let dateString = parseDate(tx.data)
        let amount = abs(tx.importo)

        // Build description: prefer titolo, append nota if present
        var desc = tx.titolo.isEmpty ? tx.esercente : tx.titolo
        if !tx.nota.isEmpty { desc += " — \(tx.nota)" }

        // Deterministic dedup ID from raw fields
        let dedupKey = "\(tx.data)|\(tx.importo)|\(tx.rimessa)"
        let bankTransactionId = "bilance_\(dedupKey.hashValue)"

        var t = Transaction(
            userId: userId,
            amount: amount,
            type: type,
            category: category,
            subCategory: subCategory.isEmpty ? nil : subCategory,
            description: desc,
            date: dateString
        )
        t.bankTransactionId = bankTransactionId
        t.tags = tx.tag.isEmpty ? nil : [tx.tag]
        t.isInternalTransfer = isInternal ? true : nil
        t.ignored = isIgnored ? true : nil
        return t
    }

    // MARK: - Line parser (RFC 4180-compatible)

    private static func parseLine(_ line: String) -> BilanceTx? {
        let fields = splitCSVLine(line)
        guard fields.count >= 9 else { return nil }

        let amountRaw = fields[2]
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(amountRaw) else { return nil }

        return BilanceTx(
            titolo:         fields[0],
            data:           fields[1],
            importo:        amount,
            categoria:      fields[3],
            sottocategoria: fields[4],
            tag:            fields[5],
            rimessa:        fields[6],
            esercente:      fields[7],
            conto:          fields[8],
            nota:           fields.count > 9 ? fields[9] : ""
        )
    }

    /// Splits a CSV line respecting double-quoted fields (handles embedded commas)
    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    // MARK: - Date parsing

    /// Converts "2026-04-22 15:28:00.000" → "2026-04-22"
    private static func parseDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // If already ISO date-only, return as-is
        if trimmed.count == 10 { return trimmed }
        // Take only the date part before the space
        return String(trimmed.prefix(10))
    }

    // MARK: - Category mapping

    private typealias CategoryMapping = (
        category: String,
        subCategory: String,
        type: Transaction.TransactionType,
        isInternal: Bool,
        isIgnored: Bool
    )

    private static func mapCategory(
        bilanceCat: String,
        bilanceSub: String,
        amount: Double
    ) -> CategoryMapping {
        let cat = bilanceCat.trimmingCharacters(in: .whitespaces)
        let sub = bilanceSub.trimmingCharacters(in: .whitespaces)

        switch cat {

        case "Entrate":
            let mappedSub = mapSubEntrate(sub)
            return ("Entrate", mappedSub, .income, false, false)

        case "Investimenti":
            if amount >= 0 {
                return ("Investimenti", "Dividendi", .income, false, false)
            } else {
                return ("Investimenti", "Acquisto titoli", .expense, false, false)
            }

        case "Cibo & Bevande":
            return ("Cibo & Bevande", mapSubCibo(sub), .expense, false, false)

        case "Casa":
            return ("Casa", mapSubCasa(sub), .expense, false, false)

        case "Shopping":
            return ("Shopping", "", .expense, false, false)

        case "Trasporto", "Trasporti":
            return ("Trasporti", mapSubTrasporto(sub), .expense, false, false)

        case "Oneri finanziari":
            return ("Oneri finanziari", mapSubOneri(sub), .expense, false, false)

        case "Salute & Istruzione", "Salute":
            return ("Salute", mapSubSalute(sub), .expense, false, false)

        case "Vita e intrattenimento":
            return ("Altro", mapSubIntrattenimento(sub), .expense, false, false)

        case "Giroconti":
            return ("Giroconto", "", amount >= 0 ? .income : .expense, true, false)

        case "Escluso":
            return ("Altro", "", amount >= 0 ? .income : .expense, false, true)

        case "Non definito", "Altro":
            return ("Altro", "", amount >= 0 ? .income : .expense, false, false)

        default:
            return (cat.isEmpty ? "Altro" : cat, sub, amount >= 0 ? .income : .expense, false, false)
        }
    }

    private static func mapSubEntrate(_ sub: String) -> String {
        switch sub {
        case "Refunds", "Rimborsi":   return "Rimborsi"
        case "Vendita", "Vendite":    return "Vendite"
        case "Stipendio":             return "Stipendio"
        case "Premi":                 return "Premi"
        default:                      return sub
        }
    }

    private static func mapSubCibo(_ sub: String) -> String {
        let s = sub.lowercased()
        if s.contains("ristorante") || s.contains("consegna") || s.contains("domicilio") {
            return "Ristoranti"
        }
        if s.contains("supermercato") || s.contains("alimentari") { return "Supermercato" }
        if s.contains("bar") || s.contains("alcolici") || s.contains("tabacco") { return "Bar" }
        if s.contains("glovo") || s.contains("deliveroo") || s.contains("just eat") { return "Glovo/Deliveroo" }
        return sub
    }

    private static func mapSubCasa(_ sub: String) -> String {
        let s = sub.lowercased()
        if s.contains("telefono") || s.contains("internet") || s.contains("utenz") { return "Bollette" }
        if s.contains("affitto") || s.contains("mutuo") { return "Affitto/Mutuo" }
        if s.contains("software") || s.contains("digit") { return "Bollette" }
        return sub
    }

    private static func mapSubTrasporto(_ sub: String) -> String {
        let s = sub.lowercased()
        if s.contains("carburante") || s.contains("benzina") { return "Carburante" }
        if s.contains("pubblico") || s.contains("treno") || s.contains("metro") { return "Mezzi Pubblici" }
        if s.contains("parcheggio") || s.contains("auto") { return "Auto/Parcheggi" }
        if s.contains("viaggi") || s.contains("aereo") || s.contains("volo") { return "Viaggi" }
        return sub
    }

    private static func mapSubOneri(_ sub: String) -> String {
        let s = sub.lowercased()
        if s.contains("prestito") || s.contains("interess") { return "Interessi" }
        if s.contains("commissioni") { return "Commissioni" }
        if s.contains("assicurazione") { return "Assicurazioni" }
        if s.contains("imposta") || s.contains("tassa") { return "Imposte" }
        return sub
    }

    private static func mapSubSalute(_ sub: String) -> String {
        let s = sub.lowercased()
        if s.contains("farmac") { return "Farmacia" }
        if s.contains("dent") { return "Dentista" }
        if s.contains("visit") || s.contains("medic") { return "Visite Mediche" }
        if s.contains("bellezza") || s.contains("benessere") { return "Farmacia" }
        return sub
    }

    private static func mapSubIntrattenimento(_ sub: String) -> String {
        let s = sub.lowercased()
        if s.contains("software") || s.contains("digit") || s.contains("stream") { return "Bollette" }
        return sub
    }
}
