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
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    @AppStorage(AlertsGroup.dismissedKey) private var dismissedPainAlert: Double = 0
    @State private var restoredAlert = 0
    @State private var showingSettings = false
    @State private var showingReport = false

    var body: some View {
        NavigationStack {
            Group {
                if let program = programs.first {
                    today(program)
                } else {
                    noProgram
                }
            }
            .navigationTitle("Aujourd'hui")
            // Fitness-style top bar: the large title and the profile on the same line, in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
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
        HStack(alignment: .center) {
            Text("Aujourd'hui")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
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

    private var noProgram: some View {
        ContentUnavailableView {
            Label("Votre programme", systemImage: "doc.viewfinder")
        } description: {
            Text("Scannez la feuille de votre kiné.")
        } actions: {
            Button("Scanner ma feuille") { router.addProgram(from: .scan) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            Button("Saisir à la main") { router.addProgram(from: .manual) }
            Button("Programme de démo") { DemoData.load(into: context) }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func today(_ program: Program) -> some View {
        let week = WeekProgress(sessions: sessions, sessionsPerWeek: program.sessionsPerWeek)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                AlertsGroup(sessions: sessions, onReport: { showingReport = true }, onShowProgram: { router.tab = .program })

                SessionCard(program: program) { router.startWorkout() }

                FollowUpSection(sessions: sessions, sessionsPerWeek: program.sessionsPerWeek, week: week)
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
            LinearGradient(colors: [Color.accentColor.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
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
                        ExerciseIcon(exercise: icon).frame(width: 20, height: 20)
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
    }
}

/// Today's session: how long it takes and how many exercises.
private struct SessionCard: View {
    let program: Program
    let onStart: () -> Void
    @Environment(\.workoutTransition) private var workoutTransition

    /// The exercises stay folded to keep the page light; tapping the card unfolds them in place.
    @State private var expanded = false

    var body: some View {
        SummaryCard(title: Text("Séance du jour"), systemImage: nil, color: .accentColor, sectionHeader: true) {
            // The chevron tells the card unfolds, like an expandable row in iOS.
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .accessibilityHidden(true)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    BigValue(value: "\(program.estimatedMinutes)", unit: "min")
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

                Button(action: onStart) {
                    Label("Commencer", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                // A soft glow lifts the main action off the card.
                .shadow(color: Color.accentColor.opacity(0.45), radius: 14, y: 6)
                .modifier(WorkoutSource(namespace: workoutTransition))
            }
        }
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
}

/// Marks the Commencer button as the start of the zoom into the session.
private struct WorkoutSource: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: WorkoutTransition.sourceID, in: namespace)
        } else {
            content
        }
    }
}

/// An exercise's pictogram in a tinted circle.
private struct ExerciseBadge: View {
    let exercise: PlannedExercise
    let size: Double

    var body: some View {
        Group {
            if let catalog = exercise.catalogExercise {
                ExerciseIcon(exercise: catalog).padding(size * 0.2)
            } else {
                Image(systemName: exercise.symbol).font(.system(size: size * 0.45))
            }
        }
        .foregroundStyle(.tint)
        .frame(width: size, height: size)
        .background(Color(.tertiarySystemGroupedBackground), in: .circle)
    }
}



/// The patient's initials, or a person symbol, as Health's profile button:
/// a soft gradient disc inside a Liquid Glass ring.
private struct ProfileBadge: View {
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
    /// The days of this week, with whether a session was done that day.
    let days: [(date: Date, done: Bool)]

    init(sessions: [Session], sessionsPerWeek: Int, now: Date = .now) {
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
    /// "3 séries de 10 répétitions" or "3 × 30 s".
    var prescriptionDetail: LocalizedStringKey {
        if let holdSeconds { return "\(sets) × \(holdSeconds) s" }
        return "\(sets) séries de \(reps) répétitions"
    }

    var trackingSymbol: String {
        if catalogExercise != nil { return "camera.viewfinder" }
        return holdSeconds == nil ? "hand.tap" : "timer"
    }

    var trackingLabel: Text {
        if catalogExercise != nil { return Text("Caméra") }
        return holdSeconds == nil ? Text("Manuel") : Text("Minuteur")
    }
}

extension Program {
    /// Rough duration: about 4 s per repetition or the hold time, plus 30 s between sets.
    var estimatedMinutes: Int {
        let seconds = exercises.reduce(0) { total, exercise in
            let perSet = exercise.holdSeconds ?? exercise.reps * 4
            return total + exercise.sets * (perSet + 30)
        }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }
}
