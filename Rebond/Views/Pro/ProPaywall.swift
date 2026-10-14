import StoreKit
import SwiftUI

/// Rebond Pro, for physiotherapists, with the system subscription store: Liquid Glass, restore, offer codes.
struct ProPaywall: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var store

    var body: some View {
        SubscriptionStoreView(productIDs: ProStore.productIDs) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Rebond Pro")
                    .font(.largeTitle.bold())
                Text("Suivez tous vos patients. Rebond reste gratuit pour eux.")
                    .foregroundStyle(.secondary)
                benefit("infinity", "Patients illimités", "L'offre gratuite suit jusqu'à \(ProStore.freePatientLimit) patients.")
                benefit("person.2", "Tout leur suivi", "Régularité, répétitions, amplitude et douleur, avec les séances douloureuses signalées.")
                benefit("qrcode", "Programmes en QR code", "Prescrivez et ajustez les programmes sans feuille à recopier.")
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
