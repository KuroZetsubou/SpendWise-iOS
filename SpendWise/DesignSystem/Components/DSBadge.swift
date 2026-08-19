import SwiftUI

// MARK: - Badge, Chip, InfoPill
//
// Every badge, chip and segmented control in the kit is a full pill. Money semantics
// (green in / red out) are reserved for amounts and their deltas — never decorative.

public enum DSBadgeTone {
    case success, danger, info, neutral, warning, onDark

    var background: Color {
        switch self {
        case .success: return DS.Palette.green50
        case .danger:  return DS.Palette.red50
        case .info:    return DS.Colors.surfaceTint
        case .neutral: return DS.Colors.surfaceSunken
        case .warning: return DS.Palette.amber500.opacity(0.14)
        case .onDark:  return DS.Colors.scrimOnDark
        }
    }

    var foreground: Color {
        switch self {
        case .success: return DS.Palette.green600
        case .danger:  return DS.Colors.expense
        case .info:    return DS.Colors.actionPrimary
        case .neutral: return DS.Colors.textSecondary
        case .warning: return DS.Palette.amber500
        case .onDark:  return DS.Colors.textOnDark
        }
    }
}

public struct DSBadge: View {
    private let text: String
    private let icon: String?
    private let tone: DSBadgeTone

    public init(_ text: String, icon: String? = nil, tone: DSBadgeTone = .neutral) {
        self.text = text
        self.icon = icon
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
            }
            Text(text).dsText(DS.Font.Style(size: 12, weight: .semibold, lineHeight: 16),
                              color: tone.foreground)
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tone.background)
        .clipShape(Capsule())
    }
}

/// Horizontal-scroll filter chip. Selected = brand blue fill, white label.
public struct DSChip: View {
    private let title: String
    private let icon: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, icon: String? = nil, isSelected: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(title).dsText(DS.Font.labelBold,
                                   color: isSelected ? DS.Colors.textOnDark : DS.Colors.textSecondary)
            }
            .foregroundStyle(isSelected ? DS.Colors.textOnDark : DS.Colors.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(isSelected ? DS.Colors.actionPrimary : DS.Colors.surfaceSunken)
            .clipShape(Capsule())
        }
        .buttonStyle(DSPressStyle())
        .animation(DS.Motion.standard, value: isSelected)
    }
}

/// Icon in a tinted circle — the kit's row/tile icon treatment.
/// Setting rows use a 40pt pale-blue circle; transaction rows a white 42pt disc.
public struct DSIconTile: View {
    private let icon: String
    private let size: CGFloat
    private let background: Color
    private let foreground: Color

    public init(_ icon: String,
                size: CGFloat = 40,
                background: Color = DS.Colors.surfaceTint,
                foreground: Color = DS.Colors.actionPrimary) {
        self.icon = icon
        self.size = size
        self.background = background
        self.foreground = foreground
    }

    public var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
    }
}

/// Meta line — two facts joined by a dot separator: "Today • 02.35 pm".
public struct DSMetaLine: View {
    private let parts: [String]
    private let color: Color

    public init(_ parts: [String], color: Color = DS.Colors.textMuted) {
        self.parts = parts.filter { !$0.isEmpty }
        self.color = color
    }

    public var body: some View {
        Text(parts.joined(separator: " • "))
            .dsText(DS.Font.meta, color: color)
            .lineLimit(1)
    }
}
