import SwiftUI
import Charts

struct BankAccountDetailView: View {
    let account: BankAccount
    @ObservedObject var viewModel: DashboardViewModel

    private var accountTransactions: [Transaction] {
        viewModel.transactions
            .filter { $0.accountId == account.id }
            .sorted { $0.date > $1.date }
    }

    private var totalSpent: Double {
        accountTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        accountTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    /// For manual accounts, balance = income − expense (live from transactions).
    /// For Open-Banking accounts, use the stored/fetched balance.
    private var displayBalance: Double {
        account.isManual == true ? (totalIncome - totalSpent) : account.currentBalance
    }

    var body: some View {
        List {
            // ── Header ──────────────────────────────────────────────
            Section {
                VStack(spacing: 8) {
                    Image(systemName: account.isManual == true ? "square.and.pencil" : account.isCreditCard == true ? "creditcard.fill" : "building.columns.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.appPrimary)
                    Text(account.displayName)
                        .font(.title3.bold())
                    if let inst = account.institutionName {
                        Text(inst)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if account.isManual == true {
                        Text("Conto manuale")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.appPrimary.opacity(0.12))
                            .foregroundStyle(Color.appPrimary)
                            .clipShape(Capsule())
                    }
                    Text(displayBalance.currencyFormatted(code: account.displayCurrency))
                        .font(.title.bold())
                        .foregroundStyle(displayBalance >= 0 ? Color.income : Color.expense)
                    if account.isManual == true {
                        Text("Saldo calcolato dalle transazioni importate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 16) {
                        Label(account.accountTypeLabel, systemImage: "tag")
                        Label(account.displayCurrency, systemImage: "dollarsign.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // ── Credit Card Plafond ─────────────────────────────────
            if account.isCreditCard == true, let limit = account.creditLimit, limit > 0 {
                Section("Plafond carta di credito") {
                    creditCardPlafondView(limit: limit)
                }
            }

            // ── Account Details ─────────────────────────────────────
            Section("Dettagli conto") {
                if let iban = account.officialName, !iban.isEmpty {
                    detailRow(icon: "creditcard", label: "IBAN / ID", value: iban)
                }
                detailRow(icon: "tag", label: "Tipo", value: account.accountTypeLabel)
                detailRow(icon: "dollarsign.circle", label: "Valuta", value: account.displayCurrency)
                if account.isCreditCard == true {
                    if let limit = account.creditLimit, limit > 0 {
                        detailRow(icon: "arrow.up.circle", label: "Limite credito", value: limit.euroFormatted)
                    }
                    if let day = account.paymentDay, day > 0 {
                        detailRow(icon: "calendar.badge.exclamationmark", label: "Giorno pagamento", value: "\(day) del mese")
                    }
                }
                if account.isExcluded {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(.secondary)
                        Text("Escluso dal totale patrimonio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // ── Summary ─────────────────────────────────────────────
            if !accountTransactions.isEmpty {
                Section("Riepilogo") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Entrate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("+" + totalIncome.euroFormatted)
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.income)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Uscite")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("-" + totalSpent.euroFormatted)
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.expense)
                        }
                    }
                    .padding(.vertical, 4)

                    Text("\(accountTransactions.count) transazioni importate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Transactions ────────────────────────────────────────
            if accountTransactions.isEmpty {
                Section("Transazioni") {
                    ContentUnavailableView {
                        Label("Nessuna transazione", systemImage: "tray")
                    } description: {
                        Text("Non ci sono transazioni importate per questo conto.")
                    }
                }
            } else {
                let grouped = Dictionary(grouping: accountTransactions) { tx in
                    String(tx.date.prefix(7))
                }
                ForEach(grouped.keys.sorted().reversed(), id: \.self) { month in
                    Section(header: Text(monthLabel(month))) {
                        ForEach(grouped[month] ?? []) { tx in
                            NavigationLink(value: tx) {
                                compactTransactionRow(tx)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                        }
                    }
                }
            }
        }
        .navigationTitle(account.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: Transaction.self) { tx in
            TransactionDetailView(transaction: tx, viewModel: viewModel)
        }
    }

    // MARK: - Credit Card Plafond

    @ViewBuilder
    private func creditCardPlafondView(limit: Double) -> some View {
        let available = account.currentBalance
        let used = limit - available
        let usageRatio = min(max(used / limit, 0), 1)

        VStack(spacing: 12) {
            // Gauge
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * usageRatio)
                    .stroke(
                        usageRatio > 0.8 ? Color.expense : usageRatio > 0.5 ? Color(hex: "#F59E0B") : Color.income,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                VStack(spacing: 2) {
                    Text("\(Int(usageRatio * 100))%")
                        .font(.title2.bold())
                    Text("utilizzato")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            .padding(.top, 4)

            // Numbers
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("Disponibile")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(available.euroFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.income)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 2) {
                    Text("Utilizzato")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(used.euroFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.expense)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 2) {
                    Text("Limite")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(limit.euroFormatted)
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity)
            }

            // Monthly spending chart (last 6 months)
            if #available(iOS 16, macOS 13, *) {
                let monthlyData = plafondMonthlyData
                if !monthlyData.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spesa mensile")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Chart(monthlyData, id: \.month) { item in
                            BarMark(
                                x: .value("Mese", item.label),
                                y: .value("Spesa", item.amount)
                            )
                            .foregroundStyle(item.amount > limit * 0.8 ? Color.expense : Color.appPrimary)
                            .cornerRadius(4)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(v.euroFormatted)
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .frame(height: 140)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private struct MonthlySpending {
        let month: String
        let label: String
        let amount: Double
    }

    private var plafondMonthlyData: [MonthlySpending] {
        let cal = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "MMM"
        labelFormatter.locale = Locale(identifier: "it_IT")

        var result: [MonthlySpending] = []
        for offset in (0..<6).reversed() {
            guard let date = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let key = formatter.string(from: date)
            let label = labelFormatter.string(from: date).capitalized
            let spent = accountTransactions
                .filter { $0.type == .expense && $0.date.hasPrefix(key) }
                .reduce(0) { $0 + $1.amount }
            result.append(MonthlySpending(month: key, label: label, amount: spent))
        }
        return result
    }

    // MARK: - Compact Transaction Row

    private func compactTransactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: 10) {
            CategoryIconView(categoryName: tx.category, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(tx.description.isEmpty ? tx.category : tx.description)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(tx.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text((tx.type == .income ? "+" : "-") + tx.amount.euroFormatted)
                    .font(.subheadline.bold())
                    .foregroundStyle(tx.type == .income ? Color.income : Color.expense)
                Text(String(tx.date.suffix(5)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.appPrimary)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func monthLabel(_ yyyyMM: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "it_IT")
        guard let date = formatter.date(from: yyyyMM) else { return yyyyMM }
        let display = DateFormatter()
        display.dateFormat = "MMMM yyyy"
        display.locale = Locale(identifier: "it_IT")
        return display.string(from: date).capitalized
    }
}
