import SwiftData
import SwiftUI

/// The patient's programs, laid out like the Accueil page: the week at a glance (which program on which day),
/// then one card per program. A card opens the program: its exercises, start it, change it, or do one exercise.
struct ProgramTab: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
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
            .navigationTitle("Programmes")
            // Same top bar as the Accueil page: the large title and its controls on the same line, in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Program.self) { program in
                ProgramDetailView(program: program, color: ProgramPalette.color(of: program, in: programs))
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Programmes")
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

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                WeekPlanCard(programs: programs)

                ForEach(programs) { program in
                    NavigationLink(value: program) {
                        ProgramCard(program: program, color: ProgramPalette.color(of: program, in: programs))
                    }
                    .buttonStyle(.plain)
                }

                Text("Seul votre kiné décide de votre programme. Ajoutez ici ce qu'il vous a prescrit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
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
                if programs.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(programs) { program in
                            Label {
                                Text(program.title).font(.subheadline)
                            } icon: {
                                Circle().fill(ProgramPalette.color(of: program, in: programs)).frame(width: 10, height: 10)
                            }
                        }
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

    private var planned: [Program] { programs.filter { $0.days.contains(weekday) } }

    var body: some View {
        VStack(spacing: 8) {
            Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                .font(.caption.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            VStack(spacing: 3) {
                if planned.isEmpty {
                    Circle().fill(Color(.systemGray4)).frame(width: 5, height: 5).frame(height: 22)
                } else {
                    ForEach(planned) { program in
                        Capsule()
                            .fill(ProgramPalette.color(of: program, in: programs))
                            .frame(width: 22, height: planned.count > 1 ? 10 : 22)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .background(isToday ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
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
                Circle().fill(color).frame(width: 10, height: 10)
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(program.title))
        .accessibilityValue(Text("\(ProgramSchedule.describe(program.days)), ^[\(program.exercises.count) exercice](inflect: true), \(program.estimatedMinutes) minutes"))
        .accessibilityHint(Text("Ouvre le programme"))
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
