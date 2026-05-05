import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DashboardViewModel

    var existingTransaction: Transaction? = nil

    // Form state
    @State private var selectedType: Transaction.TransactionType = .expense
    @State private var amountString = ""
    @State private var description = ""
    @State private var selectedCategory = ""
    @State private var selectedSubCategory = ""
    @State private var selectedDate = Date()
    @State private var isRecurring = false
    @State private var recurringFrequency: Transaction.RecurringFrequency = .monthly
    @State private var tags = ""
    @State private var isIgnored = false

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSuggestingCategory = false
    @State private var categorySuggestion: String? = nil
    @State private var suggestionConfidence: Double = 0
    @State private var suggestionSource: String = ""

    private var isEditing: Bool { existingTransaction != nil }

    private var availableParentCategories: [AppCategory] {
        let catType = AppCategory.CategoryType(rawValue: selectedType.rawValue) ?? .expense
        return viewModel.allCategories(ofType: catType)
    }

    private var availableSubCategories: [AppCategory] {
        guard let parent = availableParentCategories.first(where: { $0.name == selectedCategory }) else { return [] }
        return viewModel.subCategories(ofParent: parent.effectiveId)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Type Picker
                Section {
                    Picker("Tipo", selection: $selectedType) {
                        ForEach(Transaction.TransactionType.allCases, id: \.self) { type in
                            Text(type == .income ? "Entrata" : "Uscita").tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedType) { _, _ in
                        selectedCategory = availableParentCategories.first?.name ?? ""
                        selectedSubCategory = ""
                    }
                }

                // Amount + Date
                Section("Importo e Data") {
                    HStack {
                        Text("€")
                            .foregroundStyle(.secondary)
                        TextField("0,00", text: $amountString)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    DatePicker("Data", selection: $selectedDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "it_IT"))
                }

                // Description + AI suggestion
                Section("Descrizione") {
                    TextField("Descrizione transazione", text: $description)
                        .onChange(of: description) { _, newValue in
                            categorySuggestion = nil
                            // Auto-suggest after 0.6s debounce
                            if newValue.count >= 3 {
                                Task {
                                    try? await Task.sleep(for: .milliseconds(600))
                                    guard description == newValue else { return }
                                    await suggestCategory()
                                }
                            }
                        }

                    if isSuggestingCategory {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Analisi AI in corso…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let suggestion = categorySuggestion {
                        HStack(spacing: 8) {
                            Image(systemName: sourceIcon(suggestionSource))
                                .foregroundStyle(.primary)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Suggerimento: **\(suggestion)**")
                                    .font(.caption)
                                Text("\(sourceLabel(suggestionSource)) · \(Int(suggestionConfidence * 100))% confidenza")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if suggestion != selectedCategory {
                                Button("Usa") {
                                    withAnimation { selectedCategory = suggestion }
                                }
                                .font(.caption.bold())
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.income)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Category
                Section("Categoria") {
                    if availableParentCategories.isEmpty {
                        Text("Nessuna categoria disponibile")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Categoria", selection: $selectedCategory) {
                            ForEach(availableParentCategories) { cat in
                                HStack {
                                    CategoryIconView(categoryName: cat.name, size: 20, showBackground: false)
                                    Text(cat.name)
                                }
                                .tag(cat.name)
                            }
                        }

                        if !availableSubCategories.isEmpty {
                            Picker("Sotto-categoria", selection: $selectedSubCategory) {
                                Text("Nessuna").tag("")
                                ForEach(availableSubCategories) { sub in
                                    Text(sub.name).tag(sub.name)
                                }
                            }
                        }

                        // AI categorize button
                        Button {
                            Task { await suggestCategory() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSuggestingCategory {
                                    ProgressView().scaleEffect(0.75)
                                    Text("Analisi in corso…")
                                } else {
                                    Image(systemName: "apple.intelligence")
                                    Text("Categorizza con AI")
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(description.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .primary)
                        }
                        .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isSuggestingCategory)
                    }
                }

                // Tags
                Section("Tag (opzionale)") {
                    TextField("es. vacanze, lavoro", text: $tags)
                }

                // Recurring
                Section("Ricorrente") {
                    Toggle("Transazione ricorrente", isOn: $isRecurring)
                    if isRecurring {
                        Picker("Frequenza", selection: $recurringFrequency) {
                            Text("Settimanale").tag(Transaction.RecurringFrequency.weekly)
                            Text("Mensile").tag(Transaction.RecurringFrequency.monthly)
                            Text("Annuale").tag(Transaction.RecurringFrequency.yearly)
                        }
                    }
                }

                // Ignore
                Section("Opzioni") {
                    Toggle("Ignora nelle statistiche", isOn: $isIgnored)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifica Transazione" : "Nuova Transazione")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Salva" : "Aggiungi") {
                        Task { await saveTransaction() }
                    }
                    .disabled(isLoading)
                    .bold()
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    // MARK: - Populate

    private func populateIfEditing() {
        guard let tx = existingTransaction else {
            selectedType = .expense
            selectedCategory = availableParentCategories.first?.name ?? ""
            return
        }
        selectedType = tx.type
        amountString = String(format: "%.2f", tx.amount).replacingOccurrences(of: ".", with: ",")
        description = tx.description
        selectedCategory = tx.category
        selectedSubCategory = tx.subCategory ?? ""
        selectedDate = tx.date.asDate ?? Date()
        isRecurring = tx.recurring ?? false
        recurringFrequency = tx.recurringFrequency ?? .monthly
        tags = tx.tags?.joined(separator: ", ") ?? ""
        isIgnored = tx.ignored ?? false
    }

    // MARK: - Save

    private func saveTransaction() async {
        let amountClean = amountString.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(amountClean), amount > 0 else {
            errorMessage = "Inserisci un importo valido."
            return
        }
        guard !selectedCategory.isEmpty else {
            errorMessage = "Seleziona una categoria."
            return
        }
        guard let userId = viewModel.userId else {
            errorMessage = "Utente non autenticato."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let tagList = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let tx = Transaction(
            id: existingTransaction?.id,
            userId: userId,
            amount: amount,
            type: selectedType,
            category: selectedCategory,
            subCategory: selectedSubCategory.isEmpty ? nil : selectedSubCategory,
            description: description,
            date: selectedDate.isoDateString,
            createdAt: nil,
            tags: tagList.isEmpty ? nil : tagList,
            recurring: isRecurring ? true : nil,
            recurringFrequency: isRecurring ? recurringFrequency : nil,
            ignored: isIgnored ? true : nil
        )

        if let id = existingTransaction?.id {
            var updates: [String: Any] = [
                "amount": amount,
                "type": selectedType.rawValue,
                "category": selectedCategory,
                "description": description,
                "date": selectedDate.isoDateString,
                "ignored": isIgnored,
                "recurring": isRecurring
            ]
            if !selectedSubCategory.isEmpty { updates["subCategory"] = selectedSubCategory }
            if isRecurring { updates["recurringFrequency"] = recurringFrequency.rawValue }
            if !tagList.isEmpty { updates["tags"] = tagList }
            await viewModel.updateTransaction(id: id, updates: updates)
        } else {
            await viewModel.addTransaction(tx)
        }

        dismiss()
    }

    // MARK: - AI Suggestion

    @MainActor
    private func suggestCategory() async {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSuggestingCategory = true
        defer { isSuggestingCategory = false }

        let amountClean = amountString.replacingOccurrences(of: ",", with: ".")
        let amount = Double(amountClean) ?? 0

        if let uid = viewModel.userId {
            await CategorizationPipeline.shared.prepare(userId: uid)
        }

        let result = await CategorizationPipeline.shared.categorize(
            description: description,
            amount: amount,
            type: selectedType,
            availableCategories: viewModel.categories.map(\.name)
        )
        categorySuggestion = result.category
        suggestionConfidence = result.confidence
        suggestionSource = result.source

        // Auto-apply if very confident
        if result.confidence >= 0.85 && selectedCategory.isEmpty {
            withAnimation { selectedCategory = result.category }
        }
    }

    private func sourceIcon(_ source: String) -> String {
        switch source {
        case "memory.exact":   return "checkmark.seal.fill"
        case "memory.similar": return "sparkle"
        case "rule.transfer":  return "arrow.left.arrow.right"
        case "ai.apple":       return "apple.intelligence"
        default:               return "wand.and.sparkles"
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "memory.exact":   return "Memoria esatta"
        case "memory.similar": return "Pattern simile"
        case "rule.transfer":  return "Rilevato giroconto"
        case "ai.apple":       return "Apple Intelligence"
        default:               return "Euristica"
        }
    }
}
