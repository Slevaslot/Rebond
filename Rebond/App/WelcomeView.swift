import SwiftUI

/// First launch only: what Rebond is in one sentence, the medical notice, and who is using this iPhone.
/// A single screen, no permission asked (HIG *Onboarding*, *Privacy*). The physiotherapist lands on their space;
/// the choice can be changed later in Réglages.
struct WelcomeView: View {
    let onChoose: (AppRole) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 18) {
                Image(systemName: "figure.strengthtraining.functional")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: 30))
                    .accessibilityHidden(true)
                Text("Rebond")
                    .font(.largeTitle.bold())
                Text("Votre rééducation à la maison, suivie par votre kiné.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button { onChoose(.patient) } label: {
                    Text("Je suis patient")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button { onChoose(.physiotherapist) } label: {
                    Label("Je suis kiné", systemImage: "stethoscope")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Label("Rebond ne remplace pas l'avis d'un professionnel de santé. Seul votre kiné décide de votre programme.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
        .padding(.horizontal, 24)
        .padding(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            PageTint(color: Color.accentColor, opacity: 0.45)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    WelcomeView { _ in }
}
