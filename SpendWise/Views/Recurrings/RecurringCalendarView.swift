import SwiftUI

struct RecurringCalendarView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var displayedMonth: Date = {
        Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    }()
    @State private var selectedDay: Date = Date()

    private let cal = Calendar.current

    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; f.locale = Locale(identifier: "it_IT")
        return f.string(from: displayedMonth).capitalized
    }

    private var daysInMonth: [Date] {
        guard let range = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        var days: [Date] = []
        var d = range.start
        while d < range.end {
            days.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return days
    }

    /// Active recurrings due on a given day.
    private func recurrings(on date: Date) -> [RecurringPayment] {
        let dayOfMonth = cal.component(.day, from: date)
        let weekday = (cal.component(.weekday, from: date) + 5) % 7
        return viewModel.activeRecurrings.filter { r in
            switch r.recurringTiming {
            case .monthly, .quarterly, .semiannually, .yearly:
                return r.recurringDate == dayOfMonth
            case .weekly, .biweekly:
                return r.recurringDate == weekday
            case .daily:
                return true
            }
        }
    }

    /// Actual transactions on a given day.
    private func transactions(on date: Date) -> [Transaction] {
        let prefix = { () -> String in
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
            return df.string(from: date)
        }()
        return viewModel.transactions
            .filter { $0.date.hasPrefix(prefix) && !$0.isIgnored }
            .sorted { $0.date > $1.date }
    }

    private var paidIds: Set<String> { viewModel.currentMonthPaidRecurringIds }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var selectedDayLabel: String {
        let df = DateFormatter(); df.dateFormat = "d MMMM"; df.locale = Locale(identifier: "it_IT")
        return df.string(from: selectedDay).capitalized
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Calendar ──────────────────────────────────────────
                VStack(spacing: 6) {
                    // Month navigator
                    HStack {
                        Button {
                            withAnimation { displayedMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth)! }
                        } label: {
                            Image(systemName: "chevron.left").font(.title3).padding(8)
                        }
                        Spacer()
                        Text(monthLabel).font(.headline)
                        Spacer()
                        Button {
                            withAnimation { displayedMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth)! }
                        } label: {
                            Image(systemName: "chevron.right").font(.title3).padding(8)
                        }
                    }
                    .padding(.horizontal, 8)

                    // Weekday headers
                    HStack(spacing: 0) {
                        ForEach(["L","M","M","G","V","S","D"], id: \.self) { d in
                            Text(d).font(.caption2.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)

                    // Day cells
                    let firstWeekday = (cal.component(.weekday, from: daysInMonth.first ?? Date()) + 5) % 7
                    let paddedDays: [Date?] = Array(repeating: nil, count: firstWeekday) + daysInMonth.map { Optional($0) }

                    LazyVGrid(columns: gridColumns, spacing: 4) {
                        ForEach(0..<paddedDays.count, id: \.self) { idx in
                            if let day = paddedDays[idx] {
                                DayCell(
                                    day: day,
                                    recurrings: recurrings(on: day),
                                    hasTransactions: !transactions(on: day).isEmpty,
                                    paidIds: paidIds,
                                    isToday: cal.isDateInToday(day),
                                    isSelected: cal.isDate(selectedDay, inSameDayAs: day)
                                )
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selectedDay = day } }
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
                .padding(.vertical, 4)
                .background(.background)

                Divider()

                // ── Selected day detail ───────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    // Day header
                    HStack {
                        Text(selectedDayLabel)
                            .font(.headline)
                        Spacer()
                        let txCount = transactions(on: selectedDay).count
                        if txCount > 0 {
                            Text("\(txCount) transazioni")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                    let dayRecurrings = recurrings(on: selectedDay)
                    let dayTransactions = transactions(on: selectedDay)

                    if dayRecurrings.isEmpty && dayTransactions.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Nessuna spesa per questo giorno")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        // Recurrings due today
                        if !dayRecurrings.isEmpty {
                            Text("Pagamenti ricorrenti")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)

                            ForEach(dayRecurrings) { r in
                                let lastAmt = r.lastLinkedAmount(linkedTransactions: viewModel.transactions) ?? r.amount
                                HStack(spacing: 12) {
                                    CategoryIconView(categoryName: r.category, size: 32, showBackground: true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.name).font(.subheadline.bold()).lineLimit(1)
                                        Text(r.recurringTiming.label).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text((r.type == .expense ? "-" : "+") + lastAmt.euroFormatted)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(r.type == .expense ? Color.expense : Color.income)
                                    if paidIds.contains(r.id ?? "") {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "clock").foregroundStyle(.orange)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                            }

                            if !dayTransactions.isEmpty { Divider().padding(.horizontal, 16).padding(.vertical, 6) }
                        }

                        // Actual transactions on this day
                        if !dayTransactions.isEmpty {
                            Text("Transazioni")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)

                            ForEach(dayTransactions) { tx in
                                HStack(spacing: 12) {
                                    CategoryIconView(categoryName: tx.category, size: 32, showBackground: false)
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct DayCell: View {
    let day: Date
    let recurrings: [RecurringPayment]
    let hasTransactions: Bool
    let paidIds: Set<String>
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        let dayNum = Calendar.current.component(.day, from: day)
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle().fill(Color.appPrimary).frame(width: 28, height: 28)
                } else if isSelected {
                    Circle().stroke(Color.appPrimary, lineWidth: 1.5).frame(width: 28, height: 28)
                }
                Text("\(dayNum)")
                    .font(.subheadline.bold())
                    .foregroundStyle(isToday ? .white : .primary)
            }
            HStack(spacing: 2) {
                ForEach(recurrings.prefix(2)) { r in
                    let isPaid = paidIds.contains(r.id ?? "")
                    Circle()
                        .fill(r.type == .expense ? (isPaid ? Color.green : Color.expense) : Color.income)
                        .frame(width: 4, height: 4)
                }
                if hasTransactions {
                    Circle().fill(Color.appPrimary.opacity(0.6)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(isSelected ? Color.appPrimary.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    RecurringCalendarView(viewModel: .preview)
}
