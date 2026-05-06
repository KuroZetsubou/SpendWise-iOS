import Foundation

enum TradeRepublicCSVParser {

    // MARK: - Model

    struct TRTransaction {
        var datetime: String        // ISO 8601 with microseconds
        var date: String            // YYYY-MM-DD
        var accountType: String     // DEFAULT | TRADING
        var category: String        // CASH | TRADING
        var type: String            // BUY, SELL, TRANSFER_INSTANT_INBOUND, etc.
        var assetClass: String      // STOCK | CRYPTO | ""
        var name: String            // asset name or counterparty name
        var symbol: String          // ISIN or ticker
        var shares: Double?
        var price: Double?
        var amount: Double          // signed (negative = outflow)
        var fee: Double             // signed fee (0 if empty)
        var tax: Double             // signed withholding tax (0 if empty)
        var currency: String
        var originalAmount: Double?
        var originalCurrency: String
        var fxRate: Double?
        var txDescription: String
        var transactionId: String   // UUID — unique dedup key
        var counterpartyName: String
        var counterpartyIban: String
        var paymentReference: String
        var mccCode: String

        /// True cash impact: amount + fee + tax
        var netAmount: Double { amount + fee + tax }

        /// Best display name: asset name → counterparty name → description snippet
        var displayName: String {
            if !name.isEmpty { return name }
            if !counterpartyName.isEmpty { return counterpartyName }
            return String(txDescription.prefix(50))
        }

