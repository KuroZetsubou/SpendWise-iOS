import Foundation
import FirebaseFirestore

// MARK: - RecurringTiming

enum RecurringTiming: String, Codable, CaseIterable, Identifiable {
    case daily         = "daily"
    case weekly        = "weekly"
    case biweekly      = "biweekly"
    case monthly       = "monthly"
    case quarterly     = "quarterly"
    case semiannually  = "semiannually"
    case yearly        = "yearly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily:        return "Giornaliero"
        case .weekly:       return "Settimanale"
        case .biweekly:     return "Bisettimanale"
        case .monthly:      return "Mensile"
        case .quarterly:    return "Trimestrale"
        case .semiannually: return "Semestrale"
        case .yearly:       return "Annuale"
        }
    }

    var systemImage: String {
        switch self {
        case .daily:        return "sun.max"
        case .weekly:       return "calendar.badge.clock"
        case .biweekly:     return "calendar.badge.clock"
        case .monthly:      return "calendar"
        case .quarterly:    return "calendar.badge.exclamationmark"
        case .semiannually: return "clock.arrow.2.circlepath"
        case .yearly:       return "star.circle"
        }
    }

    /// Approximate multiplier to normalize to monthly cost
    var monthlyFactor: Double {
        switch self {
        case .daily:        return 30.44
        case .weekly:       return 4.33
        case .biweekly:     return 2.17
        case .monthly:      return 1.0
        case .quarterly:    return 1.0 / 3.0
        case .semiannually: return 1.0 / 6.0
        case .yearly:       return 1.0 / 12.0
        }
    }

    /// Approximate multiplier to normalize to yearly cost
    var yearlyFactor: Double { monthlyFactor * 12 }
}

// MARK: - RecurringPayment

/// Main document stored in `recurrings/{id}`
struct RecurringPayment: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var name: String
    var amount: Double
    var type: Transaction.TransactionType
    var category: String
    var subCategory: String?

    /// Day of month (1–31) for monthly/quarterly/semiannually/yearly,
    /// or day of week (0=Mon … 6=Sun) for daily/weekly/biweekly.
    var recurringDate: Int

    var recurringTiming: RecurringTiming

    /// Snapshot of linked transaction IDs (for quick reads; N:N junction is authoritative)
    var transactionIds: [String]

    var notes: String?
    var isActive: Bool
    var endDate: String?

    @ServerTimestamp var createdAt: Timestamp?
    var updatedAt: String?

    // MARK: Computed helpers

    var monthlyCost: Double { amount * recurringTiming.monthlyFactor }
    var yearlyCost: Double { amount * recurringTiming.yearlyFactor }
}

// MARK: - RecurringTransactionLink (N:N junction)

/// Stored in `recurring_transaction_links/{id}`
/// Mirrors a SQL junction table: recurringId ↔ transactionId
struct RecurringTransactionLink: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var recurringId: String
    var transactionId: String
    @ServerTimestamp var linkedAt: Timestamp?
}

extension RecurringPayment {
    /// Amount from the most recently linked transaction (nil if no linked txs).
    func lastLinkedAmount(linkedTransactions: [Transaction]) -> Double? {
        linkedTransactions
            .filter { $0.recurringId == self.id }
            .sorted { $0.date > $1.date }
            .first?.amount
    }

    /// Monthly cost using last linked transaction amount when available.
    func effectiveMonthlyCost(linkedTransactions: [Transaction]) -> Double {
        (lastLinkedAmount(linkedTransactions: linkedTransactions) ?? amount) * recurringTiming.monthlyFactor
    }

    /// Compute the next expected payment date based on the most recently linked transaction.
    func nextPaymentDate(linkedTransactions: [Transaction]) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lastDate: Date?
        for transaction in linkedTransactions where transaction.recurringId == id {
            let dateString = String(transaction.date.prefix(10))
            guard let parsedDate = formatter.date(from: dateString) else { continue }
            if let currentLastDate = lastDate {
                if parsedDate > currentLastDate {
                    lastDate = parsedDate
                }
            } else {
                lastDate = parsedDate
            }
        }

        guard let lastDate else { return nil }

        let cal = Calendar.current
        switch recurringTiming {
        case .daily:        return cal.date(byAdding: .day,        value: 1, to: lastDate)
        case .weekly:       return cal.date(byAdding: .weekOfYear, value: 1, to: lastDate)
        case .biweekly:     return cal.date(byAdding: .weekOfYear, value: 2, to: lastDate)
        case .monthly:      return cal.date(byAdding: .month,      value: 1, to: lastDate)
        case .quarterly:    return cal.date(byAdding: .month,      value: 3, to: lastDate)
        case .semiannually: return cal.date(byAdding: .month,      value: 6, to: lastDate)
        case .yearly:       return cal.date(byAdding: .year,       value: 1, to: lastDate)
        }
    }
}
