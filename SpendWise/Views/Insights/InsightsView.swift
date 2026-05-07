import SwiftUI
import Charts

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showError = false
    @State private var insightsMonthOffset: Int = 0
    @State private var selectedCategoryDrilldown: CategoryBreakdown? = nil

    private var canGoBack: Bool { insightsMonthOffset > -24 }
    private var canGoForward: Bool { insightsMonthOffset < 0 }

    private var selectedDate: Date {
        Calendar.current.date(byAdding: .month, value: insightsMonthOffset, to: Date()) ?? Date()
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f.string(from: selectedDate).capitalized
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    monthNavigator
                    expensePieChart
                    monthlySavingsSection
                    InsightsCalendarView(viewModel: viewModel, month: selectedDate)
                    categoryListSection
                    recurringSection
                    aiInsightsSection
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.loadInsights() }
                    } label: {
                        if viewModel.isLoadingInsights {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoadingInsights)
                }
            }
            .onChange(of: viewModel.errorMessage) { _, msg in showError = msg != nil }
            .alert("Errore", isPresented: $showError) {
                Button("OK") { viewModel.dismissError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(item: $selectedCategoryDrilldown) { cat in
                CategoryTransactionsSheet(
                    category: cat,
                    date: selectedDate,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - Month Navigator

    private var monthNavigator: some View {
        HStack(spacing: 16) {
            Button { withAnimation { insightsMonthOffset -= 1 } } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundStyle(canGoBack ? .primary : .secondary)
            }
            .disabled(!canGoBack)

            Text(monthLabel)
                .font(.headline)
                .frame(minWidth: 160)
                .multilineTextAlignment(.center)

            Button { withAnimation { insightsMonthOffset += 1 } } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
                    .foregroundStyle(canGoForward ? .primary : .secondary)
            }
            .disabled(!canGoForward)
        }
        .padding(.vertical, 4)
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { v in
                    if v.translation.width > 0, canGoBack { withAnimation { insightsMonthOffset -= 1 } }
                    else if v.translation.width < 0, canGoForward { withAnimation { insightsMonthOffset += 1 } }
                }
        )
    }

    // MARK: - Expense Pie Chart

    private var expensePieChart: some View {
        let breakdown = viewModel.expenseCategoryBreakdown(for: selectedDate)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Uscite per categoria")
                .font(.headline)
                .padding(.horizontal)

            if breakdown.isEmpty {
                Text("Nessuna uscita in \(monthLabel)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart(breakdown) { item in
                    SectorMark(
                        angle: .value("Importo", item.amount),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color(hex: item.color))
                    .cornerRadius(4)
                    .annotation(position: .overlay) {
                        if item.percentage > 8 {
                            Text(item.percentage.percentFormatted)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(height: 240)
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(breakdown) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: item.color))
                                .frame(width: 10, height: 10)
                            Text(item.category)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(item.amount.euroFormatted)
                                .font(.caption.bold())
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    // MARK: - Recurring Payments

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pagamenti ricorrenti", systemImage: "repeat.circle.fill")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    RecurringsView(viewModel: viewModel)
                } label: {
                    Text("Vedi tutti")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal)

            if viewModel.activeRecurrings.isEmpty {
                Text("Nessun abbonamento attivo.\nAggiungili dal tab Abbonamenti.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Costo mensile")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.monthlyRecurringCost.euroFormatted)
                            .font(.title3.bold()).foregroundStyle(Color.expense)
                    }
                    Spacer()
                    Text("\(viewModel.activeRecurrings.count) abbonamenti")
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.1))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)

                Divider().padding(.horizontal)

                ForEach(viewModel.activeRecurrings.prefix(4)) { r in
                    HStack(spacing: 12) {
                        CategoryIconView(categoryName: r.category, size: 36, showBackground: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.subheadline).lineLimit(1)
                            Text(r.recurringTiming.label)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((r.type == .expense ? "-" : "+") + r.amount.euroFormatted)
                            .font(.subheadline.bold())
                            .foregroundStyle(r.type == .expense ? Color.expense : Color.income)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                if viewModel.activeRecurrings.count > 4 {
                    NavigationLink {
                        RecurringsView(viewModel: viewModel)
                    } label: {
                        Text("Vedi altri \(viewModel.activeRecurrings.count - 4)…")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func frequencyLabel(_ freq: Transaction.RecurringFrequency?) -> String {
        switch freq {
        case .weekly:  return "Settimanale"
        case .monthly: return "Mensile"
        case .yearly:  return "Annuale"
        case nil:      return "Ricorrente"
        }
    }

    // MARK: - Category List

    private var categoryListSection: some View {
        let breakdown = viewModel.expenseCategoryBreakdown(for: selectedDate)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Categorie del mese")
                .font(.headline)
                .padding(.horizontal)

            if breakdown.isEmpty {
                Text("Nessuna spesa in \(monthLabel)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(breakdown) { item in
                        Button {
                            selectedCategoryDrilldown = item
                        } label: {
                            categoryListRow(item: item, max: breakdown.first?.amount ?? 1)
                        }
                        .buttonStyle(.plain)
                        if item.id != breakdown.last?.id {
                            Divider().padding(.horizontal)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func categoryListRow(item: CategoryBreakdown, max: Double) -> some View {
        HStack(spacing: 12) {
            CategoryIconView(categoryName: item.category, size: 36, showBackground: true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.category)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    Text(item.amount.euroFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.expense)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 5)
                        Capsule()
                            .fill(Color(hex: item.color))
                            .frame(width: geo.size.width * CGFloat(item.amount / max), height: 5)
                    }
                }
                .frame(height: 5)
                Text(item.percentage.percentFormatted + " del totale")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }



    // MARK: - Monthly Savings

    private var monthlySavingsSection: some View {
        let income   = viewModel.monthlyIncomeTotal(for: selectedDate)
        let expenses = viewModel.monthlyExpensesTotal(for: selectedDate)
        let savings  = income - expenses
        let ratio    = income > 0 ? min(max(savings / income, 0), 1) : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Riepilogo del mese")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 0) {
                savingsTile(label: "Entrate", value: income, icon: "arrow.down.circle.fill", color: Color.income)
                Divider()
                savingsTile(label: "Uscite", value: expenses, icon: "arrow.up.circle.fill", color: Color.expense)
                Divider()
                VStack(spacing: 4) {
                    Image(systemName: savings >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(savings >= 0 ? Color.income : Color.expense)
                    Text(savings >= 0 ? "+\(savings.euroFormatted)" : savings.euroFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(savings >= 0 ? Color.income : Color.expense)
                    Text("Risparmio")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            if income > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Tasso di risparmio")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(ratio * 100))%")
                            .font(.caption.bold())
                            .foregroundStyle(ratio >= 0.2 ? Color.income : ratio >= 0 ? .orange : Color.expense)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 6)
                            Capsule()
                                .fill(ratio >= 0.2 ? Color.income : ratio >= 0 ? .orange : Color.expense)
                                .frame(width: geo.size.width * CGFloat(ratio), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal)
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func savingsTile(label: String, value: Double, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value.euroFormatted).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Consigli AI", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if viewModel.isLoadingInsights {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(.horizontal)

            if viewModel.insights.isEmpty && !viewModel.isLoadingInsights {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Tocca il pulsante aggiorna per ottenere consigli personalizzati basati sulle tue transazioni.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await viewModel.loadInsights() }
                    } label: {
                        Label("Genera Consigli", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ForEach(viewModel.insights) { insight in
                    InsightCardView(insight: insight)
                        .padding(.horizontal)
                }
            }
        }
        .cardStyle()
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Category Transactions Sheet
struct CategoryTransactionsSheet: View {
    let category: CategoryBreakdown
    let date: Date
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    private var transactions: [Transaction] {
        let cal = Calendar.current
        return viewModel.transactions.filter { tx in
            guard !tx.isIgnored, tx.type == .expense, tx.category == category.category else { return false }
            guard let txDate = cal.date(from: cal.dateComponents([.year, .month, .day], from: {
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
                return df.date(from: String(tx.date.prefix(10))) ?? Date.distantPast
            }())) else { return false }
            return cal.isDate(txDate, equalTo: date, toGranularity: .month)
        }.sorted { $0.date > $1.date }
    }

    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; f.locale = Locale(identifier: "it_IT")
        return f.string(from: date).capitalized
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        CategoryIconView(categoryName: category.category, size: 48, showBackground: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.category).font(.title3.bold())
                            Text(monthLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(category.amount.euroFormatted)
                                .font(.title3.bold()).foregroundStyle(Color.expense)
                            Text(category.percentage.percentFormatted)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("\(transactions.count) transazioni") {
                    ForEach(transactions) { tx in
                        NavigationLink(value: tx) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tx.description.isEmpty ? tx.category : tx.description)
                                        .font(.subheadline).lineLimit(1)
                                    Text(String(tx.date.prefix(10)))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("-" + tx.amount.euroFormatted)
                                    .font(.subheadline.bold()).foregroundStyle(Color.expense)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(category.category)
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
        }
    }
}

// MARK: - Insight Card
struct InsightCardView: View {
    let insight: FinancialInsight

    private var impactColor: Color { Color(hex: insight.impact.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(impactColor)
                Text(insight.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Spacer()
                Text(insight.impact.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(impactColor.opacity(0.15))
                    .foregroundStyle(impactColor)
                    .clipShape(Capsule())
            }
            Text(insight.advice)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(impactColor.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}


#Preview {
    InsightsView(viewModel: .preview)
}
