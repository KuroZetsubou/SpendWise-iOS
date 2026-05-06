import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showLinkRecurring = false

    private var bankAccount: BankAccount? {
        guard let aid = transaction.accountId else { return nil }
        return viewModel.resolvedBankAccount(for: aid)
    }

    private var amountColor: Color {
        transaction.type == .income ? Color.income : Color.expense
    }

    private var isImported: Bool { transaction.bankTransactionId != nil }

    var body: some View {
        List {
                // ── Header ──────────────────────────────────────────────────
                Section {
                    HStack(spacing: 16) {
                        CategoryIconView(categoryName: transaction.category, size: 52, showBackground: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transaction.description.isEmpty ? transaction.category : transaction.description)
                                .font(.headline)
                                .lineLimit(2)
                            Text((transaction.type == .income ? "+" : "-") + transaction.amount.euroFormatted)
                                .font(.title2.bold())
                                .foregroundStyle(amountColor)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                // ── Date & Category ─────────────────────────────────────────
                Section("Dettagli") {
                    detailRow(icon: "calendar", label: "Data", value: transaction.date.italianFormatted)
                    detailRow(icon: "tag", label: "Categoria", value: transaction.category)
                    if let sub = transaction.subCategory, !sub.isEmpty {
                        detailRow(icon: "tag.fill", label: "Sotto-categoria", value: sub)
                    }
                    detailRow(
                        icon: transaction.type == .income ? "arrow.down.circle" : "arrow.up.circle",
                        label: "Tipo",
                        value: transaction.type == .income ? "Entrata" : "Uscita"
                    )
                    if let currency = transaction.originalCurrency, !currency.isEmpty, currency != "EUR" {
                        detailRow(icon: "dollarsign.circle", label: "Valuta originale",
                                  value: "\(transaction.originalAmount.map { String(format: "%.2f", $0) } ?? "-") \(currency)")
                    }
                }

                // ── Bank Account ─────────────────────────────────────────────
                if let account = bankAccount {
                    Section("Conto bancario") {
                        HStack(spacing: 12) {
                            Image(systemName: account.isCreditCard == true ? "creditcard.fill" : "building.columns.fill")
                                .font(.title3)
                                .foregroundStyle(Color.appPrimary)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.displayName)
                                    .font(.subheadline.bold())
                                if let inst = account.institutionName {
                                    Text(inst)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Text(account.accountTypeLabel)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.appPrimary.opacity(0.1))
                                        .foregroundStyle(Color.appPrimary)
                                        .clipShape(Capsule())
                                    Text(account.displayCurrency)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(account.currentBalance.euroFormatted)
                                    .font(.subheadline.bold())
                                Text("saldo")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        if let iban = account.officialName, !iban.isEmpty {
                            detailRow(icon: "creditcard", label: "IBAN / ID", value: iban)
                        }
                        if account.isCreditCard == true {
                            if let limit = account.creditLimit, limit > 0 {
                                detailRow(icon: "arrow.up.circle", label: "Limite credito", value: limit.euroFormatted)
                            }
                            if let day = account.paymentDay, day > 0 {
                                detailRow(icon: "calendar.badge.exclamationmark", label: "Giorno pagamento", value: "\(day) del mese")
                            }
                        }
                    }
                } else if let aid = transaction.accountId {
                    Section("Conto bancario") {
                        HStack {
                            Image(systemName: "building.columns").foregroundStyle(.secondary)
                            Text("Account: \(aid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Bank transaction metadata ────────────────────────────────
                if isImported {
                    Section("Info importazione") {
                        if let btid = transaction.bankTransactionId {
                            detailRow(icon: "number", label: "ID transazione banca", value: btid)
                        }
                        if let bd = transaction.bookingDate {
                            detailRow(icon: "calendar.badge.checkmark", label: "Data contabile", value: String(bd.prefix(10)))
                        }
                        if let vd = transaction.transactionDate {
                            detailRow(icon: "calendar.badge.clock", label: "Data valuta", value: String(vd.prefix(10)))
                        }
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text("Importata da banca — modifica limitata")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Recurring ────────────────────────────────────────────────
                Section("Abbonamento") {
                    if let rid = transaction.recurringId,
                       let rec = viewModel.recurrings.first(where: { $0.id == rid }) {
                        detailRow(icon: "repeat.circle.fill", label: "Abbonamento", value: rec.name)
                        detailRow(icon: rec.recurringTiming.systemImage, label: "Frequenza", value: rec.recurringTiming.label)
                        Button(role: .destructive) {
                            Task { await viewModel.unlinkTransaction(recurringId: rid, transactionId: transaction.id ?? "") }
                        } label: {
                            Label("Scollega da \(rec.name)", systemImage: "link.badge.minus")
                                .font(.subheadline)
                        }
                    } else {
                        if transaction.recurring == true {
                            let freq = transaction.recurringFrequency
                            detailRow(icon: "repeat", label: "Frequenza",
                                      value: freq == .weekly ? "Settimanale" : freq == .yearly ? "Annuale" : "Mensile")
                        }
                        Button {
                            showLinkRecurring = true
                        } label: {
                            Label("Aggiungi ad abbonamento", systemImage: "link.badge.plus")
                                .font(.subheadline)
                        }
                    }
                }

                // ── Tags ─────────────────────────────────────────────────────
                if let tags = transaction.tags, !tags.isEmpty {
                    Section("Tag") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Color.appPrimary.opacity(0.1))
                                        .foregroundStyle(Color.appPrimary)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // ── Flags ────────────────────────────────────────────────────
                if transaction.isIgnored || transaction.isTransfer {
                    Section {
                        if transaction.isIgnored {
                            Label("Ignorata nelle statistiche", systemImage: "eye.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if transaction.isTransfer {
                            Label("Giroconto interno", systemImage: "arrow.left.arrow.right")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // ── Delete ───────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Elimina transazione", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
        }
        .navigationTitle("Transazione")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEdit = true
                } label: {
                    Label("Modifica", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddTransactionView(viewModel: viewModel, existingTransaction: transaction)
        }
        .sheet(isPresented: $showLinkRecurring) {
            LinkToRecurringSheet(transaction: transaction, viewModel: viewModel)
        }
        .confirmationDialog("Eliminare questa transazione?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let id = transaction.id {
                    Task {
                        await viewModel.deleteTransaction(id: id)
                        dismiss()
                    }
                }
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.appPrimary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

// MARK: - Link to Recurring Sheet

struct LinkToRecurringSheet: View {
    let transaction: Transaction
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showNewRecurring = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.activeRecurrings.isEmpty {
                    ContentUnavailableView {
                        Label("Nessun abbonamento", systemImage: "repeat.circle")
                    } description: {
                        Text("Crea un abbonamento per collegare questa transazione.")
                    }
                } else {
                    Section("Seleziona abbonamento") {
                        ForEach(viewModel.activeRecurrings) { rec in
                            Button {
                                Task {
                                    await viewModel.linkTransaction(recurringId: rec.id ?? "", transactionId: transaction.id ?? "")
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    CategoryIconView(categoryName: rec.category, size: 36, showBackground: true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rec.name)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Image(systemName: rec.recurringTiming.systemImage)
                                                .font(.caption2)
                                            Text(rec.recurringTiming.label)
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(rec.amount.euroFormatted)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.expense)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        showNewRecurring = true
                    } label: {
                        Label("Crea nuovo abbonamento", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Collega ad abbonamento")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .sheet(isPresented: $showNewRecurring) {
                AddRecurringView(
                    viewModel: viewModel,
                    prefill: AddRecurringView.Prefill(
                        name: transaction.description,
                        amount: transaction.amount,
                        category: transaction.category
                    )
                )
            }
        }
    }
}

#Preview("Dettaglio — Spesa") {
    NavigationStack {
        TransactionDetailView(transaction: MockData.transactions[1], viewModel: .preview)
    }
}

#Preview("Dettaglio — Import TR") {
    NavigationStack {
        TransactionDetailView(transaction: MockData.transactions[4], viewModel: .preview)
    }
}
