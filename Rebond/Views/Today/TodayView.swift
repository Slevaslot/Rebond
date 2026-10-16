import Charts
import SwiftData
import SwiftUI

/// The session to do, laid out like the Health app's Summary: a tinted header, large cards with a colored
/// category label, a big rounded value and a small chart, bold section titles. Liquid Glass stays in the
/// navigation layer (toolbar, tab bar). Editing the program lives in the Programme tab.
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(filter: Session.programSessions, sort: \Session.date, order: .reverse) private var sessions: [Session]
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    @AppStorage(AlertsGroup.dismissedKey) private var dismissedPainAlert: Double = 0
    @State private var restoredAlert = 0
    @State private var showingSettings = false
    @State private var showingReport = false

    var body: some View {
        NavigationStack {
            Group {
                if !programs.isEmpty {
                    today
                } else {
                    NoProgramView { header }
                }
            }
            .navigationTitle("Accueil")
            // Fitness-style top bar: the large title and the profile on the same line, in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            // Reminders follow the program's frequency, whichever way it was saved.
            .task(id: programs.allDays) {
                if !programs.isEmpty {
                    await ReminderScheduler.refreshIfEnabled(days: programs.allDays)
                }
            }
            .sheet(isPresented: $showingReport) {
                NavigationStack {
                    ReportView()
                        .toolbar {
                            Button("Fermer", systemImage: "xmark", role: .close) { showingReport = false }
                        }
                }
            }
        }
    }

    private var header: some View {
        PageHeader("Accueil") {
            ProfileButton { showingSettings = true }
        }
    }

    private var today: some View {
        let week = WeekProgress(sessions: sessions, sessionsPerWeek: programs.sessionsPerWeek, plannedDays: programs.allDays)
        let todays = programs.scheduled(on: .now)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                AlertsGroup(sessions: sessions, onReport: { showingReport = true })

                if todays.isEmpty {
                    RestDayCard(programs: programs)
                } else {
                    ForEach(todays) { program in
                        // With several programs, the card says which one it is.
                        SessionCard(program: program, title: programs.active.count > 1 ? program.title : nil) {
                            router.startWorkout(program)
                        }
                    }
                }

                FollowUpSection(sessions: sessions, sessionsPerWeek: programs.sessionsPerWeek, week: week)

                MedicalDisclaimer()
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        // Pulling the page down brings back the alert of a painful session that was dismissed;
        // the page bounces even when it is shorter than the screen.
        .scrollBounceBehavior(.always)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < -50
        } action: { _, pulled in
            guard pulled, dismissedPainAlert != 0 else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { dismissedPainAlert = 0 }
            restoredAlert += 1
        }
        .sensoryFeedback(.success, trigger: restoredAlert)
        .background(alignment: .top) {
            // Tinted top, fading into the page, like Health's Summary.
            PageTint(color: Color.accentColor, opacity: 0.45)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Cards

/// A Health-style card: a colored category label with an optional trailing detail, then the content.
struct SummaryCard<Content: View, Trailing: View>: View {
    let title: Text
    let systemImage: String?
    var icon: CatalogExercise?
    let color: Color
    /// Section-style header, like Health's "BIEN-ÊTRE MENTAL": capitals, bold, gray, no icon.
    var sectionHeader = false
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                if sectionHeader {
                    title
                        .textCase(.uppercase)
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                } else {
                Label {
                    title
                } icon: {
                    if let icon {
                        Image(systemName: icon.symbol)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                    }
                }
                .font(.headline)
                .foregroundStyle(color)
                .tint(color)
                }
                Spacer(minLength: 8)
                trailing
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }
}

/// A big rounded value with its unit, as in Health ("3 717 pas").
struct BigValue: View {
    let value: String
    let unit: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // Read as one: "4 min", "2 sur 10".
        .accessibilityElement(children: .combine)
    }
}

/// Today's session: how long it takes and how many exercises.
private struct SessionCard: View {
    let program: Program
    /// The program's name, shown when the patient follows several.
    var title: String?
    let onStart: () -> Void
    @Environment(\.workoutTransition) private var workoutTransition

    /// The exercises stay folded to keep the page light; tapping the card unfolds them in place.
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SummaryCard(title: Text("Séance du jour"), systemImage: nil, color: .accentColor, sectionHeader: true) {
            // The chevron tells the card unfolds, like an expandable row in iOS.
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .padding(.top, -6)
                }
                HStack(alignment: .bottom) {
                    BigValue(value: "\(program.estimatedMinutes)", unit: "min")
                        .accessibilityLabel(Text("Durée estimée : \(program.estimatedMinutes) minutes"))
                    Spacer()
                    if !expanded {
                        HStack(spacing: -6) {
                            ForEach(program.orderedExercises.prefix(4)) { exercise in
                                ExerciseBadge(exercise: exercise, size: 38)
                                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            }
                        }
                        .transition(.blurReplace)
                        .accessibilityHidden(true)
                    }
                }

