import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var chartSelection: String? = nil
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    monthHeaderView
                    statsGrid

                    if !viewModel.monthlyChartData.isEmpty {
                        monthlyBarChart
                    }

                    recentTransactionsSection
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddTransaction = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = abs(value.translation.height)
                        guard abs(horizontal) > vertical else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
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

    // MARK: - Month Header (with navigation arrows)

    private var monthHeaderView: some View {
        HStack(spacing: 12) {
            // Back arrow
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { viewModel.goToPreviousMonth() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(viewModel.canGoBack ? .primary : .tertiary)
            }
            .disabled(!viewModel.canGoBack)

            VStack(spacing: 2) {
                Text(viewModel.selectedMonthLabel)
                    .font(.title3.bold())
                    .animation(.none, value: viewModel.selectedMonthOffset)
                HStack(spacing: 4) {
                    Text("saldo:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.currentMonthBalance.euroFormatted)
                        .font(.caption.bold())
                        .foregroundStyle(viewModel.currentMonthBalance >= 0 ? Color.income : Color.expense)
                }
                // Projected end-of-month balance (only for current month, only if recurrings exist)
                if viewModel.isCurrentMonth && !viewModel.activeRecurrings.isEmpty {
                    let projected = viewModel.projectedMonthEndBalance
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text("previsto fine mese: \(projected.euroFormatted)")
                            .font(.caption2)
                    }
                    .foregroundStyle(projected >= 0 ? Color.income.opacity(0.8) : Color.expense.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)

            // Forward arrow (disabled if current month)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { viewModel.goToNextMonth() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(viewModel.canGoForward ? .primary : .tertiary)
            }
            .disabled(!viewModel.canGoForward)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .overlay(alignment: .bottom) {
            if !viewModel.isCurrentMonth {
                Text("Scorri o usa le frecce per navigare")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .offset(y: 18)
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCardView(
                title: "Entrate",
                value: viewModel.currentMonthIncome.euroFormatted,
                icon: "arrow.down.circle.fill",
                color: Color.income
            )
            StatCardView(
                title: "Uscite",
                value: viewModel.currentMonthExpenses.euroFormatted,
                icon: "arrow.up.circle.fill",
                color: Color.expense
            )
            if !viewModel.bankAccounts.isEmpty {
                StatCardView(
                    title: "Saldo Bancario",
                    value: viewModel.totalBankBalance.euroFormatted,
                    icon: "building.columns",
                    color: .appPrimary,
                    subtitle: "\(viewModel.bankAccounts.filter { !$0.isExcluded }.count) conto/i"
                )
            }
            StatCardView(
                title: "Transazioni",
                value: "\(viewModel.currentMonthTransactions.count)",
                icon: "list.bullet.rectangle",
                color: .appSecondary
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Monthly Grouped Bar Chart (last 6 months)

    private var monthlyBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ultimi 6 mesi")
                .font(.headline)
                .padding(.horizontal)

            Chart(viewModel.monthlyChartData) { item in
                BarMark(
                    x: .value("Mese", item.month),
                    y: .value("Importo", item.amount),
                    width: .ratio(0.4)
                )
                .foregroundStyle(by: .value("Tipo", item.type))
                .position(by: .value("Tipo", item.type))
                .cornerRadius(4)

                if let sel = chartSelection, sel == item.month {
                    RuleMark(x: .value("Mese", sel))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top, spacing: 4) {
                            chartTooltip(for: sel)
                        }
                }
            }
            .chartForegroundStyleScale([
                "Entrate": Color.income,
                "Uscite": Color.expense
            ])
            .chartLegend(position: .bottom, alignment: .center)
            .chartXSelection(value: $chartSelection)
            .frame(height: 220)
            .padding(.horizontal)
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func chartTooltip(for month: String) -> some View {
        let items = viewModel.monthlyChartData.filter { $0.month == month }
        let income  = items.first(where: { $0.type == "Entrate" })?.amount ?? 0
        let expense = items.first(where: { $0.type == "Uscite"  })?.amount ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(month).font(.caption.bold())
            HStack(spacing: 6) {
                Circle().fill(Color.income).frame(width: 8, height: 8)
                Text(income.euroFormatted).font(.caption)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.expense).frame(width: 8, height: 8)
                Text(expense.euroFormatted).font(.caption)
            }
            Divider()
            Text((income - expense).euroFormatted)
                .font(.caption.bold())
                .foregroundStyle(income >= expense ? Color.income : Color.expense)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    // MARK: - Recent Transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transazioni recenti")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if viewModel.recentTransactions.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna transazione", systemImage: "tray")
                } description: {
                    Text("Aggiungi la tua prima transazione con il pulsante +")
                }
                .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.recentTransactions) { tx in
                        TransactionRowView(
                            transaction: tx,
                            onDelete: {
                                if let id = tx.id {
                                    Task { await viewModel.deleteTransaction(id: id) }
                                }
                            },
                            onEdit: { transactionToEdit = tx }
                        )
                        .padding(.horizontal)
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    DashboardView(viewModel: .preview)
}
