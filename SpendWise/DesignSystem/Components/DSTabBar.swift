import SwiftUI

// MARK: - Tab bar
//
// White sheet with a soft upward shadow, four labelled tabs and a raised blue circular
// action in the middle. Active tab = blue filled icon + blue label. Icons are bare (22pt,
// muted); labels are 11pt/600.

public struct DSTabBarItem: Identifiable, Equatable {
    public let id: Int
    public let title: String
    public let icon: String
    public let activeIcon: String

    public init(id: Int, title: String, icon: String, activeIcon: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.activeIcon = activeIcon ?? icon
    }
}

public struct DSTabBar: View {
    private let items: [DSTabBarItem]
    @Binding private var selection: Int
    private let centerIcon: String
    private let onCenterTap: () -> Void

    public init(items: [DSTabBarItem],
                selection: Binding<Int>,
                centerIcon: String = "plus",
                onCenterTap: @escaping () -> Void) {
        self.items = items
        self._selection = selection
        self.centerIcon = centerIcon
        self.onCenterTap = onCenterTap
    }

    private var half: Int { (items.count + 1) / 2 }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items.prefix(half)) { tab(for: $0) }

            Button(action: onCenterTap) {
                Image(systemName: centerIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.Colors.textOnDark)
                    .frame(width: 54, height: 54)
                    .background(DS.Colors.actionPrimary)
                    .clipShape(Circle())
                    .dsShadow(.fab)
            }
            .buttonStyle(DSPressStyle())
            .offset(y: -16)
            .padding(.horizontal, DS.Space.x2)

            ForEach(items.suffix(from: min(half, items.count))) { tab(for: $0) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, DS.Space.x2)
        .background(
            DS.Colors.surfaceCard
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DS.Radius.sheet,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: DS.Radius.sheet,
                        style: .continuous
                    )
                )
                .dsShadow(.tabBar)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tab(for item: DSTabBarItem) -> some View {
        let isActive = selection == item.id
        return Button {
            withAnimation(DS.Motion.standard) { selection = item.id }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isActive ? item.activeIcon : item.icon)
                    .font(.system(size: 21, weight: .medium))
                Text(item.title)
                    .dsText(DS.Font.caption,
                            color: isActive ? DS.Colors.actionPrimary : DS.Colors.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? DS.Colors.actionPrimary : DS.Colors.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
    }
}
