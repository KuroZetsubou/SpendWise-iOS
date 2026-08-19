import SwiftUI

// MARK: - FinanceMode Design System — Tokens
//
// Ported 1:1 from the FinanceMode (Expensix) design system CSS tokens.
// Source: tokens/{colors,spacing,radii,elevation,motion}.css
//
// The kit is a light-ground system: white screens, a cooler gray-50 second surface,
// one brand blue for every action and a navy family for headers and hero panels.
// Green means money in, red means money out — those two are reserved for amounts.

public enum DS {}

// MARK: - Color

public extension DS {
    enum Palette {
        // Brand blue — #3856FC from CTAs, active nav pill, links
        public static let blue50  = Color(hex: "#EEF0FE")
        public static let blue100 = Color(hex: "#E3E7FE")
        public static let blue200 = Color(hex: "#CDD5FE")
        public static let blue300 = Color(hex: "#D4E2FE")
        public static let blue500 = Color(hex: "#3856FC")
        public static let blue600 = Color(hex: "#2A45DE")
        public static let blue700 = Color(hex: "#2038B8")

        // Navy — headers, hero panels, dark cards
        public static let navy900 = Color(hex: "#0C2250")
        public static let navy800 = Color(hex: "#0F2D6D")
        public static let navy700 = Color(hex: "#17307A")
        public static let navy600 = Color(hex: "#1A3A7F")

        // Neutrals
        public static let white   = Color(hex: "#FFFFFF")
        public static let gray25  = Color(hex: "#F8F9FB")
        public static let gray50  = Color(hex: "#F2F4F6")
        public static let gray100 = Color(hex: "#EAECEF")
        public static let gray200 = Color(hex: "#E1E4E8")
        public static let gray300 = Color(hex: "#CBD1D8")
        public static let gray400 = Color(hex: "#A6AEB8")
        public static let gray500 = Color(hex: "#7A828C")
        public static let gray600 = Color(hex: "#5B636D")
        public static let ink900  = Color(hex: "#1F1F1F")
        public static let ink800  = Color(hex: "#2B2B2E")

        // Semantic accents
        public static let green500 = Color(hex: "#2FC81E")
        public static let green600 = Color(hex: "#25A517")
        public static let green100 = Color(hex: "#CFF3C9")
        public static let green50  = Color(hex: "#E9F9E6")
        public static let red500   = Color(hex: "#C10D14")
        public static let red600   = Color(hex: "#A5090F")
        public static let red50    = Color(hex: "#FDECEC")
        public static let amber500  = Color(hex: "#F5A524")
        public static let purple500 = Color(hex: "#8B5CF6")
        public static let orange500 = Color(hex: "#F97316")
        public static let teal500   = Color(hex: "#14B8A6")
    }

    /// Semantic aliases — always prefer these over raw palette values in screens.
    enum Colors {
        public static let bgApp          = Palette.white
        public static let bgSubtle       = Palette.gray50
        public static let surfaceCard    = Palette.white
        public static let surfaceSunken  = Palette.gray50
        public static let surfaceTint    = Palette.blue50
        public static let surfaceInverse = Palette.navy800
        public static let surfaceTrack   = Palette.gray100

        public static let textBody      = Palette.ink900
        public static let textHeading   = Palette.ink900
        public static let textMuted     = Palette.gray400
        public static let textSecondary = Palette.gray500
        public static let textOnDark    = Palette.white
        public static let textOnDarkMuted = Color.white.opacity(0.72)
        public static let textLink      = Palette.blue500
        public static let income        = Palette.green500
        public static let expense       = Palette.red500

        public static let borderHairline = Palette.gray200
        public static let borderField    = Palette.gray100
        public static let borderSelected = Palette.blue500

        public static let actionPrimary      = Palette.blue500
        public static let actionPrimaryHover = Palette.blue600
        public static let actionPrimaryPress = Palette.blue700
        public static let actionSecondaryBg  = Palette.gray50

        public static let focusRing   = Color(hex: "#3856FC").opacity(0.32)
        public static let scrimOnDark = Color.white.opacity(0.18)

        /// Category colors — used only inside budget donuts and bars.
        public static let catEssentials = Palette.blue500
        public static let catLifestyle  = Palette.purple500
        public static let catSavings    = Palette.green500
        public static let catTransport  = Palette.orange500
        public static let catOther      = Palette.teal500

        /// The rotation used to color an arbitrary set of categories in charts.
        public static let categoryRamp: [Color] = [
            catEssentials, catLifestyle, catSavings, catTransport, catOther,
            Palette.amber500, Palette.navy600, Palette.blue300
        ]

