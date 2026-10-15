import SwiftData
import SwiftUI

/// "Mon programme": everything the physiotherapist gave, laid out like the Accueil page. The week first, where
/// each day gets its séance (tap a day to change it), then the séances, then one way to add more.
/// A séance card opens the séance: its exercises, start it, change it.
struct ProgramTab: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @State private var showingSettings = false
    @State private var showingFreeExercise = false
    @State private var adding = false
    /// The way chosen in the "Ajouter" sheet, opened once the sheet is gone.
    @State private var pendingSource: AppRouter.ImportSource?
    @State private var path: [Program] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if programs.isEmpty {
                    NoProgramView { header }
                } else {
                    content
                }
            }
            .navigationTitle("Mon programme")
            // Same top bar as the Accueil page: the large title and its controls on the same line, in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Program.self) { program in
                ProgramDetailView(program: program, color: ProgramPalette.color(of: program, in: programs))
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingFreeExercise) {
                FreeExercisePicker()
            }
            .sheet(isPresented: $adding, onDismiss: {
                if let source = pendingSource { router.addProgram(from: source) }
                pendingSource = nil
            }) {
                AddFromPhysioSheet { source in
                    pendingSource = source
                    adding = false
                }
            }
            // Back on this tab after visiting another one: the program, not the page left open.
            .onChange(of: router.tab) {
                if router.tab != .program { path = [] }
            }
        }
    }

    private var header: some View {
        PageHeader("Mon programme") {
            Menu {
                Button("Faire un exercice seul", systemImage: "figure.mixed.cardio") { showingFreeExercise = true }
            } label: {
                HeaderIcon(systemImage: "ellipsis")
            }
            .accessibilityLabel("Plus")
            ProfileButton { showingSettings = true }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                WeekCard(programs: programs)

                Text("Séances")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                ForEach(programs) { program in
                    Button {
                        path.append(program)
                    } label: {
                        ProgramCard(program: program, color: ProgramPalette.color(of: program, in: programs))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    adding = true
                } label: {
                    Label("Ajouter ce que m'a donné mon kiné", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .padding(.top, 6)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(alignment: .top) {
            // Tinted top, fading into the page, like the Accueil page.
            PageTint(color: Color.accentColor, opacity: 0.45)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// One color per séance, in the order they were added, to tell them apart in the week. Always with its name:
/// the color never carries the information alone.
enum ProgramPalette {
    static let colors: [Color] = [.accentColor, .orange, .purple, .green, .pink, .teal]

    static func color(of program: Program, in programs: [Program]) -> Color {
        let index = programs.firstIndex { $0.persistentModelID == program.persistentModelID } ?? 0
        return colors[index % colors.count]
    }
}

/// The seven days, Monday first, each with its séance or a rest. Tapping a day chooses its séance: the week
/// is where the program is planned.
private struct WeekCard: View {
    let programs: [Program]

    var body: some View {
        SummaryCard(title: Text("Ma semaine"), systemImage: "calendar", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(ProgramSchedule.mondayFirst, id: \.self) { weekday in
                        DayButton(weekday: weekday, programs: programs)
                            .frame(maxWidth: .infinity)
                    }
                }
                Text("Touchez un jour pour choisir sa séance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A day of the week: its letter, its séance's color and initial, and a menu to change it.
private struct DayButton: View {
    let weekday: Int
    let programs: [Program]
    @Environment(\.modelContext) private var context

    private var isToday: Bool { Calendar.current.component(.weekday, from: .now) == weekday }
    private var planned: Program? { programs.first { $0.days.contains(weekday) } }

    var body: some View {
        Menu {
            Section(Calendar.current.weekdaySymbols[weekday - 1].capitalizedFirst) {
                ForEach(programs) { program in
                    Button {
                        if planned?.persistentModelID != program.persistentModelID { program.toggle(weekday, in: context) }
                    } label: {
                        if planned?.persistentModelID == program.persistentModelID {
                            Label(program.title, systemImage: "checkmark")
                        } else {
                            Text(program.title)
                        }
                    }
                }
                Button {
                    planned?.toggle(weekday, in: context)
                } label: {
                    if planned == nil {
                        Label("Repos", systemImage: "checkmark")
                    } else {
                        Text("Repos")
                    }
                }
            }
        } label: {
            VStack(spacing: 8) {
                Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                    .font(.caption.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                ZStack {
                    if let planned {
                        Circle().fill(ProgramPalette.color(of: planned, in: programs))
                        Text(planned.title.prefix(1).uppercased())
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    } else {
                        Circle().fill(Color(.tertiarySystemFill))
                        Image(systemName: "moon.zzz.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                // Today: a ring around the day, the same whether something is planned or not.
                .padding(3)
                .overlay {
                    if isToday { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: planned?.persistentModelID)
        .accessibilityLabel(Text(Calendar.current.weekdaySymbols[weekday - 1]))
        .accessibilityValue(planned.map { Text($0.title) } ?? Text("Repos"))
        .accessibilityHint(Text("Choisir la séance de ce jour"))
    }
}

/// A séance as a card: its color and name, its days, its exercises' pictograms, how long it takes.
private struct ProgramCard: View {
    let program: Program
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(program.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if program.isScheduled(on: .now) {
                    Text("Aujourd'hui")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.18), in: .capsule)
                        .foregroundStyle(color)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(program.days.isEmpty ? String(localized: "Aucun jour") : ProgramSchedule.describe(program.days).capitalizedFirst)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .center) {
                HStack(spacing: -6) {
                    ForEach(program.orderedExercises.prefix(5)) { exercise in
                        ExerciseBadge(exercise: exercise, size: 36)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    }
                }
                Spacer()
                Text("^[\(program.exercises.count) exercice](inflect: true) · \(program.estimatedMinutes) min")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(program.title))
        .accessibilityValue(Text("\(program.days.isEmpty ? String(localized: "Aucun jour") : ProgramSchedule.describe(program.days)), ^[\(program.exercises.count) exercice](inflect: true), \(program.estimatedMinutes) minutes"))
        .accessibilityHint(Text("Ouvre la séance"))
    }
}

extension String {
    /// "Lundi et jeudi" from "lundi et jeudi".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// "Suivi caméra", "Comptage manuel" or "Minuteur": a symbol and a word in a capsule, never a color alone.
struct TrackingBadge: View {
    let exercise: PlannedExercise

    var body: some View {
        let followed = exercise.catalogExercise != nil
        Label { exercise.trackingLabel } icon: { Image(systemName: exercise.trackingSymbol) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(followed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(followed ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: .capsule)
    }
}

// MARK: - Adding

/// The ways to add what the physiotherapist gave, in one place: filmed at their office, photos or videos
/// already on the iPhone, the sheet scanned, their message; the list of exercises comes last.
/// All lead to the same "Ma séance" screen.
struct AddChoices: View {
    let onChoose: (AppRouter.ImportSource) -> Void
    #if DEBUG
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AddGroup(title: "Chez mon kiné")
            AddRow(title: "Filmer mes exercices", detail: "L'iPhone apprend chaque mouvement", symbol: "video") { onChoose(.film) }
            AddGroup(title: "Ce que mon kiné m'a donné")
            AddRow(title: "Photos ou vidéos", detail: "La feuille, ou les vidéos des exercices", symbol: "photo.on.rectangle") {
                onChoose(.library)
            }
            Divider().padding(.leading, 44)
            AddRow(title: "Scanner la feuille", symbol: "doc.viewfinder") { onChoose(.scan) }
            Divider().padding(.leading, 44)
            AddRow(title: "Coller son message", symbol: "text.bubble") { onChoose(.message) }
            AddGroup(title: "Sinon")
            AddRow(title: "Choisir dans la liste", symbol: "list.bullet") { onChoose(.manual) }
            #if DEBUG
            Divider().padding(.leading, 44)
            AddRow(title: "Programme de démo", symbol: "sparkles") { DemoData.load(into: context) }
            #endif
        }
    }
}

/// "Ajouter ce que m'a donné mon kiné", as a sheet over the program.
private struct AddFromPhysioSheet: View {
    let onChoose: (AppRouter.ImportSource) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                AddChoices(onChoose: onChoose)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ajouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// No program yet, in the same cards as the other pages: how to add the physiotherapist's program,
/// and one exercise to do right away. The page's own header stays on top.
struct NoProgramView<Header: View>: View {
    @ViewBuilder let header: Header
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                SummaryCard(title: Text("Mon programme"), systemImage: "list.bullet.clipboard", color: .accentColor) {
                    EmptyView()
                } content: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comment votre kiné vous a-t-il donné vos exercices ?")
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 6)
                        AddChoices { router.addProgram(from: $0) }
                    }
                }

                FreeExerciseCard()
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(alignment: .top) {
            PageTint(color: Color.accentColor, opacity: 0.45)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// A group of ways in the card: "Chez mon kiné".
private struct AddGroup: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }
}

/// A way to add, as a row of the card.
private struct AddRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
