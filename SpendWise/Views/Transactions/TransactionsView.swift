import SwiftUI

struct TransactionsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var searchText = ""
    @State private var selectedTypeFilter: Transaction.TransactionType? = nil
    @State private var selectedCategoryFilter: String? = nil
    @State private var showAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var transactionToDelete: Transaction?
    @State private var showDeleteConfirm = false
    @State private var isBatchCategorizing = false
    @State private var batchProgress: (done: Int, total: Int) = (0, 0)
    @State private var showBatchDone = false
    @State private var cachedFiltered: [Transaction] = []
    @State private var cachedGrouped: [String: [Transaction]] = [:]
    @State private var cachedCategories: [String] = []

    var body: some View {
        NavigationStack {
            Group {
                if cachedFiltered.isEmpty && searchText.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna transazione", systemImage: "tray")
                    } description: {
                        Text("Aggiungi la tua prima transazione.")
                    } actions: {
                        Button("Aggiungi") { showAddTransaction = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(cachedGrouped.keys.sorted().reversed(), id: \.self) { month in
                            Section(header: monthSectionHeader(month: month)) {
                                ForEach(cachedGrouped[month] ?? []) { tx in
                                    NavigationLink(value: tx) {
                                        TransactionRowView(
                                            transaction: tx,
                                            onDelete: {
                                                transactionToDelete = tx
                                                showDeleteConfirm = true
                                            },
                                            onEdit: { transactionToEdit = tx }
                                        )
                                    }
                                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(transaction: tx, viewModel: viewModel)
            }
            .navigationTitle("Transazioni")
            .searchable(text: $searchText, prompt: "Cerca transazioni...")
            .task { updateCaches() }
            .onChange(of: viewModel.transactions) { _, _ in updateCaches() }
            .onChange(of: searchText) { _, _ in updateCaches() }
            .onChange(of: selectedTypeFilter) { _, _ in updateCaches() }
            .onChange(of: selectedCategoryFilter) { _, _ in updateCaches() }
            .overlay {
                if isBatchCategorizing {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView(value: batchProgress.total > 0 ? Double(batchProgress.done) / Double(batchProgress.total) : 0)
                                .progressViewStyle(.linear)
                                .frame(width: 220)
                            Text("Categorizzazione AI…")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("\(batchProgress.done) / \(batchProgress.total)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .alert("Categorizzazione completata", isPresented: $showBatchDone) {
                Button("OK") {}
            } message: {
                Text("Aggiornate \(batchProgress.done) transazioni.")
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Section("Filtra per tipo") {
                            Button("Tutte") { selectedTypeFilter = nil }
                            Button("Entrate") { selectedTypeFilter = .income }
                            Button("Uscite") { selectedTypeFilter = .expense }
                        }
                        if !cachedCategories.isEmpty {
                            Section("Filtra per categoria") {
                                Button("Tutte") { selectedCategoryFilter = nil }
                                ForEach(cachedCategories, id: \.self) { cat in
                                    Button(cat) { selectedCategoryFilter = cat }
                                }
                            }
                        }
                        Section("AI") {
                            Button {
                                Task { await runBatchCategorization() }
                            } label: {
                                let n = viewModel.transactions.filter { $0.category.isEmpty || $0.category == "Altro" }.count
                                Label(n > 0 ? "Categorizza \(n) non categorizzate" : "Tutte già categorizzate", systemImage: "apple.intelligence")
                            }
                            .disabled(isBatchCategorizing || viewModel.transactions.filter { $0.category.isEmpty || $0.category == "Altro" }.isEmpty)
                        }
                    } label: {
                        Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView(viewModel: viewModel)
            }
            .sheet(item: $transactionToEdit) { tx in
                AddTransactionView(viewModel: viewModel, existingTransaction: tx)
            }
            .confirmationDialog(
                "Elimina transazione?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    if let id = transactionToDelete?.id {
                        Task { await viewModel.deleteTransaction(id: id) }
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                if let tx = transactionToDelete {
                    Text(tx.description.isEmpty ? tx.category : tx.description)
                }
            }
            .alert("Errore", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            )) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Static formatters (created once)
    private static let _fmtYM: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let _fmtMonthDisplay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; f.locale = Locale(identifier: "it_IT"); return f
    }()

    // MARK: - Cache update

    private func updateCaches() {
        let txs = viewModel.transactions
        let filtered = txs.filter { tx in
            let matchesSearch = searchText.isEmpty
                || tx.description.localizedCaseInsensitiveContains(searchText)
                || tx.category.localizedCaseInsensitiveContains(searchText)
            let matchesType = selectedTypeFilter == nil || tx.type == selectedTypeFilter
            let matchesCategory = selectedCategoryFilter == nil || tx.category == selectedCategoryFilter
            return matchesSearch && matchesType && matchesCategory
        }
        cachedFiltered = filtered

        var grouped: [String: [Transaction]] = [:]
        for tx in filtered { grouped[String(tx.date.prefix(7)), default: []].append(tx) }
        cachedGrouped = grouped

        cachedCategories = Array(Set(txs.map { $0.category })).sorted()
    }

    // MARK: - Grouping header

    private func monthSectionHeader(month: String) -> some View {
        let monthDate = Self._fmtYM.date(from: month) ?? Date()
        let monthTxs = cachedGrouped[month] ?? []
        let income = monthTxs.filter { $0.type == .income && !$0.isIgnored }.reduce(0) { $0 + $1.amount }
        let expense = monthTxs.filter { $0.type == .expense && !$0.isIgnored }.reduce(0) { $0 + $1.amount }

        return HStack {
            Text(Self._fmtMonthDisplay.string(from: monthDate).capitalized)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Spacer()
            Text("+\(income.euroFormatted)")
                .font(.caption.bold())
                .foregroundStyle(Color.income)
            Text("-\(expense.euroFormatted)")
                .font(.caption.bold())
                .foregroundStyle(Color.expense)
        }
    }

    private var hasActiveFilter: Bool {
        selectedTypeFilter != nil || selectedCategoryFilter != nil
    }

    // MARK: - Batch AI Categorization

    @MainActor
    private func runBatchCategorization() async {
        guard let userId = viewModel.userId else { return }
        let txs = viewModel.transactions
        let categoryNames = viewModel.categories.map(\.name)
        guard !txs.isEmpty else { return }

        isBatchCategorizing = true
        // Only process uncategorized transactions
        let uncategorized = txs.filter { $0.category.isEmpty || $0.category == "Altro" }
        guard !uncategorized.isEmpty else {
            isBatchCategorizing = false
            batchProgress = (0, 0)
            showBatchDone = true
            return
        }

        batchProgress = (0, uncategorized.count)

        await CategorizationPipeline.shared.prepare(userId: userId)

        var updatedCount = 0
        for tx in uncategorized {
            guard let id = tx.id else {
                batchProgress.done += 1
                continue
            }
            let result = await CategorizationPipeline.shared.categorize(
                description: tx.description,
                amount: tx.amount,
                type: tx.type,
                availableCategories: categoryNames,
                allTransactions: txs
            )
            if result.category != tx.category {
                await viewModel.updateTransaction(id: id, updates: ["category": result.category])
                updatedCount += 1
            }
            batchProgress.done += 1
        }

        batchProgress.done = updatedCount
        isBatchCategorizing = false
        showBatchDone = true
    }
}

#Preview {
    TransactionsView(viewModel: .preview)
}
