import SwiftUI

// MARK: - Button
//
// Every button in the kit is a pill. Primary = brand blue, white label. Secondary = gray-50
// fill, ink label. Ghost = transparent, blue label. Outline = dashed pale blue on white
// ("Add New Card"). Dark = navy. Press feedback is 0.97 scale + a step down the blue ramp.
// Disabled is 45% opacity, never a gray recolor. Labels are verb-first, Title Case.

public enum DSButtonVariant { case primary, secondary, ghost, outline, dark, destructive }
public enum DSButtonSize {
    case small, medium, large

    var height: CGFloat {
        switch self {
        case .small: return 36
        case .medium: return 44
        case .large: return 54
        }
    }
    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 20
        case .large: return 24
        }
    }
    var style: DS.Font.Style {
        switch self {
        case .small: return DS.Font.metaBold
        case .medium: return DS.Font.labelBold
        case .large: return DS.Font.Style(size: 15, weight: .semibold, lineHeight: 22)
        }
    }
}

public struct DSButton: View {
    private let title: String
    private let icon: String?
    private let iconRight: String?
    private let variant: DSButtonVariant
    private let size: DSButtonSize
    private let block: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String,
                icon: String? = nil,
                iconRight: String? = nil,
                variant: DSButtonVariant = .primary,
                size: DSButtonSize = .large,
                block: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.iconRight = iconRight
        self.variant = variant
        self.size = size
        self.block = block
        self.action = action
    }

    private var foreground: Color {
        switch variant {
        case .primary, .dark, .destructive: return DS.Colors.textOnDark
        case .secondary: return DS.Colors.textBody
        case .ghost, .outline: return DS.Colors.textLink
        }
    }

    private var background: Color {
        switch variant {
        case .primary: return DS.Colors.actionPrimary
        case .secondary: return DS.Colors.actionSecondaryBg
        case .ghost: return .clear
        case .outline: return DS.Colors.surfaceCard
        case .dark: return DS.Palette.navy800
        case .destructive: return DS.Colors.expense
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.x2) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                }
                Text(title).dsText(size.style, color: foreground)
                if let iconRight {
                    Image(systemName: iconRight).font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: block ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                if variant == .outline {
                    Capsule().strokeBorder(
                        DS.Palette.blue200,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(DSPressStyle())
    }
}

// MARK: - Icon button
//
// Circular. On navy grounds it is an 18% white scrim; on light grounds a white disc with the
// card shadow, or a flat gray-50 tile.

public enum DSIconButtonTone { case onDark, light, sunken, tint, primary }

public struct DSIconButton: View {
    private let icon: String
    private let tone: DSIconButtonTone
    private let size: CGFloat
    private let iconSize: CGFloat
    private let action: () -> Void

    public init(_ icon: String,
                tone: DSIconButtonTone = .light,
                size: CGFloat = 44,
                iconSize: CGFloat? = nil,
                action: @escaping () -> Void) {
        self.icon = icon
        self.tone = tone
        self.size = size
        self.iconSize = iconSize ?? size * 0.45
        self.action = action
    }

    private var background: Color {
        switch tone {
        case .onDark:  return DS.Colors.scrimOnDark
        case .light:   return DS.Colors.surfaceCard
        case .sunken:  return DS.Colors.surfaceSunken
        case .tint:    return DS.Colors.surfaceTint
        case .primary: return DS.Colors.actionPrimary
        }
    }

    private var foreground: Color {
        switch tone {
        case .onDark, .primary: return DS.Colors.textOnDark
        case .light, .sunken:   return DS.Colors.textBody
        case .tint:             return DS.Colors.actionPrimary
        }
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .modifier(OnlyLightShadow(tone: tone))
        }
        .buttonStyle(DSPressStyle())
    }
}

private struct OnlyLightShadow: ViewModifier {
    let tone: DSIconButtonTone
    func body(content: Content) -> some View {
        switch tone {
        case .light:   content.dsShadow(.card)
        case .primary: content.dsShadow(.fab)
        default:       content
        }
    }
}

// MARK: - Press feedback
//
// 120ms, 0.97 scale, no bounce.

public struct DSPressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .animation(DS.Motion.fast, value: configuration.isPressed)
    }
}
