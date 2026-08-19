import SwiftUI

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showError = false
    @State private var insightsMonthOffset: Int = 0
    @State private var selectedCategoryDrilldown: CategoryBreakdown? = nil
    @State private var heroHeight: CGFloat = 320

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

    private var breakdown: [CategoryBreakdown] {
        viewModel.expenseCategoryBreakdown(for: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.sectionGap) {
                    heroHeader
                        .dsReportHeroHeight()

                    VStack(spacing: DS.Space.sectionGap) {
                        savingsSummary
                        quickAccess
                        categoryListSection
                        recurringSection
                        aiInsightsSection
                    }
                    .dsGutter()
                }
                .padding(.bottom, DS.Space.tabBarHeight + DS.Space.x8)
            }
            .scrollIndicators(.hidden)
            .dsHeroScrollBackground(height: heroHeight)
            .ignoresSafeArea(edges: .top)
            .onPreferenceChange(DSHeroHeightKey.self) { heroHeight = $0 }
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

    // MARK: - Hero
    //
    // The kit's Budget screen: the donut sits on the navy gradient, total in the centre,
    // segments in category colors.

    private var heroHeader: some View {
        VStack(spacing: DS.Space.x5) {
            HStack(spacing: DS.Space.x3) {
                Text("Report").dsText(DS.Font.h2, color: DS.Colors.textOnDark)
                Spacer(minLength: DS.Space.x2)
                DSIconButton(viewModel.isLoadingInsights ? "hourglass" : "arrow.clockwise",
                             tone: .onDark, size: 44) {
                    Task { await viewModel.loadInsights() }
                }
                .disabled(viewModel.isLoadingInsights)
            }

            monthStepper

            if breakdown.isEmpty {
                VStack(spacing: DS.Space.x2) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(DS.Colors.textOnDarkMuted)
                    Text("Nessuna uscita in \(monthLabel)")
                        .dsText(DS.Font.body, color: DS.Colors.textOnDarkMuted)
                }
                .padding(.vertical, DS.Space.x8)
            } else {
                DSDonutChart(
                    segments: donutSegments,
                    total: totalExpenses.dsAmount,
                    label: "Uscite totali",
                    size: 210,
                    thickness: 20,
                    onDark: true
                )
                .padding(.vertical, DS.Space.x2)

                DSDonutLegend(segments: donutSegments.prefix(4).map { $0 },
                              onDark: true) { $0.dsAmount }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.x16)
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

    private var totalExpenses: Double {
        breakdown.reduce(0) { $0 + $1.amount }
    }

    private var donutSegments: [DSDonutSegment] {
        breakdown.map {
            DSDonutSegment(label: $0.category, value: $0.amount, color: Color(hex: $0.color))
        }
    }

    private var monthStepper: some View {
        HStack(spacing: DS.Space.x2) {
            stepperButton(icon: "chevron.left", enabled: canGoBack) { insightsMonthOffset -= 1 }
            Text(monthLabel)
                .dsText(DS.Font.labelBold, color: DS.Colors.textOnDark)
                .frame(maxWidth: .infinity)
            stepperButton(icon: "chevron.right", enabled: canGoForward) { insightsMonthOffset += 1 }
        }
        .padding(DS.Space.x2)
        .background(DS.Colors.scrimOnDark)
        .clipShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { v in
                    if v.translation.width > 0, canGoBack {
                        withAnimation(DS.Motion.standard) { insightsMonthOffset -= 1 }
                    } else if v.translation.width < 0, canGoForward {
                        withAnimation(DS.Motion.standard) { insightsMonthOffset += 1 }
                    }
                }
        )
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

    // MARK: - Savings summary

    private var savingsSummary: some View {
        let income   = viewModel.monthlyIncomeTotal(for: selectedDate)
        let expenses = viewModel.monthlyExpensesTotal(for: selectedDate)
        let savings  = income - expenses
        let ratio    = income > 0 ? min(max(savings / income, 0), 1) : 0

        return DSStatCard(
            title: "Riepilogo del Mese",
            caption: "Risparmio netto",
            value: savings.dsSignedAmount(isIncome: savings >= 0),
            delta: income > 0 ? "\(Int(ratio * 100))% risparmiato" : nil,
            deltaTone: ratio >= 0.2 ? .success : (savings >= 0 ? .warning : .danger)
        ) {
            VStack(spacing: DS.Space.x4) {
                HStack(spacing: DS.Space.rowGap) {
                    DSCashflowRow(label: "Entrate", amount: income.dsAmount,
                                  isIncome: true,
                                  fraction: income > 0 ? 1 : 0)
                    DSCashflowRow(label: "Uscite", amount: expenses.dsAmount,
                                  isIncome: false,
                                  fraction: income > 0 ? min(expenses / income, 1) : 1)
                }
                .padding(.bottom, DS.Space.x2)

                if income > 0 {
                    DSProgressBar(
                        value: ratio,
                        color: ratio >= 0.2 ? DS.Colors.income
                             : (savings >= 0 ? DS.Palette.amber500 : DS.Colors.expense),
                        leftLabel: "Tasso di risparmio",
                        rightLabel: "\(Int(ratio * 100))%"
                    )
                }
            }
        }
    }

    // MARK: - Quick access
    //
    // Two-up tile grid, 12pt gap — the kit's services grid shape.

    private var quickAccess: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.rowGap),
                            GridItem(.flexible(), spacing: DS.Space.rowGap)],
                  spacing: DS.Space.rowGap) {
            NavigationLink {
                BudgetsView(viewModel: viewModel)
            } label: {
                quickTile(icon: "chart.bar.xaxis", title: "Budget",
                          caption: "\(viewModel.budgets.filter { $0.isActive }.count) attivi")
            }
            .buttonStyle(DSPressStyle())

            NavigationLink {
                RecurringCalendarView(viewModel: viewModel)
            } label: {
                quickTile(icon: "calendar", title: "Calendario",
                          caption: "Pagamenti in scadenza")
            }
            .buttonStyle(DSPressStyle())
        }
    }

    private func quickTile(icon: String, title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.x2 + 2) {
            DSIconTile(icon, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsText(DS.Font.h3, color: DS.Colors.textHeading)
                Text(caption).dsText(DS.Font.meta, color: DS.Colors.textMuted).lineLimit(1)
            }
        }
        .padding(DS.Space.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    // MARK: - Category list

    private var categoryListSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Categorie del Mese")

            if breakdown.isEmpty {
                DSEmptyState(icon: "square.grid.2x2",
                             title: "Nessuna Spesa",
                             message: "Non ci sono uscite registrate in \(monthLabel).")
            } else {
                VStack(spacing: DS.Space.rowGap) {
                    ForEach(breakdown) { item in
                        Button {
                            selectedCategoryDrilldown = item
                        } label: {
                            categoryRow(item: item, max: breakdown.first?.amount ?? 1)
                        }
                        .buttonStyle(DSPressStyle())
                    }
                }
            }
        }
    }

    private func categoryRow(item: CategoryBreakdown, max: Double) -> some View {
        let tint = Color(hex: item.color)
        return HStack(spacing: DS.Space.x3) {
            DSIconTile(AppCategory.categoryIcons[item.category] ?? "tag",
                       size: 42, background: tint.opacity(0.12), foreground: tint)

            VStack(alignment: .leading, spacing: DS.Space.x1 + 2) {
                HStack {
                    Text(item.category)
                        .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.x2)
                    Text(item.amount.dsAmount)
                        .dsText(DS.Font.labelBold, color: DS.Colors.textHeading)
                }
                DSProgressBar(value: max > 0 ? item.amount / max : 0, color: tint, height: 6)
                Text(item.percentage.dsPercent + " del totale")
                    .dsText(DS.Font.meta, color: DS.Colors.textMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.gray400)
        }
        .padding(DS.Space.cardPad)
        .background(DS.Colors.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    // MARK: - Recurring payments

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Pagamenti Ricorrenti") {
                if !viewModel.activeRecurrings.isEmpty {
                    NavigationLink {
                        RecurringsView(viewModel: viewModel)
                    } label: {
                        Text("Vedi Tutti").dsText(DS.Font.label, color: DS.Colors.textLink)
                    }
                }
            }

            if viewModel.activeRecurrings.isEmpty {
                DSEmptyState(icon: "repeat",
                             title: "Nessun Abbonamento",
                             message: "Aggiungi i pagamenti ricorrenti per vedere il costo fisso mensile.")
            } else {
                DSCard(.tint) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Costo mensile").dsText(DS.Font.meta, color: DS.Colors.textSecondary)
                            Text(viewModel.monthlyRecurringCost.dsAmount)
                                .dsText(DS.Font.Style(size: 22, weight: .bold, lineHeight: 28,
                                                      trackingEm: -0.02),
                                        color: DS.Colors.expense)
                        }
                        Spacer(minLength: DS.Space.x2)
                        DSBadge("\(viewModel.activeRecurrings.count) attivi", tone: .info)
                    }
                }

                VStack(spacing: DS.Space.rowGap) {
                    ForEach(viewModel.activeRecurrings.prefix(4)) { r in
                        DSTransactionRow(
                            name: r.name,
                            meta: [r.recurringTiming.label, r.category],
                            amount: r.amount.dsSignedAmount(isIncome: r.type != .expense),
                            isIncome: r.type != .expense
                        ) {
                            CategoryIconView(categoryName: r.category, size: 22,
                                             showBackground: false)
                        }
                    }
                }

                if viewModel.activeRecurrings.count > 4 {
                    NavigationLink {
                        RecurringsView(viewModel: viewModel)
                    } label: {
                        Text("Vedi altri \(viewModel.activeRecurrings.count - 4)")
                            .dsText(DS.Font.labelBold, color: DS.Colors.textLink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.x2)
                    }
                }
            }
        }
    }

    // MARK: - AI insights

    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Consigli AI") {
                if viewModel.isLoadingInsights {
                    ProgressView().scaleEffect(0.7).tint(DS.Colors.actionPrimary)
                }
            }

            if viewModel.insights.isEmpty && !viewModel.isLoadingInsights {
                DSPromoBanner(
                    title: "Analizza le Tue Spese",
                    message: "Genera consigli personalizzati basati sulle tue transazioni per capire dove intervenire.",
                    icon: "sparkles",
                    actionTitle: "Genera Consigli",
                    action: { Task { await viewModel.loadInsights() } }
                )
            } else {
                VStack(spacing: DS.Space.rowGap) {
                    ForEach(viewModel.insights) { insight in
                        InsightCardView(insight: insight)
                    }
                }
            }
        }
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
            ScrollView {
                VStack(spacing: DS.Space.sectionGap) {
                    DSCard(.card) {
                        HStack(spacing: DS.Space.x4) {
                            DSIconTile(AppCategory.categoryIcons[category.category] ?? "tag",
                                       size: 48,
                                       background: Color(hex: category.color).opacity(0.12),
                                       foreground: Color(hex: category.color))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.category)
                                    .dsText(DS.Font.h3, color: DS.Colors.textHeading)
                                Text(monthLabel).dsText(DS.Font.meta, color: DS.Colors.textMuted)
                            }
                            Spacer(minLength: DS.Space.x2)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(category.amount.dsAmount)
                                    .dsText(DS.Font.h3, color: DS.Colors.expense)
                                Text(category.percentage.dsPercent)
                                    .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Space.x4) {
                        DSSectionHeader("\(transactions.count) Transazioni")
                        LazyVStack(spacing: DS.Space.rowGap) {
                            ForEach(transactions) { tx in
                                NavigationLink(value: tx) {
                                    DSTransactionRow(
                                        name: tx.displayTitle,
                                        meta: tx.dsMetaParts,
                                        amount: tx.amount.dsSignedAmount(isIncome: false),
                                        isIncome: false
                                    ) {
                                        CategoryIconView(categoryName: tx.category, size: 22,
                                                         showBackground: false)
                                    }
                                }
                                .buttonStyle(DSPressStyle())
                            }
                        }
                    }
                }
                .dsGutter()
                .padding(.vertical, DS.Space.x5)
            }
            .scrollIndicators(.hidden)
            .background(DS.Colors.bgApp)
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
        DSCard(.card) {
            VStack(alignment: .leading, spacing: DS.Space.x2 + 2) {
                HStack(spacing: DS.Space.x3) {
                    DSIconTile("lightbulb.fill", size: 36,
                               background: impactColor.opacity(0.12), foreground: impactColor)
                    Text(insight.title)
                        .dsText(DS.Font.h3, color: DS.Colors.textHeading)
                        .lineLimit(2)
                    Spacer(minLength: DS.Space.x2)
                }
                Text(insight.advice)
                    .dsText(DS.Font.body, color: DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                DSBadge(insight.impact.label, tone: .neutral)
            }
        }
    }
}

#Preview {
    InsightsView(viewModel: .preview)
}
