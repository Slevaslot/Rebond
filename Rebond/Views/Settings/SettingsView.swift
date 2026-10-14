import SwiftData
import SwiftUI

/// Reminders, Rebond Plus, privacy and the medical notice.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    @AppStorage(AppRole.key) private var role = AppRole.patient.rawValue
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @AppStorage(ReminderSettings.enabledKey) private var remindersEnabled = false
    @AppStorage(ReminderSettings.hourKey) private var reminderHour = ReminderSettings.defaultHour
    @State private var confirmingDemo = false

    private var sessionsPerWeek: Int { programs.first?.sessionsPerWeek ?? 3 }

    var body: some View {
        NavigationStack {
            Form {
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
                } header: {
                    Text("Rappels")
                } footer: {
                    Text("Un rappel les jours de séance (\(sessionsPerWeek) par semaine), et le dimanche pour envoyer votre bilan à votre kiné.")
                }

                Section {
                    TextField("Votre nom", text: $patientName)
                        .textContentType(.name)
                } header: {
                    Text("Vous")
                } footer: {
                    Text("Affiché sur le bilan que vous envoyez à votre kiné.")
                }

                Section {
                    Button("Ouvrir l'espace kiné", systemImage: "stethoscope") {
                        dismiss()
                        role = AppRole.physiotherapist.rawValue
                    }
                } header: {
                    Text("Vous êtes kiné ?")
                } footer: {
                    Text("Prescrivez vos programmes en QR code et suivez vos patients avec Rebond Pro.")
                }

                Section("Données") {
                    Button("Charger les données de démo") { confirmingDemo = true }
                        .confirmationDialog("Remplacer le programme et l'historique par les données de démo ?", isPresented: $confirmingDemo, titleVisibility: .visible) {
                            Button("Remplacer", role: .destructive) { DemoData.load(into: context) }
                        }
                }

                Section {
                    Label("Rebond ne remplace pas l'avis d'un professionnel de santé. Seul votre kiné décide de votre programme.", systemImage: "stethoscope")
                    Label("Tout reste sur votre iPhone : vos images, vos séances et votre programme. Seul le bilan que vous choisissez d'envoyer quitte l'appareil.", systemImage: "lock.shield")
                    Link("Politique de confidentialité", destination: AppLinks.privacyPolicy)
                } header: {
                    Text("À propos")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
    }
}
