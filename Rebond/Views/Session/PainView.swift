import SwiftData
import SwiftUI
import TipKit

/// End of session: pain level from 0 to 10. From 7, a calm message, never blocking.
struct PainView: View {
    let nothingDone: Bool
    let onSave: (Int) -> Void
    let onDiscard: () -> Void

    @State private var pain = 0.0

    private var level: Int { Int(pain) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text(level, format: .number)
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(Self.word(for: level))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Slider(value: $pain, in: 0...10, step: 1) {
                        Text("Douleur")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("10")
                    }
                    .accessibilityValue(Text("\(level) sur 10, \(Text(Self.word(for: level)))"))
                }
                .padding(.vertical)
                .animation(.default, value: level)
            } header: {
                Text("Quelle douleur avez-vous ressentie ?")
            } footer: {
                Text("0 : aucune douleur. 10 : douleur insupportable.")
            }

            if level >= WeeklyReport.highPain {
                Section {
                    Label("Si la douleur est forte ou inhabituelle, faites une pause et parlez-en à votre kiné.", systemImage: "heart.text.square")
                }
            }

            if nothingDone {
                Section {
                    Button("Ne pas enregistrer", role: .destructive, action: onDiscard)
                } footer: {
                    Text("Aucun exercice n'a été fait pendant cette séance.")
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            Button {
                onSave(level)
            } label: {
                Text("Enregistrer la séance")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.horizontal)
        }
        .navigationTitle("Fin de séance")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: level)
    }

    static func word(for level: Int) -> LocalizedStringKey {
        switch level {
        case 0: "Aucune douleur"
        case 1...3: "Légère"
        case 4...6: "Modérée"
        case 7...9: "Forte"
        default: "Insupportable"
        }
    }
}

/// What the session produced, to end on a positive note. Offers the reminders once, then Health once.
struct WorkoutSummaryView: View {
    let session: Session
    let onDone: () -> Void

    @AppStorage(ReminderSettings.enabledKey) private var remindersEnabled = false
    @AppStorage("hasOfferedReminders") private var hasOfferedReminders = false
    @AppStorage(PhoneHealth.offeredKey) private var hasOfferedHealth = false
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    private let health = PhoneHealth.shared
    private let watch = PhoneWatchLink.shared
    private let watchAppTip = WatchAppTip()
    /// Shown when the summary opens: answering an offer doesn't make the tip appear under the patient's finger.
    @State private var offersSomething = true

    var body: some View {
        List {
            Section {
                ContentUnavailableView {
                    Label("Séance terminée, bravo !", systemImage: "checkmark.seal.fill")
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(.bounce, options: .nonRepeating)
                } description: {
                    Text("\(Duration.seconds(session.duration), format: .units(allowed: [.minutes], width: .wide)) d'exercices")
                }
            }
            Section("Ce que vous avez fait") {
                ForEach(session.orderedResults) { result in
                    ResultRow(result: result)
                }
                LabeledContent("Douleur", value: "\(session.pain) / 10")
            }
            // A paired Apple Watch without Rebond: one suggestion at a time, so only when nothing else is offered.
            if watch.isWatchPaired, !watch.isWatchAppInstalled, !offersSomething {
                Section {
                    // The tip is its own card: no list row around it.
                    TipView(watchAppTip)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if offersReminders {
                Section {
                    Label("Recevoir un rappel les jours de séance ?", systemImage: "bell.badge")
                    Button("Activer les rappels") {
                        hasOfferedReminders = true
                        Task {
                            remindersEnabled = await ReminderScheduler.enable(days: programs.isEmpty ? ReminderScheduler.sessionDays(count: 3) : programs.allDays)
                        }
                    }
                    Button("Plus tard") { hasOfferedReminders = true }
                        .foregroundStyle(.secondary)
                }
            }
            healthSection
        }
        .navigationTitle("Résumé")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { offersSomething = offersReminders || offersHealth }
        .safeAreaBar(edge: .bottom) {
            Button(action: onDone) {
                Text("Terminer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.horizontal)
        }
    }
}

extension WorkoutSummaryView {
    private var offersReminders: Bool {
        !remindersEnabled && !hasOfferedReminders
    }

    /// One offer at a time: the reminders first, Health at a later session.
    private var offersHealth: Bool {
        health.lastRecording == .none && PhoneHealth.isAvailable && !health.isEnabled && !hasOfferedHealth
            && (remindersEnabled || hasOfferedReminders)
    }

    /// Where the workout went in Health, or the offer to save the sessions there (once).
    @ViewBuilder
    private var healthSection: some View {
        switch health.lastRecording {
        case .watch:
            Section {
                Label("Enregistrée dans Santé par votre Apple Watch", systemImage: "applewatch")
            }
        case .phone:
            Section {
                Label {
                    Text("Enregistrée dans Santé")
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
            }
        case .none:
            // One offer at a time: the reminders first, Health at a later session.
            if offersHealth {
                Section {
                    Label("Ajouter vos séances à l'app Santé ?", systemImage: "heart.text.square")
                    Button("Enregistrer dans Santé") {
                        hasOfferedHealth = true
                        Task {
                            if await health.enable() {
                                health.recordAfterEnabling(start: session.date.addingTimeInterval(-session.duration), end: session.date)
                            }
                        }
                    }
                    Button("Plus tard") { hasOfferedHealth = true }
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Chaque séance devient un entraînement dans Santé et compte dans vos anneaux d'Activité. Avec une Apple Watch, votre fréquence cardiaque est enregistrée aussi.")
                }
            }
        }
    }
}

/// One exercise of a saved session.
struct ResultRow: View {
    let result: ExerciseResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.exerciseName)
                .font(.headline)
            if result.isHeld {
                Text("\(result.heldSeconds) s tenues sur \(result.plannedSeconds) s")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(result.completedReps) répétitions sur \(result.plannedReps)")
                    .foregroundStyle(.secondary)
                if result.incompleteReps > 0 {
                    Text("\(result.incompleteReps) incomplètes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let amplitude = result.amplitude {
                Text("Amplitude habituelle : \(Int(amplitude.rounded())) % de l'objectif")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
