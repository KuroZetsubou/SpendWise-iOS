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
