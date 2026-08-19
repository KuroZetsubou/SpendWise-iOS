import SwiftUI

// MARK: - App bar
//
// Two grounds:
//  - navy / gradient: white title centred, translucent circular back and overflow buttons.
//    Navy panels bleed to the edges and full width.
//  - light: ink title left-aligned on the app background, white circular action on the right.

public struct DSAppBar<Accessory: View>: View {
    public enum Tone { case navy, gradient, light }

    private let title: String
    private let subtitle: String?
    private let tone: Tone
    private let onBack: (() -> Void)?
    private let trailingIcon: String?
    private let onTrailing: (() -> Void)?
    private let accessory: Accessory

    public init(_ title: String,
                subtitle: String? = nil,
                tone: Tone = .light,
                onBack: (() -> Void)? = nil,
                trailingIcon: String? = nil,
                onTrailing: (() -> Void)? = nil,
                @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.onBack = onBack
        self.trailingIcon = trailingIcon
        self.onTrailing = onTrailing
        self.accessory = accessory()
    }

    private var isDark: Bool { tone != .light }
    private var centred: Bool { isDark }

    private var titleColor: Color { isDark ? DS.Colors.textOnDark : DS.Colors.textHeading }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x5) {
            HStack(spacing: DS.Space.x3) {
                if let onBack {
                    DSIconButton("chevron.left", tone: isDark ? .onDark : .light,
                                 size: 44, action: onBack)
                } else if centred && trailingIcon != nil {
                    Color.clear.frame(width: 44, height: 44)
                }

                VStack(alignment: centred ? .center : .leading, spacing: 2) {
                    Text(title)
                        .dsText(centred ? DS.Font.h3 : DS.Font.h2, color: titleColor)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .dsText(DS.Font.meta,
                                    color: isDark ? DS.Colors.textOnDarkMuted : DS.Colors.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)

                if let trailingIcon, let onTrailing {
                    DSIconButton(trailingIcon, tone: isDark ? .onDark : .light,
                                 size: 44, action: onTrailing)
                } else if centred && onBack != nil {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .frame(minHeight: DS.Space.appBarHeight)

            accessory
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.x2)
        .padding(.bottom, DS.Space.x5)
        .frame(maxWidth: .infinity)
        .background(headerBackground)
    }

    @ViewBuilder
    private var headerBackground: some View {
        switch tone {
        case .navy:     DS.Colors.surfaceInverse
        case .gradient: DS.Gradients.hero
        case .light:    DS.Colors.bgApp
        }
    }
}

// MARK: - Balance header
//
// The navy hero figure: caption above, big amount below, small eye toggle beside it.
// Sits in the app bar's accessory slot.

public struct DSBalanceHeader: View {
    private let label: String
    private let amount: String
    private let caption: String?
    @Binding private var isHidden: Bool
    private let onDark: Bool

    public init(label: String, amount: String, caption: String? = nil,
                isHidden: Binding<Bool>? = nil, onDark: Bool = true) {
        self.label = label
        self.amount = amount
        self.caption = caption
        self._isHidden = isHidden ?? .constant(false)
        self.onDark = onDark
        self.hasToggle = isHidden != nil
    }

    private let hasToggle: Bool

    private var labelColor: Color { onDark ? DS.Colors.textOnDarkMuted : DS.Colors.textMuted }
    private var amountColor: Color { onDark ? DS.Colors.textOnDark : DS.Colors.textHeading }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x1) {
            Text(label).dsText(DS.Font.label, color: labelColor)

            HStack(spacing: DS.Space.x3) {
                Text(isHidden ? "€ ••••••" : amount)
                    .dsText(DS.Font.amountHero, color: amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if hasToggle {
                    Button {
                        withAnimation(DS.Motion.standard) { isHidden.toggle() }
                    } label: {
                        Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(amountColor)
                            .frame(width: 24, height: 24)
                            .background(onDark ? DS.Colors.scrimOnDark : DS.Colors.surfaceSunken)
                            .clipShape(Circle())
                    }
                    .buttonStyle(DSPressStyle())
                }
                Spacer(minLength: 0)
            }

            if let caption {
                Text(caption).dsText(DS.Font.meta, color: labelColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
