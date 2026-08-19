import SwiftUI

// MARK: - FinanceMode Design System — Typography
//
// One family, five weights. Amounts are the loudest thing on screen (34pt/700, currency
// symbol spaced away from the figure). Headline tracking is tight (-0.02em); nothing is
// letter-spaced open. No italics, no serif, no mono, no display face.
//
// FONT SUBSTITUTION: the source kit shipped no font binaries — its CSS already substituted
// Plus Jakarta Sans as "the closest match to a neutral geometric grotesk". On iOS the native
// equivalent is SF Pro, so the scale below is built on the system face. To swap in a real
// font later, bundle the .otf/.ttf files and set `DS.Font.family` — nothing else changes.

public extension DS {
    enum Font {
        /// Set to a bundled PostScript family name (e.g. "PlusJakartaSans") to override the
        /// system face across the whole design system.
        public static var family: String? = nil

        public struct Style {
            public let size: CGFloat
            public let weight: SwiftUI.Font.Weight
            public let lineHeight: CGFloat
            /// em value from the CSS tokens; converted to points against `size`.
            public let trackingEm: CGFloat

            public init(size: CGFloat, weight: SwiftUI.Font.Weight,
                        lineHeight: CGFloat, trackingEm: CGFloat = 0) {
                self.size = size
                self.weight = weight
                self.lineHeight = lineHeight
                self.trackingEm = trackingEm
            }

            public var tracking: CGFloat { size * trackingEm }

            /// SwiftUI's lineSpacing is the gap *added* between lines, not the line box.
            public var lineSpacing: CGFloat { max(0, lineHeight - size * 1.21) }

            public var font: SwiftUI.Font {
                if let family = DS.Font.family {
                    return .custom(family, size: size).weight(weight)
                }
                return .system(size: size, weight: weight)
            }
        }

        // Amounts — "$ 243.320.00"
        public static let amountHero = Style(size: 34, weight: .bold, lineHeight: 42, trackingEm: -0.02)
        // Analytics figures — "$1,520,228"
        public static let amountLarge = Style(size: 28, weight: .bold, lineHeight: 36, trackingEm: -0.02)
        // Onboarding headlines
        public static let h1 = Style(size: 24, weight: .bold, lineHeight: 32, trackingEm: -0.02)
        // Screen title on light headers, card total
        public static let h2 = Style(size: 20, weight: .bold, lineHeight: 28, trackingEm: -0.02)
        // Screen title on navy headers (centred), section header, row title
        public static let h3 = Style(size: 17, weight: .semibold, lineHeight: 24)
        public static let body = Style(size: 15, weight: .regular, lineHeight: 22)
        public static let bodyMedium = Style(size: 15, weight: .medium, lineHeight: 22)
        public static let label = Style(size: 14, weight: .medium, lineHeight: 20)
        public static let labelBold = Style(size: 14, weight: .semibold, lineHeight: 20)
        // "Today • 02.35 pm"
        public static let meta = Style(size: 13, weight: .regular, lineHeight: 18)
        public static let metaBold = Style(size: 13, weight: .semibold, lineHeight: 18)
        // Tab bar labels
        public static let caption = Style(size: 11, weight: .semibold, lineHeight: 14)
    }
}

// MARK: - Applying a style

private struct DSTextStyleModifier: ViewModifier {
    let style: DS.Font.Style
    let color: Color?

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .foregroundStyle(color ?? DS.Colors.textBody)
    }
}

public extension View {
    /// Applies a design-system type style (font, weight, tracking, line spacing, color).
    func dsText(_ style: DS.Font.Style, color: Color? = nil) -> some View {
        modifier(DSTextStyleModifier(style: style, color: color))
    }
}

// MARK: - Amount formatting
//
// The kit spaces the currency symbol away from the figure ("$ 243.320.00") and always
// carries the sign on signed amounts ("+$500", "-$600"). SpendWise is a euro / it-IT app,
// so the same rule is applied to the euro symbol.

public extension Double {
    /// "€ 1.234,56" — currency symbol spaced away from the figure, per the kit's amount rule.
    var dsAmount: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let figure = f.string(from: NSNumber(value: abs(self))) ?? String(format: "%.2f", abs(self))
        return "€ \(figure)"
    }

    /// "+€ 1.234,56" / "-€ 1.234,56" — signed amounts always carry the sign.
    func dsSignedAmount(isIncome: Bool) -> String {
        (isIncome ? "+" : "-") + dsAmount
    }

    /// "€ 1.235" — no decimals, for chart axes and compact figures.
    var dsAmountCompact: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        f.maximumFractionDigits = 0
        let figure = f.string(from: NSNumber(value: abs(self))) ?? String(format: "%.0f", abs(self))
        return "€ \(figure)"
    }

    /// "+2,8%" — percentages use a comma decimal in this system.
    var dsPercent: String {
        String(format: "%.1f%%", self).replacingOccurrences(of: ".", with: ",")
    }
}
