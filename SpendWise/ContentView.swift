import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @State private var showAddTransaction = false
    @State private var showSettings = false

    // The kit's bottom bar carries four labelled tabs around a raised centre action.
    // Settings lives behind the light app bar's trailing button on the Dashboard.
    private let tabs: [DSTabBarItem] = [
        DSTabBarItem(id: DashboardViewModel.Tab.dashboard.rawValue,
                     title: "Home", icon: "house", activeIcon: "house.fill"),
        DSTabBarItem(id: DashboardViewModel.Tab.transactions.rawValue,
                     title: "Movimenti", icon: "arrow.left.arrow.right", activeIcon: "arrow.left.arrow.right"),
        DSTabBarItem(id: DashboardViewModel.Tab.insights.rawValue,
                     title: "Report", icon: "chart.pie", activeIcon: "chart.pie.fill"),
        DSTabBarItem(id: DashboardViewModel.Tab.bank.rawValue,
                     title: "Banca", icon: "building.columns", activeIcon: "building.columns.fill")
    ]

    var body: some View {
        Group {
            if authViewModel.isLoading {
                splashView
            } else if authViewModel.isAuthenticated {
                mainShell
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(.light)   // FinanceMode is a light-ground system; dark screens use navy.
        .tint(DS.Colors.actionPrimary)
        .animation(DS.Motion.slow, value: authViewModel.isAuthenticated)
        .animation(DS.Motion.slow, value: authViewModel.isLoading)
#if os(iOS)
        .modifier(URLHandlerModifier())
#endif
    }

    // MARK: - Splash
    private var splashView: some View {
        ZStack {
            DS.Gradients.hero.ignoresSafeArea()
            VStack(spacing: DS.Space.x5) {
                ZStack {
                    Circle()
                        .fill(DS.Colors.scrimOnDark)
                        .frame(width: 96, height: 96)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(DS.Colors.textOnDark)
                }
                Text("SpendWise")
                    .dsText(DS.Font.h1, color: DS.Colors.textOnDark)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(DS.Colors.textOnDark)
                    .padding(.top, DS.Space.x2)
            }
        }
    }

    // MARK: - Main shell

    private var mainShell: some View {
        ZStack {
            DS.Colors.bgApp.ignoresSafeArea()

            Group {
                switch dashboardViewModel.selectedTab {
                case .dashboard:
                    DashboardView(viewModel: dashboardViewModel,
                                  onOpenSettings: { showSettings = true })
                case .transactions:
                    TransactionsView(viewModel: dashboardViewModel)
                case .insights:
                    InsightsView(viewModel: dashboardViewModel)
                case .bank:
                    BankConnectView(viewModel: dashboardViewModel)
                case .settings:
                    SettingsView(viewModel: dashboardViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DSTabBar(
                    items: tabs,
                    selection: Binding(
                        get: { dashboardViewModel.selectedTab.rawValue },
                        set: { raw in
                            if let tab = DashboardViewModel.Tab(rawValue: raw) {
                                dashboardViewModel.selectedTab = tab
                            }
                        }
                    ),
                    centerIcon: "plus",
                    onCenterTap: { showAddTransaction = true }
                )
            }
        }
        .environmentObject(authViewModel)
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView(viewModel: dashboardViewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: dashboardViewModel)
                .environmentObject(authViewModel)
        }
        .overlay(alignment: .bottom) {
            if let toast = dashboardViewModel.toastMessage {
                DSToastView(message: toast)
                    .padding(.bottom, DS.Space.tabBarHeight + DS.Space.x5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(DS.Motion.slow) {
                                if dashboardViewModel.toastMessage?.id == toast.id {
                                    dashboardViewModel.toastMessage = nil
                                }
                            }
                        }
                    }
            }
        }
        .animation(DS.Motion.slow, value: dashboardViewModel.toastMessage?.id)
    }
}

// MARK: - Toast
//
// A white pill on the card shadow — the kit has no dark or material toasts.

private struct DSToastView: View {
    let message: DashboardViewModel.ToastMessage

    private var icon: String {
        switch message.kind {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    private var color: Color {
        switch message.kind {
        case .success: return DS.Colors.income
        case .error:   return DS.Colors.expense
        case .info:    return DS.Colors.actionPrimary
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.x2) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(message.text)
                .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                .lineLimit(2)
        }
        .padding(.horizontal, DS.Space.x5)
        .padding(.vertical, DS.Space.x3)
        .background(DS.Colors.surfaceCard)
        .clipShape(Capsule())
        .dsShadow(.raised)
        .dsGutter()
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
