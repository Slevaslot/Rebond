import StoreKit
import SwiftUI

/// Rebond Pro, for physiotherapists, with the system subscription store: the plans by number of patients, monthly
/// or yearly, restore, offer codes. An upgrade from a lower plan is a system upgrade, prorated by the App Store.
struct ProPaywall: View {
    /// Real patients followed now, to suggest the plan that fits.
    var followed = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var store
    @State private var period = ProPlan.Period.monthly

    var body: some View {
        // One period at a time: three plans side by side, priced by the number of patients.
        SubscriptionStoreView(productIDs: ProPlan.productIDs(period)) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Rebond Pro")
                    .font(.largeTitle.bold())
                Text("Un prix selon le nombre de patients que vous suivez. Rebond reste gratuit pour eux.")
                    .foregroundStyle(.secondary)
                benefit("person.3", "10, 30 ou illimité", "Rebond Pro 10, Rebond Pro 30 ou Rebond Cabinet. L'offre gratuite suit \(ProPlan.freePatientLimit) patients.")
                benefit("gift", "1 mois offert", "Sur chaque offre, résiliable à tout moment.")
                benefit("arrow.up.circle", "Changez d'offre quand vous voulez", "Le passage à l'offre supérieure est calculé au prorata par l'App Store.")
                Label {
                    Text("Vous suivez \(followed) patients : \(Text(ProPlan.suggested(forPatients: followed).name)) vous suffit.")
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                Picker("Facturation", selection: $period) {
                    Text("Mensuel").tag(ProPlan.Period.monthly)
                    Text("Annuel").tag(ProPlan.Period.yearly)
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases, .redeemCode, .cancellation)
        .subscriptionStorePolicyDestination(url: AppLinks.privacyPolicy, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: AppLinks.terms, for: .termsOfService)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                await store.refresh()
                dismiss()
            }
        }
    }

    private func benefit(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
