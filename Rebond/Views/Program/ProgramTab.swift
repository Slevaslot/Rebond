import SwiftData
import SwiftUI

/// "Exercices": the week, the programs (exercises ticked, with their days), then "Mes exercices" and creating one.
/// The day's session gathers the programs planned that day.
struct ProgramTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query(sort: \LibraryExercise.createdAt) private var library: [LibraryExercise]
    @State private var showingSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Exercices")
                // Same top bar as the Accueil page: the large title and its controls on the same line, in the page.
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: Program.self) { program in
                    ProgramDetailView(program: program, color: ProgramPalette.color(of: program, in: programs))
                }
                .navigationDestination(for: LibraryExercise.self) { exercise in
                    LibraryExerciseView(exercise: exercise)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                // Back on this tab after visiting another one: the lists, not the page left open.
                .onChange(of: router.tab) {
                    if router.tab != .program { path = NavigationPath() }
                }
        }
    }

    private var header: some View {
        PageHeader("Exercices") {
            ProfileButton { showingSettings = true }
        }
    }

    private var content: some View {
        List {
            // No top margin: the header sits exactly where it does on the Accueil page.
            header.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 7, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if !programs.isEmpty {
                WeekPlanCard(programs: programs).pageRow()
            }

            // The programs first, to manage them without scrolling past every exercise.
            sectionTitle("Mes programmes")
            ForEach(programs) { program in
                Button { path.append(program) } label: {
                    ProgramRow(program: program, color: ProgramPalette.color(of: program, in: programs))
                }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        // No destructive role: with it, the list removes the row itself, then once more when the
                        // program leaves the query, and the next row (the other program) vanished from the screen.
                        Button("Supprimer", systemImage: "trash") {
                            withAnimation { context.delete(program) }
                        }
                        .tint(.red)
                    }
                    .pageRow()
            }
            // A whole program at once: typed by hand, or the physiotherapist's message or sheet.
            Menu {
                OtherProgramWays()
            } label: {
                Text("Créer un programme")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .center)
            .pageRow()

            // Then the exercises: one is created on its own, then added to a program.
            sectionTitle("Mes exercices")
            AddExerciseMenu(label: {
                Text("Créer un exercice")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }, offersPhysiotherapist: false)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            // In a list, a menu keeps its label's width: stretch the menu itself, its text centered.
            .frame(maxWidth: .infinity, alignment: .center)
            .pageRow()

            if library.isEmpty {
                Text("Filmez l'exercice bien fait, ou choisissez un exercice Rebond.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .pageRow()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(library.enumerated()), id: \.element.id) { index, exercise in
                        if index > 0 { Divider().padding(.leading, 74) }
                        Button { path.append(exercise) } label: {
                            LibraryExerciseRow(exercise: exercise)
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
                .pageRow()
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(alignment: .top) {
            // Tinted top, fading into the page, like the Accueil page.
            PageTint(color: Color.accentColor, opacity: 0.45)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .pageRow()
    }
}

/// A program in the list: its name, its days, how many exercises.
private struct ProgramRow: View {
    let program: Program
    /// Its color in the week.
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(program.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(program.days.isEmpty
                     ? String.inflected("Sans jour · ^[\(program.exercises.count) exercice](inflect: true)")
                     : "\(Self.shortDays(program.days)) · \(String.inflected("^[\(program.exercises.count) exercice](inflect: true)"))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    /// "L M V": the days, Monday first.
    static func shortDays(_ days: [Int]) -> String {
        ProgramSchedule.mondayFirst.filter(days.contains)
            .map { Calendar.current.veryShortWeekdaySymbols[$0 - 1] }
            .joined(separator: " ")
    }
}

extension View {
    /// A list row that looks like the rest of the page: no separator, no background, the page's margins.
    func pageRow() -> some View {
        listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// One color per program, in the order they were added, to tell them apart in the week. Always with its name:
/// the color never carries the information alone.
enum ProgramPalette {
    static let colors: [Color] = [.accentColor, .orange, .purple, .green, .pink, .teal]

    static func color(of program: Program, in programs: [Program]) -> Color {
        let index = programs.firstIndex { $0.persistentModelID == program.persistentModelID } ?? 0
        return colors[index % colors.count]
    }
}

/// The seven days, Monday first, with the programs of each day: what to do when, at a glance.
private struct WeekPlanCard: View {
    let programs: [Program]

    var body: some View {
        SummaryCard(title: Text("Votre semaine"), systemImage: "calendar", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(ProgramSchedule.mondayFirst, id: \.self) { weekday in
                        DayColumn(weekday: weekday, programs: programs)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private struct DayColumn: View {
    let weekday: Int
    let programs: [Program]

    private var isToday: Bool { Calendar.current.component(.weekday, from: .now) == weekday }

    private var planned: [Program] { programs.active.filter { $0.days.contains(weekday) } }

    var body: some View {
        VStack(spacing: 8) {
            Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                .font(.caption.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            ZStack {
                if planned.isEmpty {
                    Circle().fill(Color(.systemGray4)).frame(width: 6, height: 6)
                } else {
                    // One color per program planned that day, side by side in the same disc.
                    HStack(spacing: 0) {
                        ForEach(planned) { program in
                            ProgramPalette.color(of: program, in: programs)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .clipShape(.circle)
                }
            }
            .frame(width: 26, height: 26)
            // Today: a ring around the day, the same whether something is planned or not.
            .padding(3)
            .overlay {
                if isToday { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Calendar.current.weekdaySymbols[weekday - 1]))
        .accessibilityValue(planned.isEmpty
            ? Text("Repos")
            : Text(planned.map(\.title).formatted(.list(type: .and))))
    }
}

/// A program as a card: its name, its days, its exercises' pictograms, how long it takes.
private struct ProgramCard: View {
    let program: Program
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // Room for the check drawn over the card.
                Color.clear.frame(width: 26, height: 1)
                Text(program.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if program.isActive, program.isScheduled(on: .now) {
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
            Text(ProgramSchedule.describe(program.days).capitalizedFirst)
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
        // A program not followed stays readable but steps back.
        .opacity(program.isActive ? 1 : 0.55)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(program.title))
        .accessibilityValue(Text("\(ProgramSchedule.describe(program.days)), ^[\(program.exercises.count) exercice](inflect: true), \(program.estimatedMinutes) minutes"))
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

/// The three ways to add a séance, on an equal footing: the physiotherapist's videos, their sheet or message,
/// or exercises picked in the list. All lead to the same "Ma séance" screen.
struct AddSessionChoices: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Section("Vidéos de mon kiné") {
            Button("Choisir mes vidéos", systemImage: "photo.on.rectangle") { router.addProgram(from: .videos) }
            Button("Filmer", systemImage: "video") { router.addProgram(from: .film) }
        }
        Section("Feuille ou message du kiné") {
            Button("Scanner la feuille", systemImage: "doc.viewfinder") { router.addProgram(from: .scan) }
            Button("Photo de la feuille", systemImage: "photo") { router.addProgram(from: .photo) }
            Button("Coller le message", systemImage: "text.bubble") { router.addProgram(from: .message) }
        }
        Section("Exercices") {
            Button("Choisir mes exercices", systemImage: "list.bullet") { router.addProgram(from: .manual) }
        }
    }
}

/// Adding a session, in full: a large button, with the same choices as the + of the header.
private struct AddSessionButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        // The system's bubble, opening from the button: nothing darkens the page.
        Menu {
            AddSessionChoices()
        } label: {
            Text("Ajouter une séance")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        // In a list, a menu keeps its label's width: stretch the menu itself, its text centered.
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// The ways to add a séance, in a Liquid Glass button.
struct AddProgramMenu: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            AddSessionChoices()
        } label: {
            HeaderIcon(systemImage: "plus")
        }
        .accessibilityLabel("Nouvelle séance")
    }
}

/// The ways to make a whole program at once, in a menu: composed from "Mes exercices", the physiotherapist's message,
/// their sheet (scanned or photographed).
struct OtherProgramWays: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            // One page at a time: tick the exercises of "Mes exercices", then set the program.
            Button("Composer moi-même", systemImage: "square.and.pencil") { router.newProgram() }
            Button("Coller le message", systemImage: "text.bubble") { router.addProgram(from: .message) }
            Button("Scanner la feuille", systemImage: "doc.viewfinder") { router.addProgram(from: .scan) }
            Button("Photo de la feuille", systemImage: "photo") { router.addProgram(from: .photo) }
        }
    }
}

/// No program yet, in the same cards as the other pages. Everything starts with an exercise (one clear next step,
/// HIG *Writing*): filmed done right (the model movement Rebond learns from); Rebond's are already in "Mes exercices".
/// Once saved, it is added to a program. "Créer un programme" makes a whole program at once (composed from
/// "Mes exercices", or the physiotherapist's message or sheet).
/// Below, an exercise to try right away, outside any program. The page's own header stays on top.
struct NoProgramView<Header: View>: View {
    @ViewBuilder let header: Header
    @Environment(AppRouter.self) private var router
    @Query(sort: \LibraryExercise.createdAt) private var library: [LibraryExercise]
    #if DEBUG
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                SummaryCard(title: Text("Pour commencer"), systemImage: "figure.mixed.cardio", color: .accentColor) {
                    EmptyView()
                } content: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Créez vos exercices, puis votre programme.")
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 8) {
                            ProgramStep(number: 1, text: "Filmez l'exercice bien fait : c'est le mouvement modèle. Les exercices Rebond sont déjà là.")
                            ProgramStep(number: 2, text: "Créez un programme avec vos exercices et vos jours.")
                        }
                        AddExerciseMenu(label: {
                            Text("Créer mon exercice")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }, offersPhysiotherapist: false)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .padding(.top, 4)

                        Menu {
                            OtherProgramWays()
                        } label: {
                            Text("Créer un programme")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        #if DEBUG
                        Button("Charger le programme de démo", systemImage: "sparkles") { DemoData.load(into: context) }
                            .font(.footnote)
                        #endif
                    }
                }

                FreeExerciseCard()

                MedicalDisclaimer()
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

/// One numbered step: "1  Filmez l'exercice bien fait…".
private struct ProgramStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A group of ways in the card: "Vidéos de mon kiné".
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

/// A way to add the program, as a row of the card.
private struct AddRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                Text(title)
                    .font(.body)
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
