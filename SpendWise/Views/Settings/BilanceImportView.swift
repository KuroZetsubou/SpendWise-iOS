import SwiftUI
import UniformTypeIdentifiers

struct BilanceImportView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importTotal: Int = 0
    @State private var parsedTransactions: [BilanceCSVParser.BilanceTx] = []
    @State private var importResult: ImportResult?
    @State private var showResult = false
    @State private var errorMessage: String?
    @State private var skipInternalTransfers = true
    @State private var skipIgnored = true
    /// Conto name → bankAccount ID (empty = non assegnato)
    @State private var contoMappings: [String: String] = [:]

    struct ImportResult {
        var imported: Int
        var skipped: Int
        var errors: [String]
    }

    private var uniqueConti: [String] {
        Array(Set(parsedTransactions.map { $0.conto }.filter { !$0.isEmpty })).sorted()
    }

    private var filteredTransactions: [BilanceCSVParser.BilanceTx] {
        parsedTransactions
            .filter { tx in
                if skipInternalTransfers && tx.categoria == "Giroconti" { return false }
                if skipIgnored && tx.categoria == "Escluso" { return false }
                return true
            }
            .sorted { $0.data > $1.data }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── About ─────────────────────────────────────────────
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color.appPrimary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Importa da Bilance")
                                .font(.headline)
                            Text("Importa le transazioni esportate dall'app Bilance in formato CSV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // ── Instructions ──────────────────────────────────────
                Section("Come esportare da Bilance") {
                    stepRow("1", "Apri l'app Bilance")
                    stepRow("2", "Impostazioni → Esporta → CSV")
                    stepRow("3", "Seleziona il file esportato qui sotto")
                }

                // ── Options ───────────────────────────────────────────
                Section("Opzioni importazione") {
                    Toggle("Escludi giroconti interni", isOn: $skipInternalTransfers)
                    Toggle("Escludi transazioni ignorate", isOn: $skipIgnored)
                }

                // ── Conto mapping ─────────────────────────────────────
                if !uniqueConti.isEmpty {
                    Section {
                        ForEach(uniqueConti, id: \.self) { conto in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conto)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Picker("Conto SpendWise", selection: Binding(
                                    get: { contoMappings[conto] ?? "" },
                                    set: { contoMappings[conto] = $0 }
                                )) {
                                    Text("— Non assegnato —").tag("")
                                    ForEach(viewModel.resolvedBankAccounts) { acc in
                                        Text(acc.displayName).tag(acc.id ?? "")
                                    }
                                }
                                .pickerStyle(.menu)
                                .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Label("Associa conti Bilance", systemImage: "building.columns")
                    } footer: {
                        Text("Associa ogni conto Bilance a un conto SpendWise per raggruppare le transazioni.")
                            .font(.caption2)
                    }
                }

                // ── Import button ─────────────────────────────────────
                Section {
                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

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

                // ── Preview ───────────────────────────────────────────
                if !parsedTransactions.isEmpty {
                    Section {
                        HStack {
                            Label("\(filteredTransactions.count) da importare", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                            Spacer()
                            if parsedTransactions.count != filteredTransactions.count {
                                Text("\(parsedTransactions.count - filteredTransactions.count) escluse")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Anteprima")
                    }

                    Section {
                        ForEach(filteredTransactions.prefix(8), id: \.rimessa) { tx in
                            previewRow(tx)
                        }
                        if filteredTransactions.count > 8 {
                            Text("e altre \(filteredTransactions.count - 8) transazioni...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button {
                            Task { await importTransactions() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Importa \(filteredTransactions.count) transazioni", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.bold())
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isImporting || filteredTransactions.isEmpty)
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
                                .tint(Color.appPrimary)
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
            .navigationTitle("Importa da Bilance")
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
                    let skippedMsg = r.skipped > 0 ? "\n\(r.skipped) già presenti (skippate)." : ""
                    let errMsg = r.errors.isEmpty ? "" : "\n\nErrori: \(r.errors.prefix(3).joined(separator: ", "))"
                    Text("\(r.imported) transazioni importate.\(skippedMsg)\(errMsg)")
                }
            }
        }
    }

    // MARK: - Subviews

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

    private func previewRow(_ tx: BilanceCSVParser.BilanceTx) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.titolo.isEmpty ? tx.esercente : tx.titolo)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text("\(tx.categoria)\(tx.sottocategoria.isEmpty ? "" : " · \(tx.sottocategoria)") · \(String(tx.data.prefix(10)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(tx.importo >= 0 ? "+" : "")\(tx.importo, format: .number.precision(.fractionLength(2)))€")
                .font(.caption.monospacedDigit())
                .foregroundStyle(tx.importo >= 0 ? Color.income : Color.expense)
        }
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        parsedTransactions = []
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            // Parse CSV on background thread to avoid blocking the UI
            Task.detached(priority: .userInitiated) {
                do {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let parsed = try BilanceCSVParser.parse(csv: content)
                    await MainActor.run { self.parsedTransactions = parsed }
                } catch {
                    await MainActor.run { self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func importTransactions() async {
        guard let userId = viewModel.userId else { return }
        let toImport = filteredTransactions.map { tx -> Transaction in
            let accountId = contoMappings[tx.conto].flatMap { $0.isEmpty ? nil : $0 }
            return BilanceCSVParser.toTransaction(tx: tx, userId: userId, accountId: accountId)
        }
        importTotal = toImport.count
        importProgress = 0
        isImporting = true

        do {
            // Write in batches of 450 — single progress step per batch
            let batchSize = 450
            let chunks = stride(from: 0, to: toImport.count, by: batchSize).map {
                Array(toImport[$0..<min($0 + batchSize, toImport.count)])
            }
            var done = 0
            for chunk in chunks {
                try await FirestoreService.shared.batchAddTransactions(chunk)
                done += chunk.count
                importProgress = Double(done) / Double(max(toImport.count, 1))
            }
            parsedTransactions = []
            contoMappings = [:]
            importProgress = 1.0
            importResult = ImportResult(imported: done, skipped: 0, errors: [])
        } catch {
            importResult = ImportResult(imported: 0, skipped: 0, errors: [error.localizedDescription])
        }

        isImporting = false
        showResult = true
    }
}

#Preview {
    BilanceImportView(viewModel: .preview)
}
