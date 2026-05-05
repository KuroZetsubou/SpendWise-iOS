import Foundation
import FirebaseFirestore

struct ReceiptItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var price: Double

    enum CodingKeys: String, CodingKey {
        case name, price
    }
}

struct Transaction: Codable, Identifiable {
    @DocumentID var id: String?
    var userId: String
    var amount: Double
    var type: TransactionType
    var category: String
    var subCategory: String?
    var description: String
    var date: String
    var bookingDate: String?
    var transactionDate: String?
    @ServerTimestamp var createdAt: Timestamp?
    var bankTransactionId: String?
    var accountId: String?
    var originalAmount: Double?
    var originalCurrency: String?
    var exchangeRate: Double?
    var tags: [String]?
    var recurring: Bool?
    var recurringFrequency: RecurringFrequency?
    var recurringEndDate: String?
    var recurringId: String?          // FK → recurrings/{id}
    var receiptItems: [ReceiptItem]?
    var ignored: Bool?
    var isInternalTransfer: Bool?

    enum TransactionType: String, Codable, CaseIterable {
        case income
        case expense
    }

    enum RecurringFrequency: String, Codable {
        case weekly
        case monthly
        case yearly
    }

    var dateAsDate: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: date) ?? Date()
    }

    var isIgnored: Bool { ignored == true }
    var isTransfer: Bool { isInternalTransfer == true }
    var effectiveAmount: Double {
        type == .expense ? -abs(amount) : abs(amount)
    }
}
