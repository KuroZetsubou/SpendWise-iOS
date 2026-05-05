import SwiftUI

struct RecurringsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showAdd = false
    @State private var itemToEdit: RecurringPayment?
    @State private var itemToDelete: RecurringPayment?
    @State private var showDeleteConfirm = false
    @State private var expandedId: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.recurrings.isEmpty {
                    ContentUnavailableView {
                        Label("Nessun abbonamento", systemImage: "repeat.circle")
                    } description: {
                        Text("Aggiungi i tuoi pagamenti fissi per tracciarli e calcolare il costo mensile.")
                    } actions: {
                        Button("Aggiungi") { showAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        summaryHeader
                        ForEach(RecurringTiming.allCases) { timing in
                            let items = viewModel.activeRecurrings.filter { $0.recurringTiming == timing }
                            if !items.isEmpty {
                                Section(timing.label) {
                                    ForEach(items) { item in
                                        RecurringRowView(
                                            item: item,
                                            isExpanded: expandedId == item.id,
                                            linkedTransactions: viewModel.transactions.filter { $0.recurringId == item.id },
                                            onTap: {
                                                withAnimation { expandedId = expandedId == item.id ? nil : item.id }
                                            },
                                            onEdit: { itemToEdit = item },
                                            onDelete: { itemToDelete = item; showDeleteConfirm = true },
                                            onLinkTransaction: { tx in
                                                if let rid = item.id {
                                                    Task { await viewModel.linkTransaction(recurringId: rid, transactionId: tx.id ?? "") }
                                                }
                                            },
                                            onUnlinkTransaction: { tx in
                                                if let rid = item.id {
                                                    Task { await viewModel.unlinkTransaction(recurringId: rid, transactionId: tx.id ?? "") }
                                                }
                                            },
                                            allTransactions: viewModel.transactions
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Abbonamenti")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddRecurringView(viewModel: viewModel)
            }
            .sheet(item: $itemToEdit) { item in
                AddRecurringView(viewModel: viewModel, existing: item)
            }
            .confirmationDialog("Eliminare \"\(itemToDelete?.name ?? "")\"?",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let id = itemToDelete?.id { Task { await viewModel.deleteRecurring(id: id) } }
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        Section {
            HStack(spacing: 0) {
                summaryTile(
                    label: "Costo mensile",
                    value: viewModel.monthlyRecurringCost.euroFormatted,
                    icon: "calendar",
                    color: Color.expense
                )
                Divider()
                summaryTile(
                    label: "Costo annuo",
                    value: (viewModel.monthlyRecurringCost * 12).euroFormatted,
                    icon: "star.circle",
                    color: .appPrimary
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryTile(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Recurring Row

struct RecurringRowView: View {
    let item: RecurringPayment
    let isExpanded: Bool
    let linkedTransactions: [Transaction]
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onLinkTransaction: (Transaction) -> Void
    let onUnlinkTransaction: (Transaction) -> Void
    let allTransactions: [Transaction]

    @State private var showLinkPicker = false

    private var unlinkableTransactions: [Transaction] {
        allTransactions.filter {
            $0.recurringId == nil && $0.description.localizedCaseInsensitiveContains(item.name)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button(action: onTap) {
                HStack(spacing: 12) {
                    CategoryIconView(categoryName: item.category, size: 40, showBackground: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline.bold()).lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: item.recurringTiming.systemImage).font(.caption2)
                            Text(item.recurringTiming.label).font(.caption)
                            Text("· giorno \(item.recurringDate)").font(.caption).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text((item.type == .expense ? "-" : "+") + item.amount.euroFormatted)
                            .font(.subheadline.bold())
                            .foregroundStyle(item.type == .expense ? Color.expense : Color.income)
                        Text("≈ \(item.monthlyCost.euroFormatted)/mese")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: onDelete) { Label("Elimina", systemImage: "trash") }
                Button(action: onEdit) { Label("Modifica", systemImage: "pencil") }.tint(.orange)
            }

            // Expanded: linked transactions
            if isExpanded {
                Divider().padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Transazioni collegate (\(linkedTransactions.count))")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showLinkPicker = true
                        } label: {
                            Label("Collega", systemImage: "link.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.top, 4)

                    if linkedTransactions.isEmpty {
                        Text("Nessuna transazione collegata")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(linkedTransactions.prefix(5)) { tx in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tx.description.isEmpty ? tx.category : tx.description)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(tx.date.prefix(10))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(tx.amount.euroFormatted)
                                    .font(.caption.bold())
                                    .foregroundStyle(tx.type == .expense ? Color.expense : Color.income)
                                Button { onUnlinkTransaction(tx) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if linkedTransactions.count > 5 {
                            Text("+ altri \(linkedTransactions.count - 5)…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showLinkPicker) {
            LinkTransactionSheet(
                recurringName: item.name,
                candidates: allTransactions.filter { $0.recurringId == nil },
                onLink: onLinkTransaction
            )
        }
    }
}

// MARK: - Link Transaction Sheet

struct LinkTransactionSheet: View {
    let recurringName: String
    let candidates: [Transaction]
    let onLink: (Transaction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Transaction] {
        candidates.filter {
            search.isEmpty ||
            $0.description.localizedCaseInsensitiveContains(search) ||
            $0.category.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { tx in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.description.isEmpty ? tx.category : tx.description)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("\(tx.date.prefix(10)) · \(tx.category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(tx.amount.euroFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(tx.type == .expense ? Color.expense : Color.income)
                    Button {
                        onLink(tx)
                        dismiss()
                    } label: {
                        Image(systemName: "link").font(.subheadline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                } // ForEach
            }
            .navigationTitle("Collega a \(recurringName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $search, prompt: "Cerca transazione…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