        /// Stable color for a category name, so the same category keeps its hue everywhere.
        public static func category(_ name: String) -> Color {
            guard !name.isEmpty else { return catOther }
            let hash = name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
            return categoryRamp[Int(hash % UInt32(categoryRamp.count))]
        }
    }

    /// Exactly two gradients exist in the kit, plus a white protection fade.
    enum Gradients {
        /// Navy hero — behind headers and the Budget screen.
        public static let hero = LinearGradient(
            colors: [Palette.navy900, Palette.navy600],
            startPoint: .top, endPoint: .bottom
        )
        /// The payment card, 140°.
        public static let cardBlue = LinearGradient(
            colors: [Palette.blue300, Color(hex: "#E9F0FE")],
            startPoint: UnitPoint(x: 0.18, y: 0), endPoint: UnitPoint(x: 0.82, y: 1)
        )
        /// White fade under floating pills so they read over a scrolling list.
        public static let fadeWhite = LinearGradient(
            stops: [
                .init(color: Palette.white.opacity(0), location: 0),
                .init(color: Palette.white, location: 0.62)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Spacing

public extension DS {
    enum Space {
        public static let x1: CGFloat = 4
        public static let x2: CGFloat = 8
        public static let x3: CGFloat = 12
        public static let x4: CGFloat = 16
        public static let x5: CGFloat = 20
        public static let x6: CGFloat = 24
        public static let x8: CGFloat = 32
        public static let x10: CGFloat = 40
        public static let x12: CGFloat = 48
        public static let x16: CGFloat = 64

        /// Left/right padding on every screen.
        public static let gutter: CGFloat = 20
        public static let cardPad: CGFloat = 16
        public static let cardPadLarge: CGFloat = 20
        /// Gap between stacked list rows.
        public static let rowGap: CGFloat = 12
        public static let sectionGap: CGFloat = 24
        public static let tabBarHeight: CGFloat = 76
        public static let appBarHeight: CGFloat = 56
        public static let touchMin: CGFloat = 44
    }
}

// MARK: - Radii

public extension DS {
    enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 14
        public static let lg: CGFloat = 18
        public static let xl: CGFloat = 22
        public static let xl2: CGFloat = 28
        public static let xl3: CGFloat = 34
        public static let pill: CGFloat = 999

        /// Transaction rows, goal cards, list rows.
        public static let card: CGFloat = 20
        /// White content cards and sheets.
        public static let cardLarge: CGFloat = 24
        public static let field: CGFloat = 14
        /// Every button in the kit is fully rounded.
        public static let button: CGFloat = 999
        public static let sheet: CGFloat = 28

        public static let strokeHairline: CGFloat = 1
        public static let strokeSelected: CGFloat = 1.5
        /// Progress ring thickness.
        public static let strokeRing: CGFloat = 4
    }
}

// MARK: - Elevation
//
// Shadows are soft, wide, low-opacity and neutral blue-black. The only colored shadows are
// under the blue scan FAB and floating "Add New" pills.

public extension DS {
    struct Shadow {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat

        /// CSS blur radius maps to roughly half in SwiftUI's shadow radius.
        init(hex: String, opacity: Double, blur: CGFloat, y: CGFloat, x: CGFloat = 0) {
            self.color = Color(hex: hex).opacity(opacity)
            self.radius = blur / 2
            self.x = x
            self.y = y
        }

        /// 0 4px 20px rgba(20,32,64,.06)
        public static let card    = Shadow(hex: "#142040", opacity: 0.06, blur: 20, y: 4)
        /// 0 8px 28px rgba(20,32,64,.10)
        public static let raised  = Shadow(hex: "#142040", opacity: 0.10, blur: 28, y: 8)
        /// 0 8px 20px rgba(56,86,252,.32)
        public static let fab     = Shadow(hex: "#3856FC", opacity: 0.32, blur: 20, y: 8)
        /// 0 -6px 24px rgba(20,32,64,.08)
        public static let tabBar  = Shadow(hex: "#142040", opacity: 0.08, blur: 24, y: -6)
        /// 0 -10px 40px rgba(12,34,80,.16)
        public static let sheet   = Shadow(hex: "#0C2250", opacity: 0.16, blur: 40, y: -10)
    }
}

public extension View {
    func dsShadow(_ shadow: DS.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - Motion
//
// Restrained and short: 120ms press, 200ms state change, 320ms sheet/screen.
// No springs, no parallax, no looping ambient animation.

public extension DS {
    enum Motion {
        /// cubic-bezier(.4,0,.2,1) — the standard curve for everything.
        public static let standard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
        public static let fast     = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.12)
        public static let slow     = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.32)
        /// ease-out fill for progress bars and rings.
        public static let fill     = Animation.timingCurve(0, 0, 0.2, 1, duration: 0.32)
        public static let pressScale: CGFloat = 0.97
    }
}
