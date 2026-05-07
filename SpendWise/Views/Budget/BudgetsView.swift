import SwiftUI

struct BudgetsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showAdd = false
    @State private var itemToEdit: Budget?
    @State private var itemToDelete: Budget?
    @State private var showDeleteConfirm = false

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

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.budgets.isEmpty {
                    ContentUnavailableView {
                        Label("Nessun budget", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("Imposta un budget mensile per categoria per tenere sotto controllo le spese.")
                    } actions: {
                        Button("Aggiungi budget") { showAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            VStack(spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Speso questo mese")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(totalSpent.euroFormatted)
                                            .font(.title2.bold())
                                            .foregroundStyle(totalSpent > totalLimit ? Color.expense : Color.income)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Budget totale")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(totalLimit.euroFormatted)
                                            .font(.title2.bold())
                                    }
                                }
                                let ratio = totalLimit > 0 ? min(totalSpent / totalLimit, 1) : 0
                                ProgressView(value: ratio)
                                    .tint(ratio > 0.9 ? Color.expense : ratio > 0.7 ? Color(hex: "#F59E0B") : Color.income)
                                    .scaleEffect(y: 1.5)
                            }
                            .padding(.vertical, 6)
                        }

                        Section("Per categoria") {
                            ForEach(activeBudgets) { budget in
                                budgetRow(budget)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            itemToDelete = budget; showDeleteConfirm = true
                                        } label: { Label("Elimina", systemImage: "trash") }
                                        Button { itemToEdit = budget } label: {
                                            Label("Modifica", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
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
    }

    private func budgetRow(_ budget: Budget) -> some View {
        let spent = monthlySpending[budget.category] ?? 0
        let ratio = budget.monthlyLimit > 0 ? min(spent / budget.monthlyLimit, 1) : 0
        let barColor: Color = ratio > 0.9 ? Color.expense : ratio > 0.7 ? Color(hex: "#F59E0B") : Color.income

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CategoryIconView(categoryName: budget.category, size: 36, showBackground: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(budget.category)
                        .font(.subheadline.bold())
                    Text("\(spent.euroFormatted) / \(budget.monthlyLimit.euroFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(ratio * 100))%")
                        .font(.subheadline.bold())
                        .foregroundStyle(barColor)
                    if spent > budget.monthlyLimit {
                        Text("+" + (spent - budget.monthlyLimit).euroFormatted)
                            .font(.caption2.bold())
                            .foregroundStyle(Color.expense)
                    } else {
                        Text((budget.monthlyLimit - spent).euroFormatted + " rimasti")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ProgressView(value: ratio)
                .tint(barColor)
                .scaleEffect(y: 1.3)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BudgetsView(viewModel: .preview)
}
