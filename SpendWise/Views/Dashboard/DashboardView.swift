import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var onOpenSettings: (() -> Void)? = nil

    @State private var showAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var balanceHidden = false
    @State private var chartIndex = 0
    @State private var chartMode: ChartMode = .expenses
    @State private var heroHeight: CGFloat = 320

    private enum ChartMode: Hashable { case expenses, income }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.sectionGap) {
                    heroHeader
                        .dsReportHeroHeight()

                    VStack(spacing: DS.Space.sectionGap) {
                        statsGrid
                        if !viewModel.monthlyChartData.isEmpty { monthlyChart }
                        recentTransactionsSection
                    }
                    .dsGutter()
                }
                .padding(.bottom, DS.Space.tabBarHeight + DS.Space.x8)
            }
            .scrollIndicators(.hidden)
            .dsHeroScrollBackground(height: heroHeight)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(DSHeroHeightKey.self) { heroHeight = $0 }
            .navigationDestination(for: Transaction.self) { tx in
                TransactionDetailView(transaction: tx, viewModel: viewModel)
            }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        guard abs(horizontal) > abs(value.translation.height) else { return }
                        withAnimation(DS.Motion.standard) {
                            if horizontal < 0 { viewModel.goToPreviousMonth() }
                            else             { viewModel.goToNextMonth() }
                        }
                    }
            )
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView(viewModel: viewModel)
            }
            .sheet(item: $transactionToEdit) { tx in
                AddTransactionView(viewModel: viewModel, existingTransaction: tx)
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

    // MARK: - Hero header
    //
    // The navy gradient panel bleeds to the edges and full width, carrying the greeting,
    // the month balance and the month stepper.

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.x5) {
            HStack(spacing: DS.Space.x3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ciao!").dsText(DS.Font.h2, color: DS.Colors.textOnDark)
                    Text("Ecco il quadro del mese")
                        .dsText(DS.Font.meta, color: DS.Colors.textOnDarkMuted)
                }
                Spacer(minLength: DS.Space.x2)
                if let onOpenSettings {
                    DSIconButton("gearshape", tone: .onDark, size: 44, action: onOpenSettings)
                }
            }

            DSBalanceHeader(
                label: "Saldo di \(viewModel.selectedMonthLabel)",
                amount: viewModel.currentMonthBalance.dsAmount,
                caption: projectionCaption,
                isHidden: $balanceHidden
            )

            monthStepper
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.x16)
        .padding(.bottom, DS.Space.x6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Gradients.hero)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: DS.Radius.xl2,
                bottomTrailingRadius: DS.Radius.xl2, topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    private var projectionCaption: String? {
        guard viewModel.isCurrentMonth, !viewModel.activeRecurrings.isEmpty else { return nil }
        return "Previsto a fine mese • \(viewModel.projectedMonthEndBalance.dsAmount)"
    }

    private var monthStepper: some View {
        HStack(spacing: DS.Space.x2) {
            stepperButton(icon: "chevron.left", enabled: viewModel.canGoBack) {
                viewModel.goToPreviousMonth()
            }

            Text(viewModel.selectedMonthLabel.capitalized)
                .dsText(DS.Font.labelBold, color: DS.Colors.textOnDark)
                .frame(maxWidth: .infinity)

            stepperButton(icon: "chevron.right", enabled: viewModel.canGoForward) {
                viewModel.goToNextMonth()
            }
        }
        .padding(.horizontal, DS.Space.x2)
        .padding(.vertical, DS.Space.x2)
        .background(DS.Colors.scrimOnDark)
        .clipShape(Capsule())
    }

    private func stepperButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.standard) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Colors.textOnDark)
                .frame(width: 30, height: 30)
                .background(DS.Colors.scrimOnDark)
                .clipShape(Circle())
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(DSPressStyle())
        .disabled(!enabled)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.rowGap),
                            GridItem(.flexible(), spacing: DS.Space.rowGap)],
                  spacing: DS.Space.rowGap) {
            DSStatTile(title: "Entrate",
                       value: viewModel.currentMonthIncome.dsAmount,
                       icon: "arrow.down.left",
                       tint: DS.Colors.income)
            DSStatTile(title: "Uscite",
                       value: viewModel.currentMonthExpenses.dsAmount,
                       icon: "arrow.up.right",
                       tint: DS.Colors.expense)
            if !viewModel.bankAccounts.isEmpty {
                DSStatTile(title: "Saldo bancario",
                           value: viewModel.totalBankBalance.dsAmount,
                           icon: "building.columns",
                           tint: DS.Colors.actionPrimary,
                           subtitle: "\(viewModel.bankAccounts.filter { !$0.isExcluded }.count) conti attivi")
            }
            DSStatTile(title: "Transazioni",
                       value: "\(viewModel.currentMonthTransactions.count)",
                       icon: "list.bullet",
                       tint: DS.Palette.purple500)
        }
    }

    // MARK: - Monthly chart

    private var chartBars: [DSBarItem] {
        let wanted = chartMode == .expenses ? "Uscite" : "Entrate"
        return viewModel.monthlyChartData
            .filter { $0.type == wanted }
            .map { DSBarItem(label: String($0.month.prefix(3)),
                             value: $0.amount,
                             display: $0.amount.dsAmountCompact) }
    }

    private var monthlyChart: some View {
        DSStatCard(
            title: "Ultimi 6 mesi",
            caption: chartMode == .expenses ? "Totale uscite" : "Totale entrate",
            value: chartBars.indices.contains(chartIndex)
                ? chartBars[chartIndex].value.dsAmount
                : nil,
            delta: chartDelta,
            deltaTone: chartDeltaIsPositive ? .success : .danger
        ) {
            VStack(spacing: DS.Space.x4) {
                DSSegmentedTabs(
                    options: [(.expenses, "Uscite"), (.income, "Entrate")],
                    selection: $chartMode
                )
                DSBarChart(
                    data: chartBars,
                    activeIndex: $chartIndex,
                    height: 140,
                    color: chartMode == .expenses ? DS.Colors.expense : DS.Colors.income
                )
            }
        }
        .onAppear { chartIndex = max(chartBars.count - 1, 0) }
        .onChange(of: chartMode) { _, _ in chartIndex = max(chartBars.count - 1, 0) }
    }

    /// Month-over-month change on the selected column.
    private var chartDeltaValue: Double? {
        let bars = chartBars
        guard bars.indices.contains(chartIndex), chartIndex > 0 else { return nil }
        let previous = bars[chartIndex - 1].value
        guard previous > 0 else { return nil }
        return (bars[chartIndex].value - previous) / previous * 100
    }

    private var chartDelta: String? {
        guard let delta = chartDeltaValue else { return nil }
        return (delta >= 0 ? "+" : "-") + abs(delta).dsPercent
    }

    /// Spending more is a bad delta; earning more is a good one.
    private var chartDeltaIsPositive: Bool {
        guard let delta = chartDeltaValue else { return true }
        return chartMode == .expenses ? delta <= 0 : delta >= 0
    }

    // MARK: - Recent transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Transazioni Recenti",
                            actionTitle: viewModel.recentTransactions.isEmpty ? nil : "Vedi Tutte",
                            action: { viewModel.selectedTab = .transactions })

            if viewModel.recentTransactions.isEmpty {
                DSEmptyState(
                    icon: "tray",
                    title: "Nessuna Transazione",
                    message: "Aggiungi il primo movimento con il pulsante blu in basso.",
                    actionTitle: "Aggiungi Movimento",
                    action: { showAddTransaction = true }
                )
            } else {
                LazyVStack(spacing: DS.Space.rowGap) {
                    ForEach(viewModel.recentTransactions) { tx in
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
                                if let id = tx.id {
                                    Task { await viewModel.deleteTransaction(id: id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row copy helpers

extension Transaction {
    /// Row title: the description, falling back to the category.
    var displayTitle: String {
        description.isEmpty ? category : description
    }

    /// "Cibo & Spesa • 3 mag" — two facts joined by a dot separator.
    var dsMetaParts: [String] {
        var parts = [category]
        if let sub = subCategory, !sub.isEmpty { parts.append(sub) }
        if let date = date.asDate {
            let f = DateFormatter()
            f.locale = Locale(identifier: "it_IT")
            f.dateFormat = "d MMM"
            parts.append(f.string(from: date))
        }
        return parts
    }
}

#Preview {
    DashboardView(viewModel: .preview)
}
