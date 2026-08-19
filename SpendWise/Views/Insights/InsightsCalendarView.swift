import SwiftUI

/// Compact calendar fixed to a given month, embedded inside InsightsView.
struct InsightsCalendarView: View {
    @ObservedObject var viewModel: DashboardViewModel
    /// The month to display — controlled by the parent (InsightsView's selectedDate).
    let month: Date

    @State private var selectedDay: Date? = nil

    private let cal = Calendar.current

    // MARK: - Derived data

    private var daysInMonth: [Date] {
        guard let range = cal.dateInterval(of: .month, for: month) else { return [] }
        var days: [Date] = []
        var d = range.start
        while d < range.end {
            days.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return days
    }

    private var paidIds: Set<String> { viewModel.currentMonthPaidRecurringIds }

    private func recurrings(on date: Date) -> [RecurringPayment] {
        let dayOfMonth = cal.component(.day, from: date)
        let weekday   = (cal.component(.weekday, from: date) + 5) % 7
        return viewModel.activeRecurrings.filter { r in
            switch r.recurringTiming {
            case .monthly, .quarterly, .semiannually, .yearly: return r.recurringDate == dayOfMonth
            case .weekly, .biweekly:                           return r.recurringDate == weekday
            case .daily:                                       return true
            }
        }
    }

    private func transactions(on date: Date) -> [Transaction] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let prefix = df.string(from: date)
        return viewModel.transactions
            .filter { $0.date.hasPrefix(prefix) && !$0.isIgnored }
            .sorted { $0.date > $1.date }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendario del mese")
                .font(.headline)
                .padding(.horizontal)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(["L","M","M","G","V","S","D"], id: \.self) { d in
                    Text(d).font(.caption2.bold()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            // Day grid
            let firstWeekday = (cal.component(.weekday, from: daysInMonth.first ?? Date()) + 5) % 7
            let paddedDays: [Date?] = Array(repeating: nil, count: firstWeekday) + daysInMonth.map { Optional($0) }

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(0..<paddedDays.count, id: \.self) { idx in
                    if let day = paddedDays[idx] {
                        CalendarDayCell(
                            day: day,
                            recurrings: recurrings(on: day),
                            hasTransactions: !transactions(on: day).isEmpty,
                            paidIds: paidIds,
                            isToday: cal.isDateInToday(day),
                            isSelected: selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if let sel = selectedDay, cal.isDate(sel, inSameDayAs: day) {
                                    selectedDay = nil
                                } else {
                                    selectedDay = day
                                }
                            }
                        }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 8)

            // Selected day detail
            if let day = selectedDay {
                Divider().padding(.horizontal)
                dayDetailSection(for: day)
            }
        }
        .cardStyle()
        .padding(.horizontal)
        .onChange(of: month) { _, _ in
            withAnimation { selectedDay = nil }
        }
    }

    // MARK: - Day detail

    @ViewBuilder
    private func dayDetailSection(for day: Date) -> some View {
        let dayTxs = transactions(on: day)
        let dayRec = recurrings(on: day)
        let df = DateFormatter()
        let _ = { df.dateFormat = "d MMMM"; df.locale = Locale(identifier: "it_IT") }()
        let label = df.string(from: day).capitalized

        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline.bold())
                .padding(.horizontal)

            if dayRec.isEmpty && dayTxs.isEmpty {
                Text("Nessuna attività")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }

            if !dayRec.isEmpty {
                Text("Ricorrenti")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                ForEach(dayRec) { r in
                    let lastAmt = r.lastLinkedAmount(linkedTransactions: viewModel.transactions) ?? r.amount
                    HStack(spacing: 10) {
                        CategoryIconView(categoryName: r.category, size: 28, showBackground: true)
                        Text(r.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text((r.type == .expense ? "-" : "+") + lastAmt.euroFormatted)
                            .font(.subheadline.bold())
                            .foregroundStyle(r.type == .expense ? Color.expense : Color.income)
                        Image(systemName: paidIds.contains(r.id ?? "") ? "checkmark.circle.fill" : "clock.fill")
                            .foregroundStyle(paidIds.contains(r.id ?? "") ? .green : .orange)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }
            }

            if !dayTxs.isEmpty {
                if !dayRec.isEmpty { Divider().padding(.horizontal) }
                Text("Transazioni")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                ForEach(dayTxs) { tx in
                    HStack(spacing: 10) {
                        CategoryIconView(categoryName: tx.category, size: 28, showBackground: false)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tx.description.isEmpty ? tx.category : tx.description)
                                .font(.subheadline).lineLimit(1)
                            Text(tx.category).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((tx.type == .expense ? "-" : "+") + tx.amount.euroFormatted)
                            .font(.subheadline.bold())
                            .foregroundStyle(tx.type == .expense ? Color.expense : Color.income)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    InsightsCalendarView(viewModel: .preview, month: Date())
}
