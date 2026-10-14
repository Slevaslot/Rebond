import StoreKit
import SwiftData
import SwiftUI

/// The physiotherapist space's settings: the name shown to patients, Rebond Pro, demo patients, and turning the space off.
struct ProSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Query private var patients: [TrackedPatient]
    @AppStorage(PatientIdentity.physiotherapistNameKey) private var physiotherapistName = ""
    @AppStorage(AppRole.key) private var role = AppRole.patient.rawValue

    @State private var showingPaywall = false
    @State private var managingSubscription = false
    @State private var confirmingTurnOff = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    TextField("Votre nom", text: $physiotherapistName)
                        .textContentType(.name)
                } header: {
                    Text("Votre nom")
                } footer: {
                    Text("Affiché à vos patients quand ils reçoivent un programme.")
                }

                Section {
                    if store.hasPro {
                        Label("Rebond Pro : patients illimités", systemImage: "checkmark.seal.fill")
                        if store.isSubscribed {
                            Button("Gérer l'abonnement") { managingSubscription = true }
                        }
                    } else {
                        Label("Offre gratuite : \(min(patients.count, ProStore.freePatientLimit)) patients suivis sur \(ProStore.freePatientLimit)",
                              systemImage: "person.2")
                        Button("Découvrir Rebond Pro") { showingPaywall = true }
                    }
                    #if DEBUG
                    Toggle("Débloquer Pro (démo)", isOn: $store.demoUnlocked)
                    #endif
                } header: {
                    Text("Abonnement")
                } footer: {
                    Text("Rebond reste toujours gratuit pour vos patients.")
                }

                Section {
                    Button("Charger des patients de démo") { DemoData.loadPatients(into: context) }
                } footer: {
                    Text("Trois patients fictifs, pour découvrir l'espace kiné.")
                }

                Section {
                    Button("Désactiver l'espace kiné", role: .destructive) { confirmingTurnOff = true }
                    Link("Politique de confidentialité", destination: AppLinks.privacyPolicy)
                } footer: {
                    Text("Vos patients suivis restent sur cet iPhone. Vous pourrez réactiver l'espace kiné dans Réglages.")
                }
            }
            .navigationTitle("Espace kiné")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer", systemImage: "xmark", role: .close) { dismiss() } }
            .sheet(isPresented: $showingPaywall) { ProPaywall() }
            .manageSubscriptionsSheet(isPresented: $managingSubscription)
            .confirmationDialog("Désactiver l'espace kiné ?", isPresented: $confirmingTurnOff, titleVisibility: .visible) {
                Button("Désactiver", role: .destructive) {
                    dismiss()
                    role = AppRole.patient.rawValue
                }
            } message: {
                Text("L'onglet Kiné disparaît. Vos patients suivis restent enregistrés sur cet iPhone.")
            }
        }
    }
}
