import SwiftUI

// MARK: - Surfaces
//
// White cards: 24pt radius, no border, soft wide neutral shadow.
// Gray tiles and rows: 20pt radius, no shadow, no border.
// Pale blue promos: 24pt radius, flat. Selected rows: white, 1.5pt blue border, soft shadow.
// There is no colored left-border card motif anywhere in this system.

public enum DSSurface {
    /// White content card — the default block on a white screen.
    case card
    /// gray-50 tile — the second, cooler surface that gives depth on white.
    case sunken
    /// Pale blue promo / icon panel.
    case tint
    /// Navy panel.
    case inverse
    /// White with a 1.5pt blue border — the selected state.
    case selected
    /// White with a hairline border, no shadow.
    case outline
}

public struct DSCard<Content: View>: View {
    private let surface: DSSurface
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(_ surface: DSSurface = .card,
                radius: CGFloat? = nil,
                padding: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {
        self.surface = surface
        self.radius = radius ?? Self.defaultRadius(for: surface)
        self.padding = padding ?? Self.defaultPadding(for: surface)
        self.content = content()
    }

    private static func defaultRadius(for surface: DSSurface) -> CGFloat {
        switch surface {
        case .card, .tint, .inverse, .selected, .outline: return DS.Radius.cardLarge
        case .sunken: return DS.Radius.card
        }
    }

    private static func defaultPadding(for surface: DSSurface) -> CGFloat {
        switch surface {
        case .card, .tint, .inverse, .selected, .outline: return DS.Space.cardPadLarge
        case .sunken: return DS.Space.cardPad
        }
    }

    private var fill: Color {
        switch surface {
        case .card, .selected, .outline: return DS.Colors.surfaceCard
        case .sunken: return DS.Colors.surfaceSunken
        case .tint: return DS.Colors.surfaceTint
        case .inverse: return DS.Colors.surfaceInverse
        }
    }

    private var shadow: DS.Shadow? {
        switch surface {
        case .card, .selected: return .card
        case .sunken, .tint, .outline: return nil
        case .inverse: return .raised
        }
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                switch surface {
                case .selected:
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(DS.Colors.borderSelected, lineWidth: DS.Radius.strokeSelected)
                case .outline:
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(DS.Colors.borderHairline, lineWidth: DS.Radius.strokeHairline)
                default:
                    EmptyView()
                }
            }
            .modifier(OptionalShadow(shadow: shadow))
    }
}

private struct OptionalShadow: ViewModifier {
    let shadow: DS.Shadow?
    func body(content: Content) -> some View {
        if let shadow {
            content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            content
        }
    }
}

// MARK: - Section header
//
// "Recent Transaction" + a blue "See All" link. Title Case, 17pt/600.

public struct DSSectionHeader<Trailing: View>: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let trailing: Trailing

    public init(_ title: String,
                actionTitle: String? = nil,
                action: (() -> Void)? = nil,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).dsText(DS.Font.h3, color: DS.Colors.textHeading)
            Spacer(minLength: DS.Space.x3)
            trailing
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).dsText(DS.Font.label, color: DS.Colors.textLink)
                }
                .buttonStyle(DSPressStyle())
            }
        }
    }
}

// MARK: - Screen background
//
// Screens are white. Depth comes from gray-50 tiles sitting on white — never a gray screen
// with white cards.

public struct DSScreenBackground: View {
    private let tone: Tone
    public enum Tone { case light, navy, gradient }

    public init(_ tone: Tone = .light) { self.tone = tone }

    public var body: some View {
        Group {
            switch tone {
            case .light:    DS.Colors.bgApp
            case .navy:     DS.Colors.surfaceInverse
            case .gradient: DS.Gradients.hero
            }
        }
        .ignoresSafeArea()
    }
}

public extension View {
    /// Puts the screen on the design system's ground and hides the platform's gray grouped
    /// background, which this system never uses.
    func dsScreen(_ tone: DSScreenBackground.Tone = .light) -> some View {
        self
            .background(DSScreenBackground(tone))
            .scrollContentBackground(.hidden)
    }

    /// The 20pt left/right gutter used on every screen.
    func dsGutter() -> some View {
        self.padding(.horizontal, DS.Space.gutter)
    }
}

// MARK: - Hero scroll background
//
// The navy hero panel scrolls with the content. Without a pinned strip behind it, the
// white screen background shows through under the status bar the moment the hero moves,
// which reads as a jarring white gap. These helpers keep a fixed navy gradient behind the
// top of a scrolling screen so the strip stays blue while the content scrolls under it.

public struct DSHeroHeightKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public extension View {
    /// Records the natural height of the hero content for use with `dsHeroScrollBackground`.
    func dsReportHeroHeight() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: DSHeroHeightKey.self, value: geo.size.height)
            }
        )
    }

    /// Pins the navy hero gradient behind the top of a scrolling screen. Apply to the
    /// `ScrollView` after `.dsReportHeroHeight()` on the hero and keep `.ignoresSafeArea(.top)`.
    func dsHeroScrollBackground(height: CGFloat) -> some View {
        background(DS.Colors.bgApp)
            .background(alignment: .top) {
                DS.Gradients.hero
                    .frame(height: max(height, 0))
            }
    }
}

// MARK: - Empty state
//
// Short and factual, per the kit's empty/aside copy rule.

public struct DSEmptyState: View {
    private let icon: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(icon: String, title: String, message: String? = nil,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: DS.Space.x3) {
            ZStack {
                Circle().fill(DS.Colors.surfaceTint).frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(DS.Colors.actionPrimary)
            }
            Text(title).dsText(DS.Font.h3, color: DS.Colors.textHeading)
            if let message {
                Text(message)
                    .dsText(DS.Font.body, color: DS.Colors.textMuted)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                DSButton(actionTitle, variant: .secondary, size: .small, action: action)
                    .padding(.top, DS.Space.x1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.x10)
        .padding(.horizontal, DS.Space.gutter)
    }
}
