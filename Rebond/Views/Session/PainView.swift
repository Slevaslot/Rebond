import SwiftData
import SwiftUI

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
                    .accessibilityValue(Text("\(level) sur 10") + Text(", ") + Text(Self.word(for: level)))
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

/// What the session produced, to end on a positive note. Offers the reminders once.
struct WorkoutSummaryView: View {
    let session: Session
    let onDone: () -> Void

    @AppStorage(ReminderSettings.enabledKey) private var remindersEnabled = false
    @AppStorage("hasOfferedReminders") private var hasOfferedReminders = false
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]

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
            if !remindersEnabled, !hasOfferedReminders {
                Section {
                    Label("Recevoir un rappel les jours de séance ?", systemImage: "bell.badge")
                    Button("Activer les rappels") {
                        hasOfferedReminders = true
                        Task {
                            remindersEnabled = await ReminderScheduler.enable(sessionsPerWeek: programs.first?.sessionsPerWeek ?? 3)
                        }
                    }
                    Button("Plus tard") { hasOfferedReminders = true }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Résumé")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("Meilleure amplitude : \(Int(amplitude.rounded())) % de l'objectif")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
