import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    var onDelete: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    private var amountColor: Color {
        transaction.type == .income ? Color.income : Color.expense
    }

    var body: some View {
        HStack(spacing: 10) {
            CategoryIconView(categoryName: transaction.category, size: 28, showBackground: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.description.isEmpty ? transaction.category : transaction.description)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(transaction.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let sub = transaction.subCategory, !sub.isEmpty {
                        Text("· \(sub)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text((transaction.type == .income ? "+" : "-") + transaction.amount.euroFormatted)
                    .font(.subheadline.bold())
                    .foregroundStyle(amountColor)
                Text(transaction.date.prefix(10))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .opacity(transaction.isIgnored ? 0.45 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let delete = onDelete {
                Button(role: .destructive, action: delete) {
                    Label("Elimina", systemImage: "trash")
                }
            }
            if let edit = onEdit {
                Button(action: edit) {
                    Label("Modifica", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
    }
}

