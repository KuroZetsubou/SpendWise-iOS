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
        ScrollView {
            VStack(spacing: DS.Space.sectionGap) {
                amountHero

                VStack(spacing: DS.Space.sectionGap) {
                    detailsSection
                    if bankAccount != nil || transaction.accountId != nil { bankSection }
                    if isImported { importSection }
                    recurringSection
                    if let tags = transaction.tags, !tags.isEmpty { tagsSection(tags) }
                    if transaction.isIgnored || transaction.isTransfer { flagsSection }

                    DSButton("Elimina Transazione", icon: "trash",
                             variant: .secondary, size: .large, block: true) {
                        showDeleteConfirm = true
                    }
                }
                .dsGutter()
            }
            .padding(.bottom, DS.Space.x8)
        }
        .scrollIndicators(.hidden)
        .background(DS.Colors.bgApp)
        .ignoresSafeArea(edges: .top)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
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

    // MARK: - Hero
    //
    // Navy detail header: translucent circular back and edit buttons, the amount as the
    // loudest thing on screen.

    private var amountHero: some View {
        VStack(spacing: DS.Space.x4) {
            HStack {
                DSIconButton("chevron.left", tone: .onDark, size: 44) { dismiss() }
                Spacer()
                Text("Transazione").dsText(DS.Font.h3, color: DS.Colors.textOnDark)
                Spacer()
                DSIconButton("pencil", tone: .onDark, size: 44) { showEdit = true }
            }

            CategoryIconView(categoryName: transaction.category, size: 30, showBackground: false)
                .frame(width: 64, height: 64)
                .background(DS.Colors.scrimOnDark)
                .clipShape(Circle())

            VStack(spacing: DS.Space.x1) {
                Text(transaction.displayTitle)
                    .dsText(DS.Font.h3, color: DS.Colors.textOnDark)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(transaction.amount.dsSignedAmount(isIncome: transaction.type == .income))
                    .dsText(DS.Font.amountHero, color: DS.Colors.textOnDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                DSMetaLine([transaction.date.italianFormatted, transaction.category],
                           color: DS.Colors.textOnDarkMuted)
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.x12)
        .padding(.bottom, DS.Space.x6)
        .frame(maxWidth: .infinity)
        .background(DS.Gradients.hero)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: DS.Radius.xl2,
                bottomTrailingRadius: DS.Radius.xl2, topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    // MARK: - Sections

    private var detailsSection: some View {
        section("Dettagli") {
            detailRow(icon: "calendar", label: "Data", value: transaction.date.italianFormatted)
            detailRow(icon: "tag", label: "Categoria", value: transaction.category)
            if let sub = transaction.subCategory, !sub.isEmpty {
                detailRow(icon: "tag.fill", label: "Sotto-categoria", value: sub)
            }
            detailRow(icon: transaction.type == .income ? "arrow.down.left" : "arrow.up.right",
                      label: "Tipo",
                      value: transaction.type == .income ? "Entrata" : "Uscita")
            if let currency = transaction.originalCurrency, !currency.isEmpty, currency != "EUR" {
                detailRow(icon: "dollarsign.circle", label: "Valuta originale",
                          value: "\(transaction.originalAmount.map { String(format: "%.2f", $0) } ?? "-") \(currency)")
            }
        }
    }

    @ViewBuilder
    private var bankSection: some View {
        if let account = bankAccount {
            section("Conto Bancario") {
                HStack(spacing: DS.Space.x3) {
                    DSIconTile(account.isCreditCard == true ? "creditcard.fill" : "building.columns.fill",
                               size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                            .lineLimit(1)
                        DSMetaLine([account.institutionName ?? "", account.accountTypeLabel,
                                    account.displayCurrency])
                    }
                    Spacer(minLength: DS.Space.x2)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(account.currentBalance.dsAmount)
                            .dsText(DS.Font.labelBold, color: DS.Colors.textHeading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("saldo").dsText(DS.Font.meta, color: DS.Colors.textMuted)
                    }
                }
                .padding(.vertical, DS.Space.x2)

                if let iban = account.officialName, !iban.isEmpty {
                    detailRow(icon: "creditcard", label: "IBAN / ID", value: iban)
                }
                if account.isCreditCard == true {
                    if let limit = account.creditLimit, limit > 0 {
                        detailRow(icon: "arrow.up.circle", label: "Limite credito",
                                  value: limit.dsAmount)
                    }
                    if let day = account.paymentDay, day > 0 {
                        detailRow(icon: "calendar.badge.exclamationmark", label: "Giorno pagamento",
                                  value: "\(day) del mese")
                    }
                }
            }
        } else if let aid = transaction.accountId {
            section("Conto Bancario") {
                detailRow(icon: "building.columns", label: "Account", value: aid)
            }
        }
    }

    private var importSection: some View {
        section("Info Importazione") {
            if let btid = transaction.bankTransactionId {
                detailRow(icon: "number", label: "ID banca", value: btid)
            }
            if let bd = transaction.bookingDate {
                detailRow(icon: "calendar.badge.checkmark", label: "Data contabile",
                          value: String(bd.prefix(10)))
            }
            if let vd = transaction.transactionDate {
                detailRow(icon: "calendar.badge.clock", label: "Data valuta",
                          value: String(vd.prefix(10)))
            }
            HStack(spacing: DS.Space.x2) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.textMuted)
                Text("Importata da banca — modifica limitata")
                    .dsText(DS.Font.meta, color: DS.Colors.textMuted)
            }
            .padding(.top, DS.Space.x1)
        }
    }

    @ViewBuilder
    private var recurringSection: some View {
        section("Abbonamento") {
            if let rid = transaction.recurringId,
               let rec = viewModel.recurrings.first(where: { $0.id == rid }) {
                detailRow(icon: "repeat.circle.fill", label: "Abbonamento", value: rec.name)
                detailRow(icon: rec.recurringTiming.systemImage, label: "Frequenza",
                          value: rec.recurringTiming.label)
                DSButton("Scollega", icon: "link.badge.plus",
                         variant: .secondary, size: .small, block: true) {
                    Task {
                        await viewModel.unlinkTransaction(recurringId: rid,
                                                          transactionId: transaction.id ?? "")
                    }
                }
                .padding(.top, DS.Space.x2)
            } else {
                if transaction.recurring == true {
                    let freq = transaction.recurringFrequency
                    detailRow(icon: "repeat", label: "Frequenza",
                              value: freq == .weekly ? "Settimanale"
                                   : freq == .yearly ? "Annuale" : "Mensile")
                }
                DSButton("Aggiungi ad Abbonamento", icon: "link.badge.plus",
                         variant: .secondary, size: .small, block: true) {
                    showLinkRecurring = true
                }
                .padding(.top, DS.Space.x2)
            }
        }
    }

    private func tagsSection(_ tags: [String]) -> some View {
        section("Tag") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.x2) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .dsText(DS.Font.metaBold, color: DS.Colors.actionPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DS.Colors.surfaceTint)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var flagsSection: some View {
        HStack(spacing: DS.Space.x2) {
            if transaction.isIgnored {
                DSBadge("Ignorata nelle statistiche", icon: "eye.slash", tone: .neutral)
            }
            if transaction.isTransfer {
                DSBadge("Giroconto interno", icon: "arrow.left.arrow.right", tone: .info)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            DSSectionHeader(title)
            DSCard(.card) {
                VStack(alignment: .leading, spacing: DS.Space.x3) {
                    content()
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: DS.Space.x3) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Colors.actionPrimary)
                .frame(width: 22)
            Text(label).dsText(DS.Font.body, color: DS.Colors.textSecondary)
            Spacer(minLength: DS.Space.x2)
            Text(value)
                .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
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
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
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
