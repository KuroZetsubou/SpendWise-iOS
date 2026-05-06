import SwiftUI
import Charts

struct InsightsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showError = false
    @State private var insightsMonthOffset: Int = 0

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
                    monthlyAreaChart
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

    // MARK: - Monthly Trend (Area Chart)

    private var monthlyAreaChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trend ultimi 6 mesi")
                .font(.headline)
                .padding(.horizontal)

            if viewModel.monthlyChartData.isEmpty {
                Text("Nessun dato disponibile")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let incomeData = viewModel.monthlyChartData.filter { $0.type == "Entrate" }
                let expenseData = viewModel.monthlyChartData.filter { $0.type == "Uscite" }

                Chart {
                    ForEach(incomeData) { item in
                        AreaMark(x: .value("Mese", item.month), y: .value("Importo", item.amount))
                            .foregroundStyle(Color.income.gradient.opacity(0.3))
                        LineMark(x: .value("Mese", item.month), y: .value("Importo", item.amount))
                            .foregroundStyle(Color.income)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .symbol(.circle)
                    }
                    ForEach(expenseData) { item in
                        AreaMark(x: .value("Mese", item.month), y: .value("Importo", item.amount))
                            .foregroundStyle(Color.expense.gradient.opacity(0.3))
                        LineMark(x: .value("Mese", item.month), y: .value("Importo", item.amount))
                            .foregroundStyle(Color.expense)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .symbol(.circle)
                    }
                }
                .chartForegroundStyleScale(["Entrate": Color.income, "Uscite": Color.expense])
                .chartLegend(position: .bottom)
                .frame(height: 200)
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

    // MARK: - AI Insights

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
