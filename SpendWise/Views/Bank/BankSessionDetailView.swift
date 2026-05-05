import SwiftUI

struct BankSessionDetailView: View {
    let session: BankSession
    @ObservedObject var viewModel: DashboardViewModel

    private var accountsForSession: [BankAccount] {
        viewModel.resolvedBankAccounts.filter { $0.sessionId == session.sessionId }
    }

    private var totalBalance: Double {
        accountsForSession.filter { !$0.isExcluded }.reduce(0) { $0 + $1.currentBalance }
    }

    var body: some View {
        List {
            // ── Header ──────────────────────────────────────────────
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.appPrimary)
                    Text(session.displayInstitutionName ?? "Banca")
                        .font(.title2.bold())
                    if let country = session.aspsp?.country {
                        Text(flagEmoji(for: country))
                            .font(.title3)
                    }
                    Text(totalBalance.euroFormatted)
                        .font(.title.bold())
                        .foregroundStyle(totalBalance >= 0 ? Color.income : Color.expense)
                    Text("\(accountsForSession.count) conti collegati")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // ── Accounts ────────────────────────────────────────────
            Section("Conti") {
                ForEach(accountsForSession) { account in
                    NavigationLink(value: account) {
                        accountRow(account)
                    }
                }
            }

            // ── Session Info ────────────────────────────────────────
            Section("Dettagli connessione") {
                if let status = session.status {
                    infoRow(icon: "checkmark.shield", label: "Stato",
                            value: status == "AUTHORIZED" ? "Autorizzata" : status)
                }
                if let desc = session.description {
                    infoRow(icon: "text.alignleft", label: "Descrizione", value: desc)
                }
                if let created = session.createdAt {
                    infoRow(icon: "calendar", label: "Collegata il", value: String(created.prefix(10)))
                }
                if let sid = session.sessionId {
                    infoRow(icon: "number", label: "Session ID", value: String(sid.prefix(8)) + "…")
                }
            }
        }
        .navigationTitle(session.displayInstitutionName ?? "Banca")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: BankAccount.self) { account in
            BankAccountDetailView(account: account, viewModel: viewModel)
        }
    }

    // MARK: - Account Row

    private func accountRow(_ account: BankAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForAccountType(account.cashAccountType ?? account.type))
                .font(.title3)
                .foregroundStyle(Color.appPrimary)
                .frame(width: 36, height: 36)
                .background(Color.appPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    Text(account.accountTypeLabel)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.appPrimary.opacity(0.1))
                        .foregroundStyle(Color.appPrimary)
                        .clipShape(Capsule())
                    if account.isCreditCard == true {
                        Text("💳")
                            .font(.caption2)
                    }
                    if account.isExcluded {
                        Text("Escluso")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.currentBalance.currencyFormatted(code: account.displayCurrency))
                    .font(.subheadline.bold())
                    .foregroundStyle(account.currentBalance >= 0 ? Color.income : Color.expense)
                Text(account.displayCurrency)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func infoRow(icon: String, label: String, value: String) -> some View {
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

    private func iconForAccountType(_ type: String) -> String {
        switch type.uppercased() {
        case "CACC", "SVGS": return "building.columns"
        case "CARD": return "creditcard"
        case "CASH": return "banknote"
        case "LOAN": return "dollarsign.circle"
        default: return "building.columns"
        }
    }

    private func flagEmoji(for countryCode: String) -> String {
        countryCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }.map { String($0) }.joined()
    }
}
