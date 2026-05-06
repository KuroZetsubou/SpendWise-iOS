import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var dashboardViewModel = DashboardViewModel()

    var body: some View {
        Group {
            if authViewModel.isLoading {
                splashView
            } else if authViewModel.isAuthenticated {
                mainTabView
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authViewModel.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: authViewModel.isLoading)
    }

    // MARK: - Splash
    private var splashView: some View {
        ZStack {
            Color(hex: "#0F2040").ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)
                Text("SpendWise")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Main Tab View
    private var mainTabView: some View {
        TabView(selection: $dashboardViewModel.selectedTab) {
            DashboardView(viewModel: dashboardViewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }
                .tag(DashboardViewModel.Tab.dashboard)

            TransactionsView(viewModel: dashboardViewModel)
                .tabItem {
                    Label("Transazioni", systemImage: "list.bullet")
                }
                .tag(DashboardViewModel.Tab.transactions)

            InsightsView(viewModel: dashboardViewModel)
                .tabItem {
                    Label("Insights", systemImage: "chart.pie.fill")
                }
                .tag(DashboardViewModel.Tab.insights)

            BankConnectView(viewModel: dashboardViewModel)
                .tabItem {
                    Label("Banca", systemImage: "building.columns.fill")
                }
                .tag(DashboardViewModel.Tab.bank)

            SettingsView(viewModel: dashboardViewModel)
                .tabItem {
                    Label("Impostazioni", systemImage: "gearshape.fill")
                }
                .tag(DashboardViewModel.Tab.settings)
        }
        .environmentObject(authViewModel)
        .overlay(alignment: .bottom) {
            if let toast = dashboardViewModel.toastMessage {
                ToastView(message: toast)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation(.spring(response: 0.4)) {
                                if dashboardViewModel.toastMessage?.id == toast.id {
                                    dashboardViewModel.toastMessage = nil
                                }
                            }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4), value: dashboardViewModel.toastMessage?.id)
    }
}

// MARK: - Toast View

private struct ToastView: View {
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
        case .success: return .green
        case .error:   return .red
        case .info:    return .appPrimary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(message.text)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
