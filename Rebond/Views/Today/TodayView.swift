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
    @AppStorage(PainAlertCard.dismissedKey) private var dismissedPainAlert: Double = 0
    @State private var restoredAlert = 0
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let program = programs.first {
                    today(program)
                } else {
                    noProgram
                }
            }
            .navigationTitle("Séance")
            // Fitness-style top bar: the large title and the profile on the same line, in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Séance")
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
                PainAlertCard(sessions: sessions)

                SessionCard(program: program) { router.startWorkout() }

                WeekCard(week: week)
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
private struct SummaryCard<Content: View, Trailing: View>: View {
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
private struct BigValue: View {
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
                    .transition(.asymmetric(insertion: .push(from: .top).combined(with: .opacity), removal: .opacity))
                }

                Button(action: onStart) {
                    Label("Commencer", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
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

/// This week: sessions done against the goal, with a bar per day (today highlighted), like Health's step card.
private struct WeekCard: View {
    let week: WeekProgress

    var body: some View {
        SummaryCard(title: Text("Régularité"), systemImage: "checkmark.circle.fill", color: .mint) {
            Text("Cette semaine")
        } content: {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    BigValue(value: "\(week.done)", unit: "sur \(week.planned) séances")
                    if week.done >= week.planned {
                        Text("Objectif atteint, bravo !")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Chart(week.days, id: \.date) { day in
                    BarMark(
                        x: .value("Jour", day.date, unit: .day),
                        y: .value("Séances", day.done ? 1 : 0.06)
                    )
                    .foregroundStyle(day.done ? Color.mint : Color(.tertiaryLabel))
                    .clipShape(.rect(cornerRadius: 2))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...1)
                .frame(width: 130, height: 64)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Régularité cette semaine"))
        .accessibilityValue(Text(week.summary))
    }
}

/// After a painful session, a calm card with a yellow band, like Health's notifications. Dismissable.
private struct PainAlertCard: View {
    let sessions: [Session]
    static let dismissedKey = "dismissedPainAlert"
    @AppStorage(dismissedKey) private var dismissed: Double = 0

    private var painful: Session? {
        guard let last = sessions.first,
              last.pain >= WeeklyReport.highPain,
              last.date.timeIntervalSinceReferenceDate > dismissed,
              last.date > Date.now.addingTimeInterval(-7 * 86_400)
        else { return nil }
        return last
    }

    var body: some View {
        if let painful {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Douleur forte", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                    Spacer()
                    Text(painful.date, format: .dateTime.day().month())
                        .font(.subheadline.weight(.semibold))
                    Button("Masquer", systemImage: "xmark") {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            dismissed = painful.date.timeIntervalSinceReferenceDate
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
                .foregroundStyle(.black)
                .padding()
                .background(.yellow)
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "heart.text.square")
                        .font(.title)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Douleur de \(painful.pain) sur 10 à la dernière séance.")
                            .font(.headline)
                        Text("Si la douleur est forte ou inhabituelle, faites une pause et parlez-en à votre kiné.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 26))
        }
    }
}

/// The patient's initials, or a person symbol, as Health's profile button.
private struct ProfileBadge: View {
    let name: String

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Group {
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.headline)
            } else {
                Text(initials)
                    .font(.title3.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 50, height: 50)
        .background(Color.accentColor.gradient, in: .circle)
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
