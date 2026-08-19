import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        ZStack {
            DS.Gradients.hero.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: DS.Space.x12)

                // Brand lockup — one benefit, then one action, per the kit's voice.
                VStack(spacing: DS.Space.x4) {
                    ZStack {
                        Circle()
                            .fill(DS.Colors.scrimOnDark)
                            .frame(width: 96, height: 96)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(DS.Colors.textOnDark)
                    }

                    Text("SpendWise")
                        .dsText(DS.Font.Style(size: 32, weight: .bold, lineHeight: 40,
                                              trackingEm: -0.02),
                                color: DS.Colors.textOnDark)

                    Text("Tieni sotto controllo le tue finanze con tracciamento automatico, budget e decisioni più consapevoli.")
                        .dsText(DS.Font.body, color: DS.Colors.textOnDarkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Space.x6)
                }

                Spacer(minLength: DS.Space.x10)

                VStack(spacing: DS.Space.rowGap) {
                    featureRow(icon: "sparkles", text: "Analisi delle spese con AI")
                    featureRow(icon: "building.columns", text: "Connetti la tua banca")
                    featureRow(icon: "chart.pie", text: "Report e insight personalizzati")
                }
                .dsGutter()

                Spacer(minLength: DS.Space.x10)

                // Screen CTAs are pinned to the bottom above the home indicator.
                VStack(spacing: DS.Space.rowGap) {
                    if authViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(DS.Colors.textOnDark)
                            .scaleEffect(1.2)
                            .frame(height: 54)
                    } else {
                        Button {
                            Task { await authViewModel.signInWithGoogle() }
                        } label: {
                            HStack(spacing: DS.Space.x2) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Accedi con Google")
                                    .dsText(DS.Font.Style(size: 15, weight: .semibold, lineHeight: 22),
                                            color: DS.Palette.navy900)
                            }
                            .foregroundStyle(DS.Palette.navy900)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(DS.Palette.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(DSPressStyle())

                        Button {
                            Task { await authViewModel.signInAnonymously() }
                        } label: {
                            Text("Continua Senza Account")
                                .dsText(DS.Font.Style(size: 15, weight: .semibold, lineHeight: 22),
                                        color: DS.Colors.textOnDark)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(DS.Colors.scrimOnDark)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(DSPressStyle())

                        Text("Potrai collegare il tuo account Google in seguito dalle Impostazioni.")
                            .dsText(DS.Font.meta, color: DS.Colors.textOnDarkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.top, DS.Space.x1)
                    }

                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .dsText(DS.Font.meta, color: DS.Palette.red50)
                            .multilineTextAlignment(.center)
                    }
                }
                .dsGutter()
                .padding(.bottom, DS.Space.x10)
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: DS.Space.x3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Colors.textOnDark)
                .frame(width: 40, height: 40)
                .background(DS.Colors.scrimOnDark)
                .clipShape(Circle())
            Text(text)
                .dsText(DS.Font.bodyMedium, color: DS.Colors.textOnDark)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
