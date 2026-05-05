import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    var onDelete: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    private var amountColor: Color {
        transaction.type == .income ? Color.income : Color.expense
    }

    private var amountPrefix: String {
        transaction.type == .income ? "+" : "-"
    }

    private var dateDisplay: String {
        transaction.date.italianFormatted
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(categoryName: transaction.category)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description.isEmpty ? transaction.category : transaction.description)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(transaction.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let sub = transaction.subCategory, !sub.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Text(dateDisplay)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(amountPrefix)\(transaction.amount.euroFormatted)")
                    .font(.subheadline.bold())
                    .foregroundStyle(amountColor)

                if transaction.recurring == true {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(transaction.isIgnored ? 0.5 : 1.0)
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

#Preview {
    List {
        TransactionRowView(
            transaction: Transaction(
                userId: "preview",
                amount: 45.20,
                type: .expense,
                category: "Cibo & Bevande",
                subCategory: "Supermercato",
                description: "Spesa settimanale",
                date: "2024-01-15",
                createdAt: nil
            )
        )
        TransactionRowView(
            transaction: Transaction(
                userId: "preview",
                amount: 2800.00,
                type: .income,
                category: "Entrate",
                subCategory: "Stipendio",
                description: "Stipendio Gennaio",
                date: "2024-01-31",
                createdAt: nil
            )
        )
    }
}
