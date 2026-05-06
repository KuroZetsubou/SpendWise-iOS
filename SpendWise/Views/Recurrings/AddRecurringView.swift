import SwiftUI

struct AddRecurringView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var existing: RecurringPayment? = nil
    var prefill: Prefill? = nil

    struct Prefill {
        var name: String
        var amount: Double
        var category: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amountString = ""
    @State private var selectedType: Transaction.TransactionType = .expense
    @State private var selectedCategory = ""
    @State private var selectedTiming: RecurringTiming = .monthly
    @State private var recurringDay: Int = 1
    @State private var notes = ""
    @State private var isActive = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existing != nil }

    private var availableCategories: [AppCategory] {
        viewModel.categories.filter { $0.type == (selectedType == .income ? .income : .expense) && $0.parentId == nil }
    }

    // For monthly+: day 1–31. For weekly/biweekly: 0–6 (Mon–Sun)
    private var dayOptions: [(label: String, value: Int)] {
        switch selectedTiming {
        case .weekly, .biweekly:
            return [("Lunedì",0),("Martedì",1),("Mercoledì",2),("Giovedì",3),("Venerdì",4),("Sabato",5),("Domenica",6)]
        default:
            return (1...31).map { ("\($0)", $0) }
        }
    }

    private var dayLabel: String { selectedTiming == .weekly || selectedTiming == .biweekly ? "Giorno della settimana" : "Giorno del mese" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli") {
                    TextField("Nome (es. Netflix, Affitto…)", text: $name)

                    Picker("Tipo", selection: $selectedType) {
                        Text("Uscita").tag(Transaction.TransactionType.expense)
                        Text("Entrata").tag(Transaction.TransactionType.income)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("€")
                        TextField("Importo", text: $amountString)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Section("Categoria") {
                    Picker("Categoria", selection: $selectedCategory) {
                        ForEach(availableCategories) { cat in
                            HStack {
                                CategoryIconView(categoryName: cat.name, size: 20, showBackground: false)
                                Text(cat.name)
                            }.tag(cat.name)
                        }
                    }
                }

                Section("Ricorrenza") {
                    Picker("Frequenza", selection: $selectedTiming) {
                        ForEach(RecurringTiming.allCases) { t in
                            Label(t.label, systemImage: t.systemImage).tag(t)
                        }
                    }

                    Picker(dayLabel, selection: $recurringDay) {
                        ForEach(dayOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                }

                Section("Opzioni") {
                    Toggle("Attivo", isOn: $isActive)
                    TextField("Note (opzionale)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(isEditing ? "Modifica Abbonamento" : "Nuovo Abbonamento")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Salva" : "Aggiungi") {
                        Task { await save() }
                    }
                    .disabled(isLoading || name.isEmpty || amountString.isEmpty)
                    .bold()
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        if let e = existing {
            name = e.name
            amountString = String(format: "%.2f", e.amount).replacingOccurrences(of: ".", with: ",")
            selectedType = e.type
            selectedCategory = e.category
            selectedTiming = e.recurringTiming
            recurringDay = e.recurringDate
            notes = e.notes ?? ""
            isActive = e.isActive
        } else if let p = prefill {
            name = p.name
            amountString = String(format: "%.2f", p.amount).replacingOccurrences(of: ".", with: ",")
            selectedCategory = p.category
            selectedCategory = availableCategories.first(where: { $0.name == p.category })?.name ?? (availableCategories.first?.name ?? "")
        } else {
            selectedCategory = availableCategories.first?.name ?? ""
        }
    }

    private func save() async {
        let clean = amountString.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(clean), amount > 0 else { errorMessage = "Importo non valido."; return }
        guard !name.isEmpty else { errorMessage = "Inserisci un nome."; return }
        guard let uid = viewModel.userId else { errorMessage = "Non autenticato."; return }

        isLoading = true
        defer { isLoading = false }

        let r = RecurringPayment(
            id: existing?.id,
            userId: uid,
            name: name,
            amount: amount,
            type: selectedType,
            category: selectedCategory.isEmpty ? (availableCategories.first?.name ?? "Altro") : selectedCategory,
            recurringDate: recurringDay,
            recurringTiming: selectedTiming,
            transactionIds: existing?.transactionIds ?? [],
            notes: notes.isEmpty ? nil : notes,
            isActive: isActive
        )

        if let id = existing?.id {
            await viewModel.updateRecurring(id: id, updates: [
                "name": name, "amount": amount, "type": selectedType.rawValue,
                "category": r.category, "recurringDate": recurringDay,
                "recurringTiming": selectedTiming.rawValue,
                "notes": notes, "isActive": isActive
            ])
        } else {
            await viewModel.addRecurring(r)
        }
        dismiss()
    }
}

#Preview("Nuovo ricorrente") {
    AddRecurringView(viewModel: .preview)
}

#Preview("Modifica ricorrente") {
    AddRecurringView(viewModel: .preview, existing: MockData.recurrings[0])
}
