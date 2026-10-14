import SwiftUI

/// A followed patient, from their last report: what needs attention, the week's regularity, pain, repetitions and
/// amplitude, the same charts the patient sees, and their program to adjust and send back by QR code.
/// Only the physiotherapist decides what comes next: the app never changes the program by itself.
struct PatientDetailView: View {
    let patient: TrackedPatient
    let onStopFollowing: () -> Void

    @State private var adjusting: PrescribingItem?
    @State private var confirmingStop = false

    var body: some View {
        Group {
            if let transfer = patient.transfer {
                content(transfer)
            } else {
                ContentUnavailableView("Bilan illisible", systemImage: "doc.questionmark",
                                       description: Text("Demandez à votre patient de vous renvoyer son bilan."))
            }
        }
        .navigationTitle(patient.name)
        .sheet(item: $adjusting) { item in
            PrescribeFlow(program: item.program, title: "Programme de \(patient.name)", patientName: patient.name)
        }
        .confirmationDialog("Arrêter le suivi de \(patient.name) ?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Arrêter le suivi", role: .destructive, action: onStopFollowing)
        } message: {
            Text("Ses bilans sont effacés de cet iPhone. Il réapparaîtra s'il vous envoie un nouveau bilan.")
        }
    }

    private func content(_ transfer: ReportTransfer) -> some View {
        let overview = PatientOverview(name: patient.name, transfer: transfer)
        let progress = ProgressData(sessions: transfer.sessionData, sessionsPerWeek: transfer.sessionsPerWeek, weeks: 6, now: transfer.generatedAt)
        let week = overview.week
        let painful = transfer.sessionData
            .filter { $0.date > week.start && $0.date <= week.end && $0.pain >= WeeklyReport.highPain }
            .sorted { $0.date < $1.date }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // The report's period, and what needs attention.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bilan du \(transfer.generatedAt, format: .dateTime.day().month(.wide).year())")
                        .font(.headline)
                    Text("Semaine du \(week.start, format: .dateTime.day().month(.wide)) au \(week.end, format: .dateTime.day().month(.wide))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    AttentionLabel(overview: overview)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 4)

                if !painful.isEmpty {
                    SummaryCard(title: Text("Douleur forte signalée"), systemImage: "exclamationmark.triangle.fill", color: .orange) {
                        EmptyView()
                    } content: {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(painful, id: \.date) { session in
                                HStack {
                                    Text(session.date, format: .dateTime.weekday(.wide).day().month(.wide))
                                    Spacer()
                                    Text("\(session.pain) sur 10")
                                        .font(.body.weight(.semibold))
                                        .monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                            }
                            Text("Douleur de \(WeeklyReport.highPain) ou plus indiquée par le patient en fin de séance. C'est vous qui décidez de la suite.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                SummaryCard(title: Text("Régularité"), systemImage: "calendar", color: .teal) {
                    Text("7 derniers jours")
                } content: {
                    VStack(alignment: .leading, spacing: 12) {
                        BigValue(value: "\(week.sessionsDone)", unit: "sur \(week.sessionsPlanned) séances")
                        RegularityChart(data: progress)
                            .frame(height: 160)
                    }
                }

                SummaryCard(title: Text("Douleur"), systemImage: "bandage.fill", color: .orange) {
                    Text("Après chaque séance")
                } content: {
                    VStack(alignment: .leading, spacing: 12) {
                        if let last = overview.lastPain {
                            BigValue(value: "\(last)", unit: "sur 10")
                            if let average = week.averagePain {
                                Text("Moyenne de la semaine : \(average.formatted(.number.precision(.fractionLength(0...1)))) sur 10")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Aucune séance cette semaine.")
                                .foregroundStyle(.secondary)
                        }
                        if !progress.pain.isEmpty {
                            PainChart(data: progress)
                                .frame(height: 160)
                        }
                    }
                }

                if !week.exercises.isEmpty {
                    SummaryCard(title: Text("Exercices de la semaine"), systemImage: "figure.strengthtraining.functional", color: .purple) {
                        EmptyView()
                    } content: {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(week.exercises.enumerated()), id: \.element.id) { index, line in
                                if index > 0 { Divider().padding(.vertical, 8) }
                                ExerciseLineView(line: line)
                            }
                        }
                    }
                }

                if !progress.amplitude.isEmpty {
                    SummaryCard(title: Text("Amplitude"), systemImage: "arrow.up.and.down", color: .blue) {
                        Text("% de l'objectif")
                    } content: {
                        VStack(alignment: .leading, spacing: 12) {
                            AmplitudeChart(data: progress)
                                .frame(height: 200)
                            Text("Meilleure répétition de chaque séance, mesurée par la caméra du patient, à titre indicatif : 100 % correspond à l'objectif du mouvement.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                ProgramCard(program: transfer.program) {
                    adjusting = PrescribingItem(program: transfer.program?.editableProgram ?? EditableProgram())
                }

                Button("Arrêter le suivi", systemImage: "person.badge.minus", role: .destructive) { confirmingStop = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// One exercise over the week: repetitions done (and incomplete) or seconds held, and the amplitude's change.
private struct ExerciseLineView: View {
    let line: WeeklyReport.ExerciseLine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.name)
                .font(.headline)
            if line.isHeld {
                Text("\(line.heldSeconds) s tenues sur \(line.plannedSeconds) s")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(line.completedReps) répétitions sur \(line.plannedReps)")
                    .foregroundStyle(.secondary)
                if line.incompleteReps > 0 {
                    Text("^[\(line.incompleteReps) répétition incomplète](inflect: true), comptées à part")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let first = line.firstAmplitude {
                if let last = line.lastAmplitude {
                    Text("Amplitude : \(Int(first.rounded())) % puis \(Int(last.rounded())) %")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                } else {
                    Text("Amplitude : \(Int(first.rounded())) %")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The patient's current program, as sent with the report, and the way to adjust it.
private struct ProgramCard: View {
    let program: ProgramTransfer?
    let onAdjust: () -> Void

    var body: some View {
        SummaryCard(title: Text("Programme actuel"), systemImage: "list.bullet.clipboard", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let program {
                    Text("^[\(program.f) séance](inflect: true) par semaine")
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(program.e.enumerated()), id: \.offset) { _, exercise in
                            HStack {
                                Text(exercise.n)
                                Spacer()
                                Group {
                                    if let hold = exercise.h {
                                        Text("\(exercise.s) × \(hold) s")
                                    } else {
                                        Text("\(exercise.s) × \(exercise.r)")
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } else {
                    Text("Le bilan ne contient pas le programme. Vous pouvez en prescrire un nouveau.")
                        .foregroundStyle(.secondary)
                }
                Text("Le nouveau programme s'affiche en QR code : votre patient le scanne et le vérifie avant de l'enregistrer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAdjust) {
                    Label(program == nil ? "Prescrire un programme" : "Ajuster le programme", systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
    }
}
