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
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                        typeSelector
                        amountAndDate
                        descriptionSection
                        categorySection
                        optionsSection

                        if let error = errorMessage {
                            DSCard(.card, padding: DS.Space.cardPad) {
                                HStack(spacing: DS.Space.x2) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(DS.Colors.expense)
                                    Text(error).dsText(DS.Font.body, color: DS.Colors.expense)
                                }
                            }
                        }
                    }
                    .dsGutter()
                    .padding(.top, DS.Space.x4)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)

                saveBar
            }
            .background(DS.Colors.bgApp)
            .navigationTitle(isEditing ? "Modifica Transazione" : "Nuova Transazione")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .onAppear { populateIfEditing() }
        }
    }

    // MARK: - Type

    private var typeSelector: some View {
        DSSegmentedTabs(
            options: [(Transaction.TransactionType.expense, "Uscita"),
                      (Transaction.TransactionType.income, "Entrata")],
            selection: $selectedType
        )
        .onChange(of: selectedType) { _, _ in
            selectedCategory = availableParentCategories.first?.name ?? ""
            selectedSubCategory = ""
        }
    }

    // MARK: - Amount and date

    private var amountAndDate: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSAmountInput(text: $amountString)

            VStack(alignment: .leading, spacing: DS.Space.x2) {
                Text("Data").dsText(DS.Font.labelBold, color: DS.Colors.textSecondary)
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DS.Colors.textMuted)
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "it_IT"))
                    Spacer()
                }
                .padding(.horizontal, DS.Space.cardPad)
                .frame(height: 52)
                .background(DS.Colors.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous))
            }
        }
    }

    // MARK: - Description and AI suggestion

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            DSTextField("Descrizione", placeholder: "es. Supermercato Esselunga",
                        text: $description, icon: "text.alignleft")
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
                HStack(spacing: DS.Space.x2) {
                    ProgressView().scaleEffect(0.7).tint(DS.Colors.actionPrimary)
                    Text("Analisi AI in corso…").dsText(DS.Font.meta, color: DS.Colors.textMuted)
                }
            } else if let suggestion = categorySuggestion {
                DSCard(.tint, padding: DS.Space.cardPad) {
                    HStack(spacing: DS.Space.x3) {
                        DSIconTile(sourceIcon(suggestionSource), size: 36,
                                   background: DS.Colors.actionPrimary,
                                   foreground: DS.Colors.textOnDark)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion).dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                            Text("\(sourceLabel(suggestionSource)) • \(Int(suggestionConfidence * 100))% confidenza")
                                .dsText(DS.Font.meta, color: DS.Colors.textSecondary)
                        }
                        Spacer(minLength: DS.Space.x2)
                        if suggestion != selectedCategory {
                            DSButton("Usa", variant: .primary, size: .small) {
                                withAnimation(DS.Motion.standard) { selectedCategory = suggestion }
                            }
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(DS.Colors.income)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Category
    //
    // Horizontal scroll row of category chips, per the kit's category selector.

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            HStack {
                Text("Categoria").dsText(DS.Font.labelBold, color: DS.Colors.textSecondary)
                Spacer()
                Button {
                    Task { await suggestCategory() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                        Text("Categorizza con AI").dsText(DS.Font.metaBold, color: DS.Colors.textLink)
                    }
                    .foregroundStyle(DS.Colors.textLink)
                }
                .buttonStyle(DSPressStyle())
                .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isSuggestingCategory)
                .opacity(description.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }

            if availableParentCategories.isEmpty {
                Text("Nessuna categoria disponibile")
                    .dsText(DS.Font.body, color: DS.Colors.textMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.x2) {
                        ForEach(availableParentCategories) { cat in
                            DSChip(cat.name,
                                   icon: AppCategory.categoryIcons[cat.name],
                                   isSelected: selectedCategory == cat.name) {
                                selectedCategory = cat.name
                                selectedSubCategory = ""
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                }
                .padding(.horizontal, -DS.Space.gutter)

                if !availableSubCategories.isEmpty {
                    Menu {
                        Button("Nessuna") { selectedSubCategory = "" }
                        ForEach(availableSubCategories) { sub in
                            Button(sub.name) { selectedSubCategory = sub.name }
                        }
                    } label: {
                        HStack(spacing: DS.Space.x3) {
                            Text("Sotto-categoria").dsText(DS.Font.body, color: DS.Colors.textSecondary)
                            Spacer(minLength: DS.Space.x2)
                            Text(selectedSubCategory.isEmpty ? "Nessuna" : selectedSubCategory)
                                .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Palette.gray400)
                        }
                        .padding(.horizontal, DS.Space.cardPad)
                        .frame(height: 52)
                        .background(DS.Colors.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            DSTextField("Tag (opzionale)", placeholder: "es. vacanze, lavoro",
                        text: $tags, icon: "number")

            DSCard(.card, padding: DS.Space.cardPad) {
                VStack(spacing: 0) {
                    DSSwitchRow(icon: "repeat", label: "Transazione ricorrente", isOn: $isRecurring)

                    if isRecurring {
                        DSSegmentedTabs(
                            options: [(Transaction.RecurringFrequency.weekly, "Settimanale"),
                                      (Transaction.RecurringFrequency.monthly, "Mensile"),
                                      (Transaction.RecurringFrequency.yearly, "Annuale")],
                            selection: $recurringFrequency
                        )
                        .padding(.top, DS.Space.x2)
                        .padding(.bottom, DS.Space.x2)
                    }

                    DSSwitchRow(icon: "eye.slash", label: "Ignora nelle statistiche",
                                isOn: $isIgnored)
                }
            }
        }
    }

    // MARK: - Save bar
    //
    // Screen CTAs are pinned to the bottom over a white protection fade.

    private var saveBar: some View {
        DSButton(isEditing ? "Salva Modifiche" : "Aggiungi Movimento",
                 variant: .primary, size: .large, block: true) {
            Task { await saveTransaction() }
        }
        .disabled(isLoading)
        .dsGutter()
        .padding(.bottom, DS.Space.x5)
        .padding(.top, DS.Space.x8)
        .background(DS.Gradients.fadeWhite)
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

#Preview("Nuova transazione") {
    AddTransactionView(viewModel: .preview)
}