                // With the largest text sizes the list is long: Commencer stays on screen, above it.
                if dynamicTypeSize.isAccessibilitySize { startButton }

                if expanded {
                    VStack(spacing: 0) {
                        ForEach(Array(program.orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                            if index > 0 { Divider().padding(.leading, 54) }
                            HStack(spacing: 12) {
                                ExerciseBadge(exercise: exercise, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).font(.headline)
                                    Text(exercise.prescriptionDetail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: exercise.trackingSymbol)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(exercise.trackingLabel)
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }

                if !dynamicTypeSize.isAccessibilitySize { startButton }
            }
        }
        // The session zooms out of the whole card: a plain rounded shape, so nothing of the glass button
        // or its glow is cut out during the transition.
        .modifier(WorkoutSource(namespace: workoutTransition))
        // Tapping anywhere on the card (except Commencer) shows or hides the exercises.
        .contentShape(.rect(cornerRadius: 26))
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { expanded.toggle() }
        }
        .accessibilityAction(named: expanded ? Text("Masquer les exercices") : Text("Voir les exercices")) {
            withAnimation { expanded.toggle() }
        }
        .sensoryFeedback(.selection, trigger: expanded)
    }

    private var startButton: some View {
        Button(action: onStart) {
            Text("Commencer")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        // A soft glow lifts the main action off the card.
        .shadow(color: Color.accentColor.opacity(0.45), radius: 14, y: 6)
    }
}

/// Required on the App Store and in the spirit of Rebond: at the foot of Accueil, with or without a program.
struct MedicalDisclaimer: View {
    var body: some View {
        Label("Rebond ne remplace pas l'avis d'un professionnel de santé. Seul votre kiné décide de votre programme.",
              systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

/// No program planned today: rest, the next session, and a session anyway for those who want one.
private struct RestDayCard: View {
    let programs: [Program]
    @Environment(AppRouter.self) private var router

    private var next: (program: Program, day: Date)? { programs.next() }

    private var anywayLabel: some View {
        Text("Faire une séance quand même")
            .font(.headline)
            .frame(maxWidth: .infinity)
    }

    var body: some View {
        SummaryCard(title: Text("Séance du jour"), systemImage: nil, color: .accentColor, sectionHeader: true) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if programs.active.isEmpty {
                    Label("Aucune séance suivie", systemImage: "list.bullet.clipboard")
                        .font(.title2.bold())
                    Text("Choisissez la séance à suivre dans Exercices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        router.tab = .program
                    } label: {
                        Text("Choisir une séance")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                } else {
                    Label("Repos aujourd'hui", systemImage: "moon.zzz.fill")
                        .font(.title2.bold())
                    if let next {
                        Text("Prochaine séance \(next.day.formatted(.dateTime.weekday(.wide))) : \(next.program.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    anywayButton
                }
            }
        }
    }

    private var anywayButton: some View {
        let followed = programs.active
        return Group {
            if followed.count == 1 {
                Button { router.startWorkout(followed[0]) } label: { anywayLabel }
            } else {
                Menu {
                    ForEach(followed) { program in
                        Button(program.title) { router.startWorkout(program) }
                    }
                } label: { anywayLabel }
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// Marks the Commencer button as the start of the zoom into the session.
private struct WorkoutSource: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: WorkoutTransition.sourceID, in: namespace) { source in
                source.clipShape(.rect(cornerRadius: 26))
            }
        } else {
            content
        }
    }
}

/// An exercise's symbol in a tinted circle: the same `figure.*` workout symbols as Apple's Fitness app.
struct ExerciseBadge: View {
    let exercise: PlannedExercise
    let size: Double

    var body: some View {
        Image(systemName: exercise.figureSymbol)
            .font(.system(size: size * 0.45))
            .accessibilityHidden(true)
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(Color(.tertiarySystemGroupedBackground), in: .circle)
    }
}



/// The tint at the top of the pages, fading into the grey background along an eased curve and over a long
/// distance, so no edge shows where it ends.
struct PageTint: View {
    var color: Color = .accentColor
    var opacity: Double = 0.45

    var body: some View {
        LinearGradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.82), location: 0.2),
            .init(color: color.opacity(opacity * 0.55), location: 0.42),
            .init(color: color.opacity(opacity * 0.28), location: 0.64),
            .init(color: color.opacity(opacity * 0.09), location: 0.85),
            .init(color: color.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: 480)
    }
}

/// The top of every tab: the large title and its buttons on one line, in the page (Fitness style).
/// The same height and spacing everywhere, so nothing moves when switching tabs.
struct PageHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .frame(height: 52)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// The profile, at the same place on every tab: opens Réglages.
struct ProfileButton: View {
    let action: () -> Void
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""

    var body: some View {
        Button(action: action) {
            ProfileBadge(name: patientName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Réglages")
    }
}

/// A round Liquid Glass button for the top of a tab, the size of the profile.
struct HeaderIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// The patient's initials, or a person symbol, as Health's profile button:
/// a soft gradient disc inside a Liquid Glass ring.
struct ProfileBadge: View {
    let name: String

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Group {
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.body.weight(.semibold))
            } else {
                Text(initials)
                    .font(.body.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 38, height: 38)
        .background(
            LinearGradient(colors: [Color(red: 0.66, green: 0.70, blue: 0.96), Color(red: 0.43, green: 0.47, blue: 0.86)],
                           startPoint: .top, endPoint: .bottom),
            in: .circle
        )
        .padding(4)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

// MARK: - Model helpers

/// Sessions done this calendar week against the program's frequency, like the regularity chart.
struct WeekProgress {
    let done: Int
    let planned: Int
    /// Calendar weekdays with a planned session.
    let plannedDays: Set<Int>
    /// The days of this week, with whether a session was done that day.
    let days: [(date: Date, done: Bool)]

    init(sessions: [Session], sessionsPerWeek: Int, plannedDays: [Int]? = nil, now: Date = .now) {
        self.plannedDays = Set(plannedDays ?? ReminderScheduler.sessionDays(count: sessionsPerWeek))
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        done = sessions.filter { week?.contains($0.date) ?? false }.count
        planned = sessionsPerWeek
        days = (0..<7).compactMap { offset in
            guard let start = week?.start, let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (day, sessions.contains { calendar.isDate($0.date, inSameDayAs: day) })
        }
    }

    var summary: LocalizedStringKey {
        done >= planned ? "Objectif atteint : \(done) séances" : "\(done) séances sur \(planned)"
    }
}

extension PlannedExercise {
    /// "3 séries de 10 répétitions" or "2 séries de 30 s de maintien".
    var prescriptionDetail: LocalizedStringKey {
        if let holdSeconds {
            return bothSides
                ? "^[\(sets) série](inflect: true) de \(holdSeconds) s de maintien, de chaque côté"
                : "^[\(sets) série](inflect: true) de \(holdSeconds) s de maintien"
        }
        return bothSides
            ? "^[\(sets) série](inflect: true) de ^[\(reps) répétition](inflect: true), de chaque côté"
            : "^[\(sets) série](inflect: true) de ^[\(reps) répétition](inflect: true)"
    }

    /// "Suivi caméra", "Comptage manuel" or "Minuteur", with its symbol.
    var trackingSymbol: String {
        if catalogExercise != nil { return "camera.viewfinder" }
        return holdSeconds == nil ? "hand.tap" : "timer"
    }

    var trackingLabel: Text {
        if catalogExercise != nil { return Text("Suivi caméra") }
        return holdSeconds == nil ? Text("Comptage manuel") : Text("Minuteur")
    }

    /// A `figure.*` symbol for an exercise the camera doesn't follow, guessed from its name.
    var figureSymbol: String {
        if let catalogExercise { return catalogExercise.symbol }
        let name = self.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        // The workout symbols closest to the movement (checked one by one against the exercises).
        let symbols: [(words: [String], symbol: String)] = [
            (["gainage", "planche", "plank", "abdo"], "figure.core.training"),
            (["pont", "bassin", "bridge"], "figure.pilates"),
            (["etirement", "stretch", "souplesse"], "figure.cooldown"),
            (["fente", "lunge"], "figure.strengthtraining.functional"),
            (["squat", "flexion"], "figure.cross.training"),
            (["assis", "chaise"], "chair.fill"),
            (["escalier", "step", "marche d"], "figure.stairs"),
            (["velo", "pedal"], "figure.indoor.cycle"),
            (["marche", "walk"], "figure.walk"),
            (["equilibre", "unipodal", "balance"], "figure.yoga"),
            (["respiration", "relaxation"], "figure.mind.and.body"),
            (["genou"], "figure.highintensity.intervaltraining"),
            (["jambe"], "figure.kickboxing"),
            (["rotation"], "figure.taichi"),
            (["bras", "epaule", "coude", "poignet"], "figure.mixed.cardio"),
        ]
        if let match = symbols.first(where: { entry in entry.words.contains { name.contains($0) } }) {
            return match.symbol
        }
        return holdSeconds == nil ? "figure.cooldown" : "figure.core.training"
    }
}

extension Program {
    /// Rough duration: about 4 s per repetition or the hold time, plus 30 s between sets.
    var estimatedMinutes: Int {
        exercises.estimatedMinutes
    }
}

nonisolated extension Array where Element == PlannedExercise {
    /// Rough duration: about 4 s per repetition or the hold time, plus 30 s between sets.
    var estimatedMinutes: Int {
        let seconds = reduce(0) { total, exercise in
            let perSet = exercise.holdSeconds ?? exercise.reps * 4
            return total + exercise.sets * (exercise.bothSides ? 2 : 1) * (perSet + 30)
        }
        return Swift.max(1, Int((Double(seconds) / 60).rounded()))
    }
}
