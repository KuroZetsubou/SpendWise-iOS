import SwiftUI

// MARK: - Suggestion wrapper (Identifiable for sheet presentation)
private struct SuggestionItem: Identifiable {
    let id: String  // = description
    let description: String
    let amount: Double
    let category: String
    let occurrences: Int
}

struct RecurringsView: View {
    enum RecurringViewMode: String, CaseIterable {
        case list = "Lista"
        case calendar = "Calendario"
    }

    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedView: RecurringViewMode = .list
    @State private var showAdd = false
    @State private var itemToEdit: RecurringPayment?
    @State private var itemToDelete: RecurringPayment?
    @State private var showDeleteConfirm = false
    @State private var itemToDetail: RecurringPayment?
    @State private var suggestionToConvert: SuggestionItem?
    @State private var suggestionsExpanded = true

    private var paidIds: Set<String> { viewModel.currentMonthPaidRecurringIds }

    private var paidCount: Int { viewModel.activeRecurrings.filter { paidIds.contains($0.id ?? "") }.count }
    private var pendingCount: Int { viewModel.activeRecurrings.count - paidCount }

    var body: some View {
        NavigationStack {
            Group {
                if selectedView == .list {
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
                                        isPaidThisMonth: paidIds.contains(item.id ?? ""),
                                        linkedTransactions: viewModel.transactions.filter { $0.recurringId == item.id },
                                        onTap: { itemToDetail = item },
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

                            suggestedSection
                        }
                    }
                } else {
                    RecurringCalendarView(viewModel: viewModel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
            .navigationTitle("Abbonamenti")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Vista", selection: $selectedView) {
                        ForEach(RecurringViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
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
            .sheet(item: $itemToDetail) { item in
                RecurringDetailSheet(
                    item: item,
                    viewModel: viewModel,
                    onEdit: { itemToEdit = item },
                    onDelete: { itemToDelete = item; showDeleteConfirm = true }
                )
            }
            .sheet(item: $suggestionToConvert) { suggestion in
                AddRecurringView(
                    viewModel: viewModel,
                    prefill: AddRecurringView.Prefill(
                        name: suggestion.description,
                        amount: suggestion.amount,
                        category: suggestion.category
                    )
                )
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
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    summaryTile(
                        label: "Pagato questo mese",
                        value: viewModel.actualMonthlyRecurringCost.euroFormatted,
                        icon: "checkmark.circle",
                        color: Color.expense
                    )
                    Divider()
                    summaryTile(
                        label: "Media mensile",
                        value: viewModel.monthlyRecurringCost.euroFormatted,
                        icon: "calendar",
                        color: .appPrimary
                    )
                    Divider()
                    summaryTile(
                        label: "Media annua",
                        value: (viewModel.monthlyRecurringCost * 12).euroFormatted,
                        icon: "star.circle",
                        color: .secondary
                    )
                }
                .frame(maxWidth: .infinity)

                // Paid / pending pills for the current month
                if !viewModel.activeRecurrings.isEmpty {
                    Divider()
                    HStack(spacing: 12) {
                        StatusPill(count: paidCount, label: "pagati", icon: "checkmark.circle.fill", color: .green)
                        StatusPill(count: pendingCount, label: "da pagare", icon: "clock.fill", color: .orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                }
            }
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

    // MARK: - Suggested subscriptions

    @ViewBuilder
    private var suggestedSection: some View {
        // Filter out suggestions that already match an existing recurring by name
        let existingNames = viewModel.activeRecurrings.map { $0.name.lowercased() }
        let suggestions = viewModel.suggestedRecurringTransactions.filter { s in
            let desc = s.description.lowercased()
            return !existingNames.contains { name in
                name.contains(desc) || desc.contains(name)
            }
        }
        if !suggestions.isEmpty {
            Section {
                if suggestionsExpanded {
                    ForEach(suggestions, id: \.description) { s in
                        HStack(spacing: 12) {
                            CategoryIconView(categoryName: s.category, size: 36, showBackground: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.description)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text("\(s.occurrences) volte · \(s.amount.euroFormatted) ca.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                suggestionToConvert = SuggestionItem(
                                    id: s.description,
                                    description: s.description,
                                    amount: s.amount,
                                    category: s.category,
                                    occurrences: s.occurrences
                                )
                            } label: {
                                Label("Aggiungi", systemImage: "plus.circle")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.appPrimary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { suggestionsExpanded.toggle() }
                } label: {
                    HStack {
                        Label("Possibili abbonamenti (\(suggestions.count))", systemImage: "wand.and.stars")
                        Spacer()
                        Image(systemName: suggestionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .textCase(nil)
            } footer: {
                if suggestionsExpanded {
                    Text("Transazioni simili rilevate più mesi — potrebbero essere abbonamenti non tracciati.")
                        .font(.caption2)
                }
            }
        }
    }
}

// MARK: - Status Pill

private struct StatusPill: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text("\(count) \(label)")
                .font(.caption.bold())
                .foregroundStyle(count == 0 ? .secondary : color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(count == 0 ? 0.06 : 0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Recurring Row

struct RecurringRowView: View {
    let item: RecurringPayment
    let isPaidThisMonth: Bool
    let linkedTransactions: [Transaction]
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onLinkTransaction: (Transaction) -> Void
    let onUnlinkTransaction: (Transaction) -> Void
    let allTransactions: [Transaction]

    private var effectiveAmount: Double {
        item.lastLinkedAmount(linkedTransactions: linkedTransactions) ?? item.amount
    }

    private var effectiveMonthly: Double {
        item.effectiveMonthlyCost(linkedTransactions: linkedTransactions)
    }

    private var endDateLabel: String? {
        guard let end = item.endDate else { return nil }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        guard let d = df.date(from: end) else { return nil }
        let display = DateFormatter(); display.dateFormat = "d MMM yyyy"; display.locale = Locale(identifier: "it_IT")
        return display.string(from: d)
    }

    var body: some View {
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
                    if let nextDate = item.nextPaymentDate(linkedTransactions: linkedTransactions) {
                        let isPast = nextDate < Date()
                        Label(
                            nextPaymentLabel(date: nextDate, isPast: isPast),
                            systemImage: isPast ? "exclamationmark.circle" : "calendar.badge.clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(isPast ? Color.expense : .secondary)
                    }
                    if let end = endDateLabel {
                        Label("Fino al \(end)", systemImage: "calendar.badge.minus")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text((item.type == .expense ? "-" : "+") + effectiveAmount.euroFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(item.type == .expense ? Color.expense : Color.income)
                    if abs(effectiveAmount - item.amount) > 0.01 {
                        Text("config: \(item.amount.euroFormatted)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("≈ \(effectiveMonthly.euroFormatted)/mese")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if isPaidThisMonth {
                        Label("Pagato", systemImage: "checkmark.circle.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    } else {
                        Label("Da pagare", systemImage: "clock.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Image(systemName: "chevron.right")
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
    }

    private func nextPaymentLabel(date: Date, isPast: Bool) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = Locale(identifier: "it_IT")
        return (isPast ? "Atteso il " : "Prossimo ") + df.string(from: date).capitalized
    }
}

// MARK: - Recurring Detail Sheet

struct RecurringDetailSheet: View {
    let item: RecurringPayment
    @ObservedObject var viewModel: DashboardViewModel
    var onEdit: () -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showLinkPicker = false
    @State private var showDeleteConfirm = false

    private var linkedTransactions: [Transaction] {
        viewModel.transactions.filter { $0.recurringId == item.id }.sorted { $0.date > $1.date }
    }

    private var effectiveAmount: Double {
        item.lastLinkedAmount(linkedTransactions: linkedTransactions) ?? item.amount
    }

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    HStack(spacing: 16) {
                        CategoryIconView(categoryName: item.category, size: 52, showBackground: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.title3.bold())
                            HStack(spacing: 6) {
                                Image(systemName: item.recurringTiming.systemImage)
                                Text(item.recurringTiming.label)
                                Text("· giorno \(item.recurringDate)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text((item.type == .expense ? "-" : "+") + effectiveAmount.euroFormatted)
                                .font(.title3.bold())
                                .foregroundStyle(item.type == .expense ? Color.expense : Color.income)
                            Text("≈ \(item.effectiveMonthlyCost(linkedTransactions: linkedTransactions).euroFormatted)/mese")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if let nextDate = item.nextPaymentDate(linkedTransactions: linkedTransactions) {
                        let isPast = nextDate < Date()
                        let formatted = nextDateFormatted(nextDate)
                        Label((isPast ? "Atteso il " : "Prossimo ") + formatted,
                              systemImage: isPast ? "exclamationmark.circle.fill" : "calendar.badge.clock")
                            .font(.subheadline)
                            .foregroundStyle(isPast ? Color.expense : .secondary)
                    }

                    if let end = item.endDate, let endDateStr = formatEndDate(end) {
                        Label("Termina il \(endDateStr)",
                              systemImage: "calendar.badge.minus")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                // Actions
                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onEdit() }
                    } label: {
                        Label("Modifica", systemImage: "pencil")
                    }

                    Button {
                        guard let id = item.id else { return }
                        Task { await viewModel.updateRecurring(id: id, updates: ["isActive": !item.isActive]) }
                        dismiss()
                    } label: {
                        Label(item.isActive ? "Disattiva" : "Riattiva",
                              systemImage: item.isActive ? "pause.circle" : "play.circle")
                    }
                    .foregroundStyle(item.isActive ? .orange : .green)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                }

                // Linked transactions
                Section {
                    if linkedTransactions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "link.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Nessuna transazione collegata")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(linkedTransactions) { tx in
                            NavigationLink(value: tx) {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tx.description.isEmpty ? tx.category : tx.description)
                                            .font(.subheadline).lineLimit(1)
                                        Text(String(tx.date.prefix(10)))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text((tx.type == .expense ? "-" : "+") + tx.amount.euroFormatted)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(tx.type == .expense ? Color.expense : Color.income)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    Button {
                        showLinkPicker = true
                    } label: {
                        Label("Collega transazione", systemImage: "link.badge.plus")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Transazioni passate (\(linkedTransactions.count))")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
            .navigationTitle(item.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(transaction: tx, viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .sheet(isPresented: $showLinkPicker) {
                LinkTransactionSheet(
                    recurringName: item.name,
                    candidates: viewModel.transactions.filter { $0.recurringId == nil },
                    onLink: { tx in
                        if let rid = item.id {
                            Task { await viewModel.linkTransaction(recurringId: rid, transactionId: tx.id ?? "") }
                        }
                    }
                )
            }
            .confirmationDialog("Eliminare \"\(item.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDelete() }
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    private func nextDateFormatted(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMMM yyyy"
        df.locale = Locale(identifier: "it_IT")
        return df.string(from: date)
    }

    private func formatEndDate(_ end: String) -> String? {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        guard let d = df.date(from: end) else { return nil }
        let display = DateFormatter(); display.dateFormat = "d MMMM yyyy"; display.locale = Locale(identifier: "it_IT")
        return display.string(from: d)
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
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
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

#Preview {
    RecurringsView(viewModel: .preview)
}
