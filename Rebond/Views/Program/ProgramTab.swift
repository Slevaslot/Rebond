import SwiftData
import SwiftUI

/// The patient's programs, laid out like the Accueil page: the week at a glance (which program on which day),
/// then one card per program. A card opens the program: its exercises, start it, change it, or do one exercise.
struct ProgramTab: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Environment(\.modelContext) private var context
    @State private var showingSettings = false
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
            .navigationTitle("Exercices")
            // Same top bar as the Accueil page: the large title and its controls on the same line, in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Program.self) { program in
                ProgramDetailView(program: program, color: ProgramPalette.color(of: program, in: programs))
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            // Back on this tab after visiting another one: the list of programs, not the page left open.
            .onChange(of: router.tab) {
                if router.tab != .program { path = [] }
            }
        }
    }

    private var header: some View {
        PageHeader("Exercices") {
            ProfileButton { showingSettings = true }
        }
    }

    /// A group of program cards. The circle on each card selects it: followed programs make the day's session.
    /// Swiping a card to the right follows it or not.
    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ list: [Program], empty: LocalizedStringKey?) -> some View {
        Text(title)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .pageRow()
        if list.isEmpty, let empty {
            Text(empty)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .pageRow()
        }
        ForEach(list) { program in
            let color = ProgramPalette.color(of: program, in: programs)
            Button {
                path.append(program)
            } label: {
                ProgramCard(program: program, color: color)
            }
            .buttonStyle(.plain)
            // The check sits in the card, in front of the name: tapping it only selects.
            .overlay(alignment: .topLeading) {
                Button {
                    withAnimation(.snappy) { program.isActive.toggle() }
                } label: {
                    Image(systemName: program.isActive ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(program.isActive ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.top, 4)
                .accessibilityLabel(Text(program.isActive ? "Ne plus suivre \(program.title)" : "Suivre \(program.title)"))
                .sensoryFeedback(.selection, trigger: program.isActive)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(program.isActive ? "Ne plus suivre" : "Suivre",
                       systemImage: program.isActive ? "checkmark.circle.badge.xmark" : "checkmark.circle") {
                    withAnimation(.snappy) { program.isActive.toggle() }
                }
                .tint(program.isActive ? .gray : color)
            }
            .pageRow()
        }
    }

    private var content: some View {
        // A list rather than a scroll view, for the system's swipe actions; it keeps the look of the cards.
        List {
            // No top margin: the header sits exactly where it does on the Accueil page.
            header.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 7, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            WeekPlanCard(programs: programs).pageRow()

            AddSessionButton().pageRow()

            FreeExerciseCard().pageRow()

            if programs.active.isEmpty {
                section("Vos séances", programs, empty: nil)
            } else {
                section("Séances suivies", programs.active, empty: nil)
                let others = programs.filter { !$0.isActive }
                if !others.isEmpty {
                    section("Autres séances", others, empty: nil)
                }
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

/// Adding a session, in full: a large button, with the same four ways as the + of the header.
private struct AddSessionButton: View {
    @Environment(AppRouter.self) private var router
    @State private var choosing = false

    var body: some View {
        // A plain button, centered like the others; the ways to add it come up from the bottom.
        Button {
            choosing = true
        } label: {
            Text("Ajouter une séance")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .confirmationDialog("Ajouter une séance", isPresented: $choosing) {
            Button("Coller le message du kiné") { router.addProgram(from: .message) }
            Button("Scanner sa feuille") { router.addProgram(from: .scan) }
            Button("Choisir une photo") { router.addProgram(from: .photo) }
            Button("Saisir à la main") { router.addProgram(from: .manual) }
            Button("Annuler", role: .cancel) {}
        }
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
            HeaderIcon(systemImage: "plus")
        }
        .accessibilityLabel("Nouvelle séance")
    }
}

/// No program yet, in the same cards as the other pages: how to add the physiotherapist's program,
/// and one exercise to do right away. The page's own header stays on top.
struct NoProgramView<Header: View>: View {
    @ViewBuilder let header: Header
    @Environment(AppRouter.self) private var router
    #if DEBUG
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                SummaryCard(title: Text("Votre programme"), systemImage: "stethoscope", color: .accentColor) {
                    EmptyView()
                } content: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ajoutez les exercices donnés par votre kiné.")
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                        Button {
                            router.addProgram(from: .message)
                        } label: {
                            Label("Coller son message", systemImage: "text.bubble")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .padding(.bottom, 6)
                        AddRow(title: "Scanner sa feuille", symbol: "doc.viewfinder") { router.addProgram(from: .scan) }
                        Divider().padding(.leading, 44)
                        AddRow(title: "Choisir une photo", symbol: "photo") { router.addProgram(from: .photo) }
                        Divider().padding(.leading, 44)
                        AddRow(title: "Saisir à la main", symbol: "square.and.pencil") { router.addProgram(from: .manual) }
                        #if DEBUG
                        Divider().padding(.leading, 44)
                        AddRow(title: "Programme de démo", symbol: "sparkles") { DemoData.load(into: context) }
                        #endif
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
