import SwiftUI

// MARK: - Stat card
//
// White analytics card: title row with an optional overflow action, a small caption, a large
// figure with a delta badge beside it, then any chart or child content.

public struct DSStatCard<Content: View>: View {
    private let title: String
    private let caption: String?
    private let value: String?
    private let delta: String?
    private let deltaTone: DSBadgeTone
    private let onMore: (() -> Void)?
    private let content: Content

    public init(title: String,
                caption: String? = nil,
                value: String? = nil,
                delta: String? = nil,
                deltaTone: DSBadgeTone = .success,
                onMore: (() -> Void)? = nil,
                @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.title = title
        self.caption = caption
        self.value = value
        self.delta = delta
        self.deltaTone = deltaTone
        self.onMore = onMore
        self.content = content()
    }

    public var body: some View {
        DSCard(.card) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: DS.Space.x3) {
                    Text(title)
                        .dsText(DS.Font.Style(size: 17, weight: .bold, lineHeight: 24),
                                color: DS.Colors.textHeading)
                    Spacer(minLength: 0)
                    if let onMore {
                        DSIconButton("ellipsis", tone: .sunken, size: 28, iconSize: 14, action: onMore)
                    }
                }

                if let caption {
                    Text(caption)
                        .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                        .padding(.top, DS.Space.x2 + 2)
                }

                if let value {
                    HStack(spacing: DS.Space.x2 + 2) {
                        Text(value)
                            .dsText(DS.Font.amountLarge, color: DS.Colors.textHeading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if let delta { DSBadge(delta, tone: deltaTone) }
                    }
                    .padding(.top, 2)
                }

                if Content.self != EmptyView.self {
                    content.padding(.top, DS.Space.x4)
                }
            }
        }
    }
}

// MARK: - Stat tile
//
// The compact 2-up figure tile: a tinted icon circle, the figure, and a muted label.
// Gray tile, 20pt radius, no shadow, no border.

public struct DSStatTile: View {
    private let title: String
    private let value: String
    private let icon: String
    private let tint: Color
    private let subtitle: String?
    private let surface: DSSurface

    public init(title: String, value: String, icon: String,
                tint: Color = DS.Colors.actionPrimary,
                subtitle: String? = nil,
                surface: DSSurface = .sunken) {
        self.title = title
        self.value = value
        self.icon = icon
        self.tint = tint
        self.subtitle = subtitle
        self.surface = surface
    }

    public var body: some View {
        DSCard(surface, radius: DS.Radius.card, padding: DS.Space.cardPad) {
            VStack(alignment: .leading, spacing: DS.Space.x2 + 2) {
                DSIconTile(icon, size: 36, background: tint.opacity(0.12), foreground: tint)

                Text(value)
                    .dsText(DS.Font.Style(size: 20, weight: .bold, lineHeight: 26, trackingEm: -0.02),
                            color: DS.Colors.textHeading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).dsText(DS.Font.meta, color: DS.Colors.textSecondary)
                    if let subtitle {
                        Text(subtitle)
                            .dsText(DS.Font.Style(size: 11, weight: .regular, lineHeight: 14),
                                    color: DS.Colors.textMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Promo banner
//
// Pale blue promo panel: 24pt radius, flat, no shadow. Copy is one sentence and one action.

public struct DSPromoBanner: View {
    private let title: String
    private let message: String
    private let icon: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(title: String, message: String, icon: String = "sparkles",
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        DSCard(.tint) {
            HStack(alignment: .top, spacing: DS.Space.x3 + 2) {
                DSIconTile(icon, size: 44, background: DS.Colors.actionPrimary,
                           foreground: DS.Colors.textOnDark)
                VStack(alignment: .leading, spacing: DS.Space.x1) {
                    Text(title).dsText(DS.Font.h3, color: DS.Colors.textHeading)
                    Text(message)
                        .dsText(DS.Font.meta, color: DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle, let action {
                        Button(action: action) {
                            Text(actionTitle).dsText(DS.Font.labelBold, color: DS.Colors.textLink)
                        }
                        .buttonStyle(DSPressStyle())
                        .padding(.top, DS.Space.x1)
                    }
                }
            }
        }
    }
}

// MARK: - Wallet / account card
//
// The payment card: the blue gradient, a dot pattern, the balance and a masked number.

public struct DSWalletCard: View {
    private let name: String
    private let balance: String
    private let number: String?
    private let footnote: String?
    private let tone: Tone

    public enum Tone { case blue, navy }

    public init(name: String, balance: String, number: String? = nil,
                footnote: String? = nil, tone: Tone = .blue) {
        self.name = name
        self.balance = balance
        self.number = number
        self.footnote = footnote
        self.tone = tone
    }

    private var isDark: Bool { tone == .navy }
    private var primaryText: Color { isDark ? DS.Colors.textOnDark : DS.Colors.textHeading }
    private var mutedText: Color { isDark ? DS.Colors.textOnDarkMuted : DS.Colors.textSecondary }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            HStack {
                Text(name).dsText(DS.Font.label, color: mutedText).lineLimit(1)
                Spacer(minLength: DS.Space.x2)
                Image(systemName: "wave.3.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(mutedText)
            }

            Text(balance)
                .dsText(DS.Font.Style(size: 26, weight: .bold, lineHeight: 32, trackingEm: -0.02),
                        color: primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack {
                if let number {
                    Text(number).dsText(DS.Font.label, color: mutedText)
                }
                Spacer(minLength: DS.Space.x2)
                if let footnote {
                    Text(footnote).dsText(DS.Font.meta, color: mutedText)
                }
            }
        }
        .padding(DS.Space.cardPadLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if isDark { DS.Gradients.hero } else { DS.Gradients.cardBlue }
                DSDotPattern(color: isDark ? Color.white.opacity(0.10)
                                           : DS.Palette.blue500.opacity(0.10))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
    }
}

/// The decorative 12pt dot grid on payment cards, masked diagonally.
struct DSDotPattern: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 12
            var y: CGFloat = 6
            while y < size.height {
                var x: CGFloat = 6
                while x < size.width {
                    let fade = 1 - min(max((x / size.width + y / size.height) / 2, 0), 1)
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2))
                    context.fill(dot, with: .color(color.opacity(fade)))
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}
