import SwiftUI

struct BudgetsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showAdd = false
    @State private var itemToEdit: Budget?
    @State private var itemToDelete: Budget?
    @State private var showDeleteConfirm = false
    @State private var heroHeight: CGFloat = 340

    // Current month spending per category (excluding ignored/transfer)
    private var monthlySpending: [String: Double] {
        var result: [String: Double] = [:]
        for tx in viewModel.currentMonthTransactions {
            guard tx.type == .expense, !tx.isIgnored, tx.isTransfer != true else { continue }
            result[tx.category, default: 0] += tx.amount
        }
        return result
    }

    private var activeBudgets: [Budget] { viewModel.budgets.filter { $0.isActive } }
    private var totalLimit: Double { activeBudgets.reduce(0) { $0 + $1.monthlyLimit } }
    private var totalSpent: Double { activeBudgets.reduce(0) { $0 + (monthlySpending[$1.category] ?? 0) } }
    private var totalRatio: Double { totalLimit > 0 ? min(totalSpent / totalLimit, 1) : 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.sectionGap) {
                heroHeader
                    .dsReportHeroHeight()

                VStack(spacing: DS.Space.sectionGap) {
                    if viewModel.budgets.isEmpty {
                        DSEmptyState(
                            icon: "chart.bar.xaxis",
                            title: "Nessun Budget",
                            message: "Imposta un limite mensile per categoria per tenere le spese sotto controllo.",
                            actionTitle: "Aggiungi Budget",
                            action: { showAdd = true }
                        )
                    } else {
                        categorySection
                    }
                }
                .dsGutter()
            }
            .padding(.bottom, DS.Space.x12 + DS.Space.x8)
        }
        .scrollIndicators(.hidden)
        .dsHeroScrollBackground(height: heroHeight)
        .ignoresSafeArea(edges: .top)
        .onPreferenceChange(DSHeroHeightKey.self) { heroHeight = $0 }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay(alignment: .bottom) {
            if !viewModel.budgets.isEmpty {
                // Floating "Add New" pill over a white protection fade.
                DSButton("Aggiungi Budget", icon: "plus", variant: .primary, size: .large) {
                    showAdd = true
                }
                .dsShadow(.fab)
                .padding(.bottom, DS.Space.x5)
                .padding(.top, DS.Space.x8)
                .frame(maxWidth: .infinity)
                .background(DS.Gradients.fadeWhite)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddBudgetView(viewModel: viewModel)
        }
        .sheet(item: $itemToEdit) { budget in
            AddBudgetView(viewModel: viewModel, existing: budget)
        }
        .confirmationDialog("Eliminare il budget per \"\(itemToDelete?.category ?? "")\"?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let id = itemToDelete?.id { Task { await viewModel.deleteBudget(id: id) } }
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    // MARK: - Hero
    //
    // The kit's Budget screen: the donut on the navy ground, total in the centre.

    private var heroHeader: some View {
        VStack(spacing: DS.Space.x5) {
            Text("Budget")
                .dsText(DS.Font.h3, color: DS.Colors.textOnDark)
                .frame(maxWidth: .infinity)

            if activeBudgets.isEmpty {
                Text("Nessun budget attivo")
                    .dsText(DS.Font.body, color: DS.Colors.textOnDarkMuted)
                    .padding(.vertical, DS.Space.x8)
            } else {
                DSDonutChart(
                    segments: donutSegments,
                    total: totalSpent.dsAmount,
                    label: "Speso su \(totalLimit.dsAmountCompact)",
                    size: 210,
                    thickness: 20,
                    onDark: true
                )

                DSBadge("\(Int(totalRatio * 100))% del budget",
                        tone: totalRatio > 0.9 ? .danger : (totalRatio > 0.7 ? .warning : .success))
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

    private var donutSegments: [DSDonutSegment] {
        activeBudgets.compactMap { budget in
            let spent = monthlySpending[budget.category] ?? 0
            guard spent > 0 else { return nil }
            return DSDonutSegment(label: budget.category, value: spent,
                                  color: Color(hex: AppCategory.categoryColors[budget.category] ?? "#3856FC"))
        }
    }

    // MARK: - Per category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Per Categoria")

            VStack(spacing: DS.Space.rowGap) {
                ForEach(activeBudgets) { budget in
                    budgetRow(budget)
                        .contextMenu {
                            Button("Modifica", systemImage: "pencil") { itemToEdit = budget }
                            Button("Elimina", systemImage: "trash", role: .destructive) {
                                itemToDelete = budget
                                showDeleteConfirm = true
                            }
                        }
                }
            }
        }
    }

    private func budgetRow(_ budget: Budget) -> some View {
        let spent = monthlySpending[budget.category] ?? 0
        let ratio = budget.monthlyLimit > 0 ? min(spent / budget.monthlyLimit, 1) : 0
        let barColor: Color = ratio > 0.9 ? DS.Colors.expense
                            : ratio > 0.7 ? DS.Palette.amber500
                            : DS.Colors.income

        return VStack(alignment: .leading, spacing: DS.Space.x3) {
            HStack(spacing: DS.Space.x3) {
                CategoryIconView(categoryName: budget.category, size: 42, showBackground: true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(budget.category)
                        .dsText(DS.Font.h3, color: DS.Colors.textBody)
                        .lineLimit(1)
                    Text("\(spent.dsAmount) di \(budget.monthlyLimit.dsAmount)")
                        .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                }

                Spacer(minLength: DS.Space.x2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(ratio * 100))%")
                        .dsText(DS.Font.Style(size: 16, weight: .bold, lineHeight: 22), color: barColor)
                    if spent > budget.monthlyLimit {
                        Text("+" + (spent - budget.monthlyLimit).dsAmount)
                            .dsText(DS.Font.meta, color: DS.Colors.expense)
                    } else {
                        Text((budget.monthlyLimit - spent).dsAmount + " rimasti")
                            .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                    }
                }
            }

            DSProgressBar(value: ratio, color: barColor)
        }
        .padding(DS.Space.cardPad)
        .background(DS.Colors.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

#Preview {
    NavigationStack { BudgetsView(viewModel: .preview) }
}
