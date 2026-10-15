import AppIntents
import CoreSpotlight
import SwiftData

/// The data store of the app, shared with the App Intents so they find the programs.
enum AppData {
    static let schema = Schema([Program.self, Session.self, TrackedPatient.self, ProgramTemplate.self, LibraryExercise.self])

    static let container: ModelContainer = {
        if let container = try? ModelContainer(for: schema) { return container }
        // A store SwiftData can't migrate (a build installed before a model change) must not stop the app
        // from launching: it is set aside, not deleted, and the app starts from an empty store.
        let store = ModelConfiguration().url
        let setAside = store.deletingLastPathComponent()
            .appending(path: "unreadable-\(Int(Date.now.timeIntervalSince1970))", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: setAside, withIntermediateDirectories: true)
        for suffix in ["", "-shm", "-wal"] {
            let file = URL(filePath: store.path(percentEncoded: false) + suffix)
            try? FileManager.default.moveItem(at: file, to: setAside.appending(path: file.lastPathComponent))
        }
        if let container = try? ModelContainer(for: schema) { return container }
        // Last resort: nothing is kept after the app quits, but the app works.
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }()
}

// MARK: - Séances

/// A program ("séance" for the patient), found in Spotlight and Shortcuts: opening it starts it.
struct SeanceEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Séance"
    static let defaultQuery = SeanceQuery()

    /// The program's creation date: stable, and unique enough for one patient's programs.
    let id: String
    let title: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(detail)", image: .init(systemName: "figure.mixed.cardio"))
    }

    init(_ program: Program) {
        id = Self.id(of: program)
        title = program.title
        detail = String(localized: "\(program.exercises.count) exercices · \(program.estimatedMinutes) min")
    }

    static func id(of program: Program) -> String {
        String(program.createdAt.timeIntervalSinceReferenceDate)
    }

    @MainActor
    static func program(id: String) -> Program? {
        let programs = (try? AppData.container.mainContext.fetch(FetchDescriptor<Program>())) ?? []
        return programs.first { Self.id(of: $0) == id }
    }

    /// Indexes the patient's programs in Spotlight, replacing the previous ones.
    static func index(_ programs: [Program]) async {
        let entities = programs.map(SeanceEntity.init)
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: SeanceEntity.self)
        try? await index.indexAppEntities(entities)
        RebondShortcuts.updateAppShortcutParameters()
    }
}

struct SeanceQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SeanceEntity] {
        identifiers.compactMap { SeanceEntity.program(id: $0).map(SeanceEntity.init) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SeanceEntity] {
        let programs = (try? AppData.container.mainContext.fetch(FetchDescriptor<Program>())) ?? []
        return programs.map(SeanceEntity.init)
    }
}

/// Opens Rebond on a program's session, ready to start: from Spotlight ("genou") or Siri.
struct StartSeanceIntent: OpenIntent {
    static let title: LocalizedStringResource = "Commencer une séance"
    static let description = IntentDescription("Ouvre Rebond et lance la séance choisie.")

    @Parameter(title: "Séance")
    var target: SeanceEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if let program = SeanceEntity.program(id: target.id) {
            AppRouter.shared.startWorkout(program)
        }
        return .result()
    }
}

// MARK: - Exercices

/// An exercise the camera follows, found in Spotlight ("squat"): opening it starts one set of 10.
struct ExerciseEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Exercice"
    static let defaultQuery = ExerciseQuery()

    let id: String
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Suivi par la caméra", image: .init(systemName: symbol))
    }

    init(_ exercise: CatalogExercise) {
        id = exercise.id
        name = String(localized: exercise.name)
        symbol = exercise.symbol
    }

    static var all: [ExerciseEntity] { CatalogExercise.all.map(ExerciseEntity.init) }

    static func index() async {
        try? await CSSearchableIndex.default().indexAppEntities(all)
    }
}

struct ExerciseQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ExerciseEntity] {
        ExerciseEntity.all.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ExerciseEntity] {
        ExerciseEntity.all
    }
}

struct StartExerciseIntent: OpenIntent {
    static let title: LocalizedStringResource = "Faire un exercice"
    static let description = IntentDescription("Ouvre Rebond et lance une série de l'exercice, suivie par la caméra.")

    @Parameter(title: "Exercice")
    var target: ExerciseEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let exercise = CatalogExercise.all.first(where: { $0.id == target.id }) else { return .result() }
        AppRouter.shared.startExercise(WorkoutExercise(name: String(localized: exercise.name), catalogID: exercise.id,
                                                       mode: .camera(catalogID: exercise.id), sets: 1, reps: 10))
        return .result()
    }
}
