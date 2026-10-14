import SwiftData
import SwiftUI

/// Settings on a single screen, without scrolling: the patient, the reminders, the physiotherapist space,
/// and "À propos" (medical notice, privacy) one level down.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    @AppStorage(AppRole.key) private var role = AppRole.patient.rawValue
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @AppStorage(ReminderSettings.enabledKey) private var remindersEnabled = false
    @AppStorage(ReminderSettings.hourKey) private var reminderHour = ReminderSettings.defaultHour

    private var sessionsPerWeek: Int { programs.first?.sessionsPerWeek ?? 3 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Votre nom", text: $patientName)
                        .textContentType(.name)
                } footer: {
                    Text("Affiché sur le bilan envoyé à votre kiné.")
                }

                Section {
                    Toggle("Rappels de séance", isOn: Binding(
                        get: { remindersEnabled },
                        set: { on in
                            Task {
                                if on {
                                    remindersEnabled = await ReminderScheduler.enable(sessionsPerWeek: sessionsPerWeek, hour: reminderHour)
                                } else {
                                    ReminderScheduler.disable()
                                    remindersEnabled = false
                                }
                            }
                        }
                    ))
                    if remindersEnabled {
                        Picker("Heure", selection: $reminderHour) {
                            ForEach(7..<22) { hour in
                                Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!, format: .dateTime.hour())
                                    .tag(hour)
                            }
                        }
                        .onChange(of: reminderHour) {
                            Task { await ReminderScheduler.schedule(sessionsPerWeek: sessionsPerWeek, hour: reminderHour) }
                        }
                    }
                }

                Section {
                    Button("Espace kiné", systemImage: "stethoscope") {
                        dismiss()
                        role = AppRole.physiotherapist.rawValue
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("À propos", systemImage: "info.circle")
                    }
                }
            }
            .scrollDisabled(true)
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
    }
}

/// The medical notice, privacy, and the demo data (development builds only).
private struct AboutView: View {
    @Environment(\.modelContext) private var context
    @State private var confirmingDemo = false

    var body: some View {
        Form {
            Section {
                Label("Rebond ne remplace pas l'avis d'un professionnel de santé. Seul votre kiné décide de votre programme.", systemImage: "stethoscope")
                Label("Tout reste sur votre iPhone. Seul le bilan que vous choisissez d'envoyer quitte l'appareil.", systemImage: "lock.shield")
                Link("Politique de confidentialité", destination: AppLinks.privacyPolicy)
            }
            #if DEBUG
            Section("Démo") {
                Button("Charger les données de démo") { confirmingDemo = true }
                    .confirmationDialog("Remplacer le programme et l'historique par les données de démo ?", isPresented: $confirmingDemo, titleVisibility: .visible) {
                        Button("Remplacer", role: .destructive) { DemoData.load(into: context) }
                    }
            }
            #endif
        }
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }
}
