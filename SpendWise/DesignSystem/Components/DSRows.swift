import SwiftUI

// MARK: - Transaction row
//
// gray-50 pill card, white circular merchant mark, name + "Today • 02.35 pm" meta line,
// and a bold signed amount — green for income, red for expense. Lists have no dividers;
// separation is whitespace and tile fill.

public struct DSTransactionRow<Leading: View>: View {
    private let name: String
    private let meta: [String]
    private let amount: String
    private let isIncome: Bool
    private let dimmed: Bool
    private let leading: Leading
    private let onTap: (() -> Void)?

    public init(name: String,
                meta: [String] = [],
                amount: String,
                isIncome: Bool,
                dimmed: Bool = false,
                onTap: (() -> Void)? = nil,
                @ViewBuilder leading: () -> Leading) {
        self.name = name
        self.meta = meta
        self.amount = amount
        self.isIncome = isIncome
        self.dimmed = dimmed
        self.onTap = onTap
        self.leading = leading()
    }

    public var body: some View {
        let content = HStack(spacing: DS.Space.x3) {
            leading
                .frame(width: 42, height: 42)
                .background(DS.Colors.surfaceCard)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .dsText(DS.Font.h3, color: DS.Colors.textBody)
                    .lineLimit(1)
                if !meta.isEmpty {
                    DSMetaLine(meta)
                }
            }

            Spacer(minLength: DS.Space.x2)

            Text(amount)
                .dsText(DS.Font.Style(size: 17, weight: .bold, lineHeight: 24),
                        color: isIncome ? DS.Colors.income : DS.Colors.expense)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.cardPad)
        .padding(.vertical, DS.Space.x3)
        .frame(maxWidth: .infinity)
        .background(DS.Colors.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .opacity(dimmed ? 0.45 : 1)

        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(DSPressStyle())
        } else {
            content
        }
    }
}

// MARK: - List row
//
// Settings / navigation row: pale blue circular icon tile, label, trailing chevron, value,
// badge or custom node. Rows sit directly on white — no dividers.

public struct DSListRow<Trailing: View>: View {
    private let icon: String?
    private let iconTint: Color
    private let iconBackground: Color
    private let label: String
    private let sublabel: String?
    private let value: String?
    private let showChevron: Bool
    private let trailing: Trailing
    private let action: (() -> Void)?

    public init(icon: String? = nil,
                iconTint: Color = DS.Colors.actionPrimary,
                iconBackground: Color = DS.Colors.surfaceTint,
                label: String,
                sublabel: String? = nil,
                value: String? = nil,
                showChevron: Bool = true,
                action: (() -> Void)? = nil,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.icon = icon
        self.iconTint = iconTint
        self.iconBackground = iconBackground
        self.label = label
        self.sublabel = sublabel
        self.value = value
        self.showChevron = showChevron
        self.action = action
        self.trailing = trailing()
    }

    private var hasTrailing: Bool { Trailing.self != EmptyView.self }

    public var body: some View {
        let content = HStack(spacing: DS.Space.x3 + 2) {
            if let icon {
                DSIconTile(icon, size: 40, background: iconBackground, foreground: iconTint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                    .lineLimit(1)
                if let sublabel {
                    Text(sublabel)
                        .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.x2)
            if let value {
                Text(value)
                    .dsText(DS.Font.label, color: DS.Colors.textSecondary)
                    .lineLimit(1)
            }
            trailing
            if showChevron && !hasTrailing {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.gray400)
            }
        }
        .padding(.vertical, DS.Space.x2 + 2)
        .frame(minHeight: DS.Space.touchMin)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(DSPressStyle())
        } else {
            content
        }
    }
}

// MARK: - Schedule row
//
// Upcoming payment / recurring: date block on the left, name and meta, amount on the right.

public struct DSScheduleRow: View {
    private let day: String
    private let month: String
    private let name: String
    private let meta: [String]
    private let amount: String
    private let isIncome: Bool
    private let accent: Color
    private let onTap: (() -> Void)?

    public init(day: String, month: String, name: String, meta: [String] = [],
                amount: String, isIncome: Bool = false,
                accent: Color = DS.Colors.actionPrimary, onTap: (() -> Void)? = nil) {
        self.day = day
        self.month = month
        self.name = name
        self.meta = meta
        self.amount = amount
        self.isIncome = isIncome
        self.accent = accent
        self.onTap = onTap
    }

    public var body: some View {
        let content = HStack(spacing: DS.Space.x3) {
            VStack(spacing: 0) {
                Text(day).dsText(DS.Font.Style(size: 18, weight: .bold, lineHeight: 22), color: accent)
                Text(month.uppercased())
                    .dsText(DS.Font.Style(size: 10, weight: .semibold, lineHeight: 12), color: accent)
            }
            .frame(width: 46, height: 46)
            .background(accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(name).dsText(DS.Font.h3, color: DS.Colors.textBody).lineLimit(1)
                if !meta.isEmpty { DSMetaLine(meta) }
            }

            Spacer(minLength: DS.Space.x2)

            Text(amount)
                .dsText(DS.Font.Style(size: 16, weight: .bold, lineHeight: 22),
                        color: isIncome ? DS.Colors.income : DS.Colors.expense)
        }
        .padding(.horizontal, DS.Space.cardPad)
        .padding(.vertical, DS.Space.x3)
        .frame(maxWidth: .infinity)
        .background(DS.Colors.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))

        if let onTap {
            Button(action: onTap) { content }.buttonStyle(DSPressStyle())
        } else {
            content
        }
    }
}
