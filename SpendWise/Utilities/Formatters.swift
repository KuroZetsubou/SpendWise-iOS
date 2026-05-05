import Foundation
import SwiftUI

// MARK: - Currency Formatter
extension NumberFormatter {
    static let euroCurrency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "it_IT")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func currency(code: String = "EUR") -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.locale = Locale(identifier: "it_IT")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }
}

extension Double {
    var euroFormatted: String {
        NumberFormatter.euroCurrency.string(from: NSNumber(value: self)) ?? "\(self) €"
    }

    func currencyFormatted(code: String = "EUR") -> String {
        NumberFormatter.currency(code: code).string(from: NSNumber(value: self)) ?? "\(self)"
    }

    var percentFormatted: String {
        String(format: "%.1f%%", self)
    }
}

// MARK: - Date Formatters
extension DateFormatter {
    static let italianDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    static let italianDateShort: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    static let italianMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "it_IT")
        return f
    }()

    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension String {
    var asDate: Date? {
        let formats = ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "dd/MM/yyyy"]
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            if let date = f.date(from: self) { return date }
        }
        return ISO8601DateFormatter().date(from: self)
    }

    var italianFormatted: String {
        asDate.map { DateFormatter.italianDate.string(from: $0) } ?? self
    }
}

extension Date {
    var isoDateString: String {
        DateFormatter.isoDate.string(from: self)
    }

    var italianFormatted: String {
        DateFormatter.italianDate.string(from: self)
    }

    var monthYearFormatted: String {
        DateFormatter.italianMonthYear.string(from: self).capitalized
    }

    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }

    var endOfMonth: Date {
        Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? self
    }
}

// MARK: - Color Helpers
extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    static let income = Color(hex: Constants.Colors.income)
    static let expense = Color(hex: Constants.Colors.expense)
    static let appPrimary = Color(hex: Constants.Colors.primary)
    static let appSecondary = Color(hex: Constants.Colors.secondary)
}

// MARK: - View Modifiers
extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}
