import SwiftUI
import UniformTypeIdentifiers

struct TradeRepublicImportView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importTotal: Int = 0
    @State private var importResult: ImportResult?
    @State private var showResult = false
    @State private var parsedTransactions: [TradeRepublicCSVParser.TRTransaction] = []
    @State private var showPreview = false
    @State private var errorMessage: String?

    struct ImportResult {
        var imported: Int
        var skipped: Int
        var errors: [String]
    }

    var body: some View {
        NavigationStack {
            List {
                // ── About ────────────────────────────────────────────
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "building.columns.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trade Republic")
                                .font(.headline)
                            Text("Importa le transazioni dal tuo conto Trade Republic tramite file CSV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // ── Option 1: Enable Banking ──────────────────────────
//                Section {
//                    VStack(alignment: .leading, spacing: 10) {
//                        Label("Via Open Banking (Consigliato)", systemImage: "link.circle.fill")
//                            .font(.subheadline.bold())
//                            .foregroundStyle(Color.appPrimary)
//                        Text("Trade Republic ha una licenza bancaria PSD2. Puoi collegarlo direttamente come qualsiasi altra banca:")
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                        HStack(spacing: 8) {
//                            stepBadge("1", "Vai in Banca")
//                            Image(systemName: "chevron.right")
//                                .font(.caption2)
//                                .foregroundStyle(.secondary)
//                            stepBadge("2", "🇩🇪 Germania")
//                            Image(systemName: "chevron.right")
//                                .font(.caption2)
//                                .foregroundStyle(.secondary)
//                            stepBadge("3", "\"Trade Republic\"")
//                        }
//                        .font(.caption2)
//                    }
//                    .padding(.vertical, 4)
//                } header: {
//                    Text("Opzione 1 — Connessione diretta")
//                }

                // ── Option 2: CSV Import ──────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Esporta CSV dall'app Trade Republic", systemImage: "square.and.arrow.up")
                            .font(.subheadline.bold())
                        steps
                    }
                    .padding(.vertical, 4)

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if #available(iOS 26.0, *) {
                        
                        Button {
                            showFilePicker = true
                        } label: {
                            HStack {
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                    Text("Importazione...")
                                } else {
                                    Label("Seleziona file CSV", systemImage: "doc.text.badge.plus")
                                        .font(.subheadline.bold())
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isImporting || viewModel.userId == nil)
                    }
                    else
                    {
                        Button {
                            showFilePicker = true
                        } label: {
                            HStack {
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                    Text("Importazione...")
                                } else {
                                    Label("Seleziona file CSV", systemImage: "doc.text.badge.plus")
                                        .font(.subheadline.bold())
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting || viewModel.userId == nil)
                    }

                } header: {
                    Text("Importa CSV")
                }

                // ── Preview ───────────────────────────────────────────
                if !parsedTransactions.isEmpty {
                    Section("Anteprima (\(parsedTransactions.count) transazioni)") {
                        ForEach(parsedTransactions.prefix(5), id: \.transactionId) { tx in
                            previewRow(tx)
                        }
                        if parsedTransactions.count > 5 {
                            Text("e altre \(parsedTransactions.count - 5) transazioni...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await importTransactions() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Importa \(parsedTransactions.count) transazioni", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.bold())
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isImporting)
                    }
                }
            }
            // ── Progress overlay ─────────────────────────────────────
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(spacing: 20) {
                            Text("Importazione in corso...")
                                .font(.headline)
                                .foregroundStyle(.white)
                            ProgressView(value: importProgress, total: 1.0)
                                .progressViewStyle(.linear)
                                .tint(.green)
                                .frame(width: 260)
                            Text("\(Int(importProgress * Double(importTotal))) / \(importTotal)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .interactiveDismissDisabled(isImporting)
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
            .navigationTitle("Trade Republic")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .disabled(isImporting)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, .text, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Importazione completata", isPresented: $showResult) {
                Button("OK") { if importResult?.errors.isEmpty == true { dismiss() } }
            } message: {
                if let r = importResult {
                    Text(importAlertMessage(r))
                }
            }
        }
    }

    // MARK: - Subviews

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepRow("1", "Apri l'app Trade Republic.")
            stepRow("2", "Tocca l'icona del profilo in alto a destra")
            stepRow("3", "Scorri fino a \"Estratto Conto\" → \"Esporta Transazioni\".")
            stepRow("4", "Scegli il periodo che vuoi esportare.")
            stepRow("5", "Seleziona il file scaricato qui sotto.")
        }
    }

    private func stepRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.caption2.bold())
                .frame(width: 18, height: 18)
                .background(Color.appPrimary.opacity(0.15))
                .foregroundStyle(Color.appPrimary)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stepBadge(_ num: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(num)
                .font(.caption2.bold())
                .frame(width: 16, height: 16)
                .background(Color.appPrimary.opacity(0.2))
                .foregroundStyle(Color.appPrimary)
                .clipShape(Circle())
            Text(label)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func previewRow(_ tx: TradeRepublicCSVParser.TRTransaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.displayName.isEmpty ? tx.typeLabel : tx.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text("\(tx.typeLabel) · \(tx.date)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(tx.netAmount >= 0 ? "+" : "")\(tx.netAmount, format: .number.precision(.fractionLength(2))) \(tx.currency)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(tx.netAmount >= 0 ? Color.income : Color.expense)
        }
    }

    // MARK: - Actions

    private func importAlertMessage(_ r: ImportResult) -> String {
        var msg = "\(r.imported) transazioni importate."
        if r.skipped > 0 { msg += "\n\(r.skipped) già presenti, saltate." }
        if !r.errors.isEmpty { msg += "\n\nErrori: \(r.errors.joined(separator: ", "))" }
        return msg
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task.detached(priority: .userInitiated) {
                do {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let content = try String(contentsOf: url, encoding: .utf8)
                    var parsed = try TradeRepublicCSVParser.parse(csv: content)
                    // Client-side dedup by transactionId + sort descending by date
                    var seen = Set<String>()
                    parsed = parsed.filter { seen.insert($0.transactionId).inserted }
                    parsed.sort { $0.date > $1.date }
                    await MainActor.run { self.parsedTransactions = parsed }
                } catch {
                    await MainActor.run { self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func importTransactions() async {
        guard let userId = viewModel.userId else { return }

        isImporting = true
        importProgress = 0

        do {
            // Step 1: ensure the manual TR bank account exists and get its ID
            let accountId = try await FirestoreService.shared.findOrCreateManualTRAccount(userId: userId)

            // Step 2: fetch already-imported transaction IDs to skip duplicates (all sources)
            let existingIds = try await FirestoreService.shared.fetchExistingBankTransactionIds(
                userId: userId
            )

            // Step 3: map to Transaction objects, filtering out duplicates
            var allMapped = parsedTransactions.map { TradeRepublicCSVParser.toTransaction(trTx: $0, userId: userId) }
            for i in allMapped.indices { allMapped[i].accountId = accountId }

            let toImport = allMapped.filter { tx in
                guard let bankId = tx.bankTransactionId else { return true }
                return !existingIds.contains(bankId)
            }
            let skipped = allMapped.count - toImport.count

            importTotal = max(toImport.count, 1)

            // Step 4: batch write only new transactions
            if toImport.isEmpty {
                importProgress = 1.0
                importResult = ImportResult(imported: 0, skipped: skipped, errors: [])
            } else {
                let batchSize = 450
                let chunks = stride(from: 0, to: toImport.count, by: batchSize).map {
                    Array(toImport[$0..<min($0 + batchSize, toImport.count)])
                }
                var done = 0
                for chunk in chunks {
                    try await FirestoreService.shared.batchAddTransactions(chunk)
                    done += chunk.count
                    importProgress = Double(done) / Double(importTotal)
                }
                importProgress = 1.0
                importResult = ImportResult(imported: done, skipped: skipped, errors: [])
            }

            // Step 5: drop generic Open Banking duplicates now covered by the richer CSV rows
            let replaced = (try? await TransactionSyncService.reconcileTradeRepublic(userId: userId)) ?? 0
            if replaced > 0 {
                importResult?.errors.append("Rimosse \(replaced) transazioni Open Banking generiche, sostituite dai dati CSV.")
            }

            parsedTransactions = []
            await viewModel.refreshBankSessions()
        } catch {
            importResult = ImportResult(imported: 0, skipped: 0, errors: [error.localizedDescription])
        }

        isImporting = false
        showResult = true
    }
}

#Preview {
    TradeRepublicImportView(viewModel: .preview)
}
