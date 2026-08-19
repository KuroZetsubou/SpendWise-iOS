import SwiftUI

struct TransactionsView: View {
    enum TxViewMode: String, CaseIterable {
        case list = "Lista"
        case calendar = "Calendario"
    }

    @ObservedObject var viewModel: DashboardViewModel
    @State private var txViewMode: TxViewMode = .list
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
            VStack(spacing: 0) {
                header

                if cachedFiltered.isEmpty {
                    ScrollView {
                        DSEmptyState(
                            icon: searchText.isEmpty ? "tray" : "magnifyingglass",
                            title: searchText.isEmpty ? "Nessuna Transazione" : "Nessun Risultato",
                            message: searchText.isEmpty
                                ? "Aggiungi il tuo primo movimento per iniziare a tracciare le spese."
                                : "Prova con un altro termine di ricerca.",
                            actionTitle: searchText.isEmpty ? "Aggiungi Movimento" : nil,
                            action: searchText.isEmpty ? { showAddTransaction = true } : nil
                        )
                    }
                    .scrollIndicators(.hidden)
                } else {
                    transactionList
                }
            }
            .background(DS.Colors.bgApp)
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(transaction: tx, viewModel: viewModel)
            }
            .task { updateCaches() }
            .onChange(of: viewModel.transactions) { _, _ in updateCaches() }
            .onChange(of: searchText) { _, _ in updateCaches() }
            .onChange(of: selectedTypeFilter) { _, _ in updateCaches() }
            .onChange(of: selectedCategoryFilter) { _, _ in updateCaches() }
            .overlay {
                if isBatchCategorizing { batchOverlay }
            }
            .alert("Categorizzazione completata", isPresented: $showBatchDone) {
                Button("OK") {}
            } message: {
                Text("Aggiornate \(batchProgress.done) transazioni.")
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
                    Text(tx.displayTitle)
                }
            }
            .alert("Errore", isPresented: errorBinding) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    // MARK: - Header
    //
    // Light app bar: ink title left, a white circular overflow button on the right, then the
    // search field and a horizontal-scroll chip row.

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            HStack(spacing: DS.Space.x3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Movimenti").dsText(DS.Font.h2, color: DS.Colors.textHeading)
                    Text("\(cachedFiltered.count) transazioni")
                        .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                }
                Spacer(minLength: DS.Space.x2)
                filterMenu
            }

            DSTextField(placeholder: "Cerca movimenti…", text: $searchText,
                        icon: "magnifyingglass")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.x2) {
                    DSChip("Tutte", isSelected: selectedTypeFilter == nil && selectedCategoryFilter == nil) {
                        selectedTypeFilter = nil
                        selectedCategoryFilter = nil
                    }
                    DSChip("Entrate", icon: "arrow.down.left",
                           isSelected: selectedTypeFilter == .income) {
                        selectedTypeFilter = selectedTypeFilter == .income ? nil : .income
                    }
                    DSChip("Uscite", icon: "arrow.up.right",
                           isSelected: selectedTypeFilter == .expense) {
                        selectedTypeFilter = selectedTypeFilter == .expense ? nil : .expense
                    }
                    ForEach(cachedCategories, id: \.self) { cat in
                        DSChip(cat, isSelected: selectedCategoryFilter == cat) {
                            selectedCategoryFilter = selectedCategoryFilter == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            .padding(.horizontal, -DS.Space.gutter)
        }
        .dsGutter()
        .padding(.top, DS.Space.x2)
        .padding(.bottom, DS.Space.x4)
        .background(DS.Colors.bgApp)
    }

    private var filterMenu: some View {
        Menu {
            Section("Tipo") {
                Button("Tutte") { selectedTypeFilter = nil }
                Button("Entrate") { selectedTypeFilter = .income }
                Button("Uscite") { selectedTypeFilter = .expense }
            }
            if !cachedCategories.isEmpty {
                Section("Categoria") {
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
                    Label(uncategorizedCount > 0
                          ? "Categorizza \(uncategorizedCount) non categorizzate"
                          : "Tutte già categorizzate",
                          systemImage: "sparkles")
                }
                .disabled(isBatchCategorizing || uncategorizedCount == 0)
            }
        } label: {
            Image(systemName: hasActiveFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(hasActiveFilter ? DS.Colors.actionPrimary : DS.Colors.textBody)
                .frame(width: 44, height: 44)
                .background(DS.Colors.surfaceCard)
                .clipShape(Circle())
                .dsShadow(.card)
        }
    }

    private var uncategorizedCount: Int {
        viewModel.transactions.filter { $0.category.isEmpty || $0.category == "Altro" }.count
    }

    // MARK: - List
    //
    // No dividers: separation is whitespace and tile fill.

    private var transactionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.sectionGap, pinnedViews: []) {
                ForEach(cachedGrouped.keys.sorted().reversed(), id: \.self) { month in
                    VStack(alignment: .leading, spacing: DS.Space.x3) {
                        monthSectionHeader(month: month)

                        LazyVStack(spacing: DS.Space.rowGap) {
                            ForEach(cachedGrouped[month] ?? []) { tx in
                                NavigationLink(value: tx) {
                                    DSTransactionRow(
                                        name: tx.displayTitle,
                                        meta: tx.dsMetaParts,
                                        amount: tx.amount.dsSignedAmount(isIncome: tx.type == .income),
                                        isIncome: tx.type == .income,
                                        dimmed: tx.isIgnored
                                    ) {
                                        CategoryIconView(categoryName: tx.category, size: 22,
                                                         showBackground: false)
                                    }
                                }
                                .buttonStyle(DSPressStyle())
                                .contextMenu {
                                    Button("Modifica", systemImage: "pencil") { transactionToEdit = tx }
                                    Button("Elimina", systemImage: "trash", role: .destructive) {
                                        transactionToDelete = tx
                                        showDeleteConfirm = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .dsGutter()
            .padding(.bottom, DS.Space.x8)
        }
        .scrollIndicators(.hidden)
    }

    private var batchOverlay: some View {
        ZStack {
            DS.Palette.navy900.opacity(0.45).ignoresSafeArea()
            VStack(spacing: DS.Space.x4) {
                DSProgressBar(
                    value: batchProgress.total > 0
                        ? Double(batchProgress.done) / Double(batchProgress.total) : 0,
                    color: DS.Colors.actionPrimary
                )
                .frame(width: 220)

                Text("Categorizzazione AI").dsText(DS.Font.h3, color: DS.Colors.textHeading)
                Text("\(batchProgress.done) / \(batchProgress.total)")
                    .dsText(DS.Font.meta, color: DS.Colors.textMuted)
            }
            .padding(DS.Space.x6)
            .background(DS.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
            .dsShadow(.raised)
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

        return HStack(spacing: DS.Space.x2) {
            Text(Self._fmtMonthDisplay.string(from: monthDate).capitalized)
                .dsText(DS.Font.h3, color: DS.Colors.textHeading)
            Spacer(minLength: DS.Space.x2)
            Text(income.dsSignedAmount(isIncome: true))
                .dsText(DS.Font.metaBold, color: DS.Colors.income)
            Text(expense.dsSignedAmount(isIncome: false))
                .dsText(DS.Font.metaBold, color: DS.Colors.expense)
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