        var typeLabel: String {
            switch type {
            case "TRANSFER_INSTANT_INBOUND", "TRANSFER_INBOUND":  return "Bonifico ricevuto"
            case "TRANSFER_INSTANT_OUTBOUND", "TRANSFER_OUTBOUND": return "Bonifico inviato"
            case "CARD_TRANSACTION":   return "Pagamento carta"
            case "INTEREST_PAYMENT":   return "Interessi"
            case "BUY":                return "Acquisto \(assetClass.isEmpty ? "titolo" : assetClass.lowercased())"
            case "SELL":               return "Vendita \(assetClass.isEmpty ? "titolo" : assetClass.lowercased())"
            case "STOCKPERK":          return "Stock Perk"
            case "DIVIDEND":           return "Dividendo"
            case "SAVINGS_PLAN_EXECUTION": return "Piano d'accumulo"
            default:                   return type.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    enum ParseError: LocalizedError {
        case emptyFile
        case noRows
        case unknownFormat
        var errorDescription: String? {
            switch self {
            case .emptyFile:      return "Il file è vuoto"
            case .noRows:         return "Nessuna transazione trovata"
            case .unknownFormat:  return "Formato CSV non riconosciuto. Assicurati di esportare da Trade Republic → Profilo → Estratto conto."
            }
        }
    }

    // MARK: - Public API

    static func parse(csv: String) throws -> [TRTransaction] {
        let lines = csv
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { throw ParseError.emptyFile }

        // Detect and parse header
        let header = splitCSVLine(lines[0]).map { $0.lowercased() }
        guard header.contains("transaction_id") || header.contains("datetime") else {
            throw ParseError.unknownFormat
        }

        func idx(_ col: String) -> Int? { header.firstIndex(of: col) }
        let iDatetime    = idx("datetime")    ?? 0
        let iDate        = idx("date")        ?? 1
        let iAccType     = idx("account_type") ?? 2
        let iCategory    = idx("category")    ?? 3
        let iType        = idx("type")        ?? 4
        let iAssetClass  = idx("asset_class") ?? 5
        let iName        = idx("name")        ?? 6
        let iSymbol      = idx("symbol")      ?? 7
        let iShares      = idx("shares")      ?? 8
        let iPrice       = idx("price")       ?? 9
        let iAmount      = idx("amount")      ?? 10
        let iFee         = idx("fee")         ?? 11
        let iTax         = idx("tax")         ?? 12
        let iCurrency    = idx("currency")    ?? 13
        let iOrigAmt     = idx("original_amount")   ?? 14
        let iOrigCur     = idx("original_currency") ?? 15
        let iFxRate      = idx("fx_rate")     ?? 16
        let iDesc        = idx("description") ?? 17
        let iTxId        = idx("transaction_id") ?? 18
        let iCpName      = idx("counterparty_name") ?? 19
        let iCpIban      = idx("counterparty_iban") ?? 20
        let iPayRef      = idx("payment_reference") ?? 21
        let iMcc         = idx("mcc_code")    ?? 22

        let rows = lines.dropFirst()
        guard !rows.isEmpty else { throw ParseError.noRows }

        return rows.compactMap { line -> TRTransaction? in
            let f = splitCSVLine(line)
            guard f.count > iAmount else { return nil }
            func field(_ i: Int) -> String { i < f.count ? f[i] : "" }
            guard let amount = Double(field(iAmount)), amount != 0 else { return nil }
            return TRTransaction(
                datetime:        field(iDatetime),
                date:            field(iDate),
                accountType:     field(iAccType),
                category:        field(iCategory),
                type:            field(iType),
                assetClass:      field(iAssetClass),
                name:            field(iName),
                symbol:          field(iSymbol),
                shares:          Double(field(iShares)),
                price:           Double(field(iPrice)),
                amount:          amount,
                fee:             Double(field(iFee)) ?? 0,
                tax:             Double(field(iTax)) ?? 0,
                currency:        field(iCurrency).isEmpty ? "EUR" : field(iCurrency),
                originalAmount:  Double(field(iOrigAmt)),
                originalCurrency: field(iOrigCur),
                fxRate:          Double(field(iFxRate)),
                txDescription:   field(iDesc),
                transactionId:   field(iTxId),
                counterpartyName: field(iCpName),
                counterpartyIban: field(iCpIban),
                paymentReference: field(iPayRef),
                mccCode:         field(iMcc)
            )
        }
    }

    // MARK: - Transaction mapping

    static func toTransaction(trTx: TRTransaction, userId: String) -> Transaction {
        let (category, subCategory, txType, isInternal) = mapCategory(trTx)
        let net = abs(trTx.netAmount)
        let desc = buildDescription(trTx)
        let date = String(trTx.date.prefix(10)) // YYYY-MM-DD

        var t = Transaction(
            userId: userId,
            amount: net,
            type: txType,
            category: category,
            subCategory: subCategory.isEmpty ? nil : subCategory,
            description: desc,
            date: date
        )
        // Use the TR transaction UUID as dedup key
        t.bankTransactionId = trTx.transactionId
        t.isInternalTransfer = isInternal ? true : nil

        // Store fee in description if present
        if trTx.fee != 0 || trTx.tax != 0 {
            let feeNote = [
                trTx.fee != 0 ? "commissione \(String(format: "%.2f", trTx.fee))€" : nil,
                trTx.tax != 0 ? "ritenuta \(String(format: "%.2f", trTx.tax))€" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            t.description += " (\(feeNote))"
        }

        return t
    }

    // MARK: - Helpers

    private static func buildDescription(_ tx: TRTransaction) -> String {
        switch tx.type {
        case "BUY", "SELL", "SAVINGS_PLAN_EXECUTION":
            var d = tx.type == "BUY" ? "Acquisto" : (tx.type == "SELL" ? "Vendita" : "PAC")
            if !tx.name.isEmpty { d += " \(tx.name)" }
            if !tx.symbol.isEmpty { d += " (\(tx.symbol))" }
            if let shares = tx.shares, let price = tx.price {
                d += String(format: " — %.4g azioni @ %.2f€", shares, price)
            }
            return d
        case "INTEREST_PAYMENT":
            return tx.txDescription.isEmpty ? "Pagamento interessi" : tx.txDescription
        case "STOCKPERK":
            return "Stock Perk\(tx.name.isEmpty ? "" : " — \(tx.name)")"
        case "DIVIDEND":
            return "Dividendo\(tx.name.isEmpty ? "" : " — \(tx.name) (\(tx.symbol))")"
        default:
            if !tx.displayName.isEmpty && tx.displayName != tx.txDescription {
                return tx.displayName
            }
            return tx.txDescription.isEmpty ? tx.typeLabel : tx.txDescription
        }
    }

    private typealias Mapping = (String, String, Transaction.TransactionType, Bool)

    private static func mapCategory(_ tx: TRTransaction) -> Mapping {
        let net = tx.netAmount
        switch tx.type {
        case "TRANSFER_INSTANT_INBOUND", "TRANSFER_INBOUND":
            return ("Entrate", "Rimborsi", .income, false)

        case "TRANSFER_INSTANT_OUTBOUND", "TRANSFER_OUTBOUND":
            return ("Giroconto", "", .expense, true)

        case "CARD_TRANSACTION":
            return (mapMCC(tx.mccCode), "", .expense, false)

        case "INTEREST_PAYMENT":
            return net >= 0
                ? ("Entrate", "", .income, false)
                : ("Oneri finanziari", "Interessi", .expense, false)

        case "BUY", "SAVINGS_PLAN_EXECUTION":
            return ("Investimenti", "Acquisto titoli", .expense, false)

        case "SELL":
            return ("Investimenti", "Plusvalenze", .income, false)

        case "STOCKPERK":
            return ("Investimenti", "Premi", .income, false)

        case "DIVIDEND":
            return ("Investimenti", "Dividendi", .income, false)

        default:
            return ("Altro", "", net >= 0 ? .income : .expense, false)
        }
    }

    /// Maps MCC codes to SpendWise categories
    private static func mapMCC(_ mcc: String) -> String {
        switch mcc {
        case "5411", "5412", "5422", "5441", "5451", "5462", "5499":
            return "Cibo & Bevande"   // grocery
        case "5812", "5813", "5814":
            return "Cibo & Bevande"   // restaurant / bar / fast food
        case "4111", "4112", "4121", "4131", "4411", "4511":
            return "Trasporti"
        case "5541", "5542":
            return "Trasporti"        // gas station
        case "5912", "8011", "8021", "8031", "8049", "8099":
            return "Salute"
        case "5940", "7941":
            return "Altro"            // sport
        case "7011", "7012":
            return "Trasporti"        // hotel / lodging
        case "6211":
            return "Investimenti"     // TR's own category for securities
        default:
            return "Shopping"
        }
    }

    /// RFC 4180 CSV line splitter — handles quoted fields with embedded commas
    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" { inQuotes.toggle() }
            else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
