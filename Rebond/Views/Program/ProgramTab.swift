import SwiftData
import SwiftUI

/// The program at a glance, in the same Health-style cards as the Accueil page: who prescribed it and when,
/// how often, then each exercise with what to do and how it is followed. Liquid Glass stays on the controls.
struct ProgramTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @AppStorage(ProgramChange.prescriberKey) private var prescriberName = ""
    @AppStorage(ProgramChange.prescribedAtKey) private var prescribedAt: Double = 0
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    @State private var editing: EditableProgram?
    @State private var savedEdit = 0
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let program = programs.first {
                    content(program)
                } else {
                    NoProgramView { header }
                }
            }
            .navigationTitle("Programme")
            // Same top bar as the Accueil page: the large title and its control on the same line, in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let editing {
                    NavigationStack {
                        ProgramEditorView(program: editing, title: "Modifier le programme") { saved in
                            Program.replaceAll(with: saved, in: context)
                            self.editing = nil
                            savedEdit += 1
                        }
                    }
                    .interactiveDismissDisabled()
                }
            }
            .sensoryFeedback(.success, trigger: savedEdit)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Programme")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            AddProgramMenu()
            // The profile stays in the same place on every tab.
            Button {
                showingSettings = true
            } label: {
                ProfileBadge(name: patientName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Réglages")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func content(_ program: Program) -> some View {
        let prescriber = ProgramChange.prescriber(of: program, prescribedAt: prescribedAt, name: prescriberName)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                PrescriptionCard(
                    program: program,
                    prescriber: prescriber,
                    week: WeekProgress(sessions: sessions, sessionsPerWeek: program.sessionsPerWeek)
                )

                HStack(alignment: .firstTextBaseline) {
                    Text("Exercices")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("Environ \(program.estimatedMinutes) min par séance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)

                ForEach(program.orderedExercises) { exercise in
                    ProgramExerciseCard(exercise: exercise)
                }

                Button {
                    editing = EditableProgram(program)
                } label: {
                    Label("Modifier le programme", systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.top, 6)

                Text("Seul votre kiné décide de votre programme. Modifiez-le pour recopier ce qu'il vous a prescrit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(alignment: .top) {
            // Tinted top, fading into the page, like the Accueil page.
            LinearGradient(colors: [Color.accentColor.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Who prescribed the program and when, and how often: the planned days of this week.
private struct PrescriptionCard: View {
    let program: Program
    /// The physiotherapist's name (empty when unknown), or nil when the patient added the program.
    let prescriber: String?
    let week: WeekProgress

    private var title: Text {
        guard let prescriber else { return Text("Programme de votre kiné") }
        return prescriber.isEmpty ? Text("Prescrit par votre kiné") : Text("Prescrit par \(prescriber)")
    }

    private var date: Text {
        let date = program.createdAt.formatted(.dateTime.day().month(.wide).year())
        return prescriber == nil ? Text("Enregistré le \(date)") : Text("Le \(date)")
    }

    /// "Lundi, mercredi et vendredi", from the same days as the reminders and the Accueil page.
    private var days: Text {
        let count = program.sessionsPerWeek
        if count >= 7 { return Text("Tous les jours") }
        let symbols = Calendar.current.weekdaySymbols
        let names = ReminderScheduler.sessionDays(count: count).map { symbols[$0 - 1] }
        return Text("Jours prévus : \(names.formatted(.list(type: .and)))")
    }

    var body: some View {
        SummaryCard(title: title, systemImage: "stethoscope", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                date
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)
                BigValue(value: "\(program.sessionsPerWeek)",
                         unit: program.sessionsPerWeek == 1 ? "séance par semaine" : "séances par semaine")
                    .accessibilityElement(children: .combine)
                Divider()
                WeekDots(week: week)
                days
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One exercise as a card: its pictogram, what to do in large type, and how it is followed.
private struct ProgramExerciseCard: View {
    let exercise: PlannedExercise

    private var amount: String {
        if let holdSeconds = exercise.holdSeconds { return "\(exercise.sets) × \(holdSeconds) s" }
        return "\(exercise.sets) × \(exercise.reps)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ExerciseBadge(exercise: exercise, size: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(amount)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text(exercise.holdSeconds == nil ? "répétitions" : "de maintien")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                TrackingBadge(exercise: exercise)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(exercise.name))
        .accessibilityValue(Text("\(Text(exercise.prescriptionDetail)), \(exercise.trackingLabel)"))
    }
}

/// "Suivi caméra", "Comptage manuel" or "Minuteur": a symbol and a word in a capsule, never a color alone.
struct TrackingBadge: View {
    let exercise: PlannedExercise

    var body: some View {
        let followed = exercise.catalogExercise != nil
        Label {
            exercise.trackingLabel
        } icon: {
            Image(systemName: exercise.trackingSymbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(followed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(followed ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: .capsule)
    }
}

/// The four ways to add a program, in a Liquid Glass button: the physiotherapist's message, their sheet
/// scanned or picked from the photos, or typed by hand.
struct AddProgramMenu: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            Button("Coller le message du kiné", systemImage: "text.bubble") { router.addProgram(from: .message) }
            Button("Scanner sa feuille", systemImage: "doc.viewfinder") { router.addProgram(from: .scan) }
            Button("Choisir une photo", systemImage: "photo") { router.addProgram(from: .photo) }
            Button("Saisir à la main", systemImage: "square.and.pencil") { router.addProgram(from: .manual) }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Nouveau programme")
    }
}

/// No program yet: it always comes from the physiotherapist, so the page says so and offers the ways to add it.
/// The page's own header stays on top, so the patient knows where they are.
struct NoProgramView<Header: View>: View {
    @ViewBuilder let header: Header
    @Environment(AppRouter.self) private var router
    #if DEBUG
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                ContentUnavailableView {
                    Label("Votre programme vient de votre kiné", systemImage: "stethoscope")
                } description: {
                    Text("Collez le message où il vous décrit vos exercices, ou scannez sa feuille.")
                } actions: {
                    Button("Coller son message", systemImage: "text.bubble") { router.addProgram(from: .message) }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    Button("Scanner sa feuille", systemImage: "doc.viewfinder") { router.addProgram(from: .scan) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    Button("Saisir à la main") { router.addProgram(from: .manual) }
                        .frame(minHeight: 44)
                    #if DEBUG
                    Button("Programme de démo") { DemoData.load(into: context) }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                    #endif
                }
                .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
            }
            .padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
    }
}
