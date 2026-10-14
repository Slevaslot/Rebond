import Charts
import SwiftData
import SwiftUI

/// The session to do, laid out like the Health app's Summary: a tinted header, large cards with a colored
/// category label, a big rounded value and a small chart, bold section titles. Liquid Glass stays in the
/// navigation layer (toolbar, tab bar, the floating start button).
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    @State private var showingSettings = false
    @State private var editing: EditableProgram?

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        ProfileBadge(name: patientName)
                    }
                    .accessibilityLabel("Réglages")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let editing {
                    ProgramEditorView(program: editing) { saved in
                        Program.replaceAll(with: saved, in: context)
                        self.editing = nil
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
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
                PainAlertCard(sessions: sessions)

                SessionCard(
                    program: program,
                    onEdit: { editing = EditableProgram(program) },
                    onScan: { router.addProgram(from: .scan) }
                )

                WeekCard(week: week)

                Text("Rebond ne remplace pas l'avis d'un professionnel de santé.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(alignment: .top) {
            // Tinted top, fading into the page, like Health's Summary.
            LinearGradient(colors: [Color.accentColor.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaBar(edge: .bottom) {
            SlideToStart { router.startWorkout() }
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
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
    let onEdit: () -> Void
    let onScan: () -> Void

    /// The program stays folded to keep the page light; "Plus de détails" unfolds it in place, like Health.
    @State private var expanded = false

    var body: some View {
        SummaryCard(title: Text("Séance du jour"), systemImage: nil, color: .accentColor, sectionHeader: true) {
            Text("\(program.exercises.count) exercices")
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

                    HStack {
                        Button("Modifier", systemImage: "pencil", action: onEdit)
                        Button("Nouvelle feuille", systemImage: "doc.viewfinder", action: onScan)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .transition(.opacity)
                }

                // Same button as Health's "Plus de détails": a tinted capsule with bold accent text.
                Button(expanded ? "Moins de détails" : "Plus de détails") {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { expanded.toggle() }
                }
                .font(.title3.weight(.semibold))
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(.accentColor)
                .contentTransition(.interpolate)
            }
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
    @AppStorage("dismissedPainAlert") private var dismissed: Double = 0

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
                        dismissed = painful.date.timeIntervalSinceReferenceDate
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
                    .font(.headline.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
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

/// "Glisser pour commencer": a Liquid Glass track with a glass thumb dragged from left to right.
/// Released before the end, the thumb springs back; at the end, the session starts.
/// VoiceOver sees a plain button, since dragging isn't practical with it.
private struct SlideToStart: View {
    let onStart: () -> Void

    @State private var offset: Double = 0
    @State private var started = 0
    @State private var triggered = false
    private let thumb: Double = 60
    private let inset: Double = 5

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - thumb - inset * 2)
            let progress = min(1, offset / travel)
            ZStack(alignment: .leading) {
                Text("Glisser pour commencer")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .shimmer()
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumb * 0.6)
                    .opacity(1 - progress * 1.4)

                Image(systemName: progress > 0.95 ? "checkmark" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: thumb, height: thumb)
                    // Plain glass, like the thumb of an incoming call's slider.
                    .glassEffect(.regular.interactive(), in: .circle)
                    .offset(x: inset + offset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !triggered else { return }
                                offset = min(max(0, value.translation.width), travel)
                                // Reaching the end is enough: no need to wait for the finger to lift.
                                if offset >= travel * 0.95 { start(travel: travel) }
                            }
                            .onEnded { _ in
                                guard !triggered else { return }
                                if offset >= travel * 0.85 {
                                    start(travel: travel)
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { offset = 0 }
                                }
                            }
                    )
            }
            .frame(height: thumb + inset * 2)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .frame(height: thumb + inset * 2)
        .sensoryFeedback(.success, trigger: started)
        .accessibilityRepresentation {
            Button("Commencer la séance", action: onStart)
        }
    }

    private func start(travel: Double) {
        triggered = true
        withAnimation(.spring(duration: 0.25)) { offset = travel }
        started += 1
        onStart()
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            offset = 0
            triggered = false
        }
    }
}

/// A light sweeping across the text, like the "slide to answer" hint of an incoming call.
private struct Shimmer: ViewModifier {
    @State private var phase: Double = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    // The light moves inside a fixed frame, and only the letters show it.
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, .white.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 70)
                            .offset(x: (phase + 1) / 2 * (geometry.size.width + 70) - 70)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

private extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
