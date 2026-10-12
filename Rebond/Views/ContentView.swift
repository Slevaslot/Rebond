import PhotosUI
import SwiftData
import SwiftUI

/// Home: the program and this week's progress, or how to get a program.
struct ContentView: View {
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Environment(\.modelContext) private var context

    @State private var showingCamera = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var sheetPhoto: UIImage?
    @State private var editing: EditableProgram?

    var body: some View {
        NavigationStack {
            Group {
                if let program = programs.first {
                    programHome(program)
                } else {
                    welcome
                }
            }
            .navigationTitle("Rebond")
            .navigationDestination(item: $sheetPhoto) { photo in
                SheetReadingView(photo: photo) { save($0) }
            }
            .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let editing {
                    ProgramEditorView(program: editing) { save($0) }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { sheetPhoto = $0 }
                    .ignoresSafeArea()
            }
            .onChange(of: pickedItem) {
                guard let pickedItem else { return }
                Task {
                    if let data = try? await pickedItem.loadTransferable(type: Data.self) {
                        sheetPhoto = UIImage(data: data)
                    }
                    self.pickedItem = nil
                }
            }
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(spacing: 24) {
                ContentUnavailableView(
                    "Votre programme",
                    systemImage: "doc.text.viewfinder",
                    description: Text("Photographiez la feuille d'exercices de votre kiné : Rebond la transforme en programme, sur votre iPhone.")
                )
                VStack(spacing: 12) {
                    if CameraPicker.isAvailable {
                        Button("Photographier ma feuille", systemImage: "camera") { showingCamera = true }
                            .buttonStyle(.borderedProminent)
                    }
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        Label("Choisir une photo", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    Button("Saisir le programme", systemImage: "square.and.pencil") { editing = EditableProgram() }
                        .buttonStyle(.bordered)
                    Button("Essayer avec un programme de démo") { DemoData.load(into: context) }
                        .font(.footnote)
                }
                .controlSize(.large)
                disclaimer
            }
            .padding()
        }
    }

    private func programHome(_ program: Program) -> some View {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let doneThisWeek = sessions.filter { $0.date > weekStart }.count

        return List {
            Section {
                NavigationLink {
                    WorkoutView(program: program)
                } label: {
                    Label("Commencer la séance", systemImage: "figure.strengthtraining.functional")
                        .font(.headline)
                }
                Gauge(value: Double(min(doneThisWeek, program.sessionsPerWeek)), in: 0...Double(program.sessionsPerWeek)) {
                    Text("\(doneThisWeek) séances sur \(program.sessionsPerWeek) cette semaine")
                }
            }

            Section("Mon programme") {
                ForEach(program.orderedExercises) { exercise in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exercise.name)
                            Text("\(exercise.sets) × \(exercise.reps)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if exercise.catalogExercise != nil {
                            Image(systemName: "camera.viewfinder")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Suivi par la caméra")
                        }
                    }
                }
                Button("Modifier le programme", systemImage: "pencil") { editing = EditableProgram(program) }
                Menu {
                    if CameraPicker.isAvailable {
                        Button("Photographier", systemImage: "camera") { showingCamera = true }
                    }
                    Button("Saisir à la main", systemImage: "square.and.pencil") { editing = EditableProgram() }
                } label: {
                    Label("Nouvelle feuille", systemImage: "doc.badge.plus")
                }
            }

            Section("Suivi") {
                NavigationLink {
                    ReportView(program: program)
                } label: {
                    Label("Rapport pour mon kiné", systemImage: "doc.richtext")
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("Historique", systemImage: "calendar")
                }
            }

            Section {
                disclaimer
            }
        }
    }

    private var disclaimer: some View {
        Text("Rebond ne remplace pas l'avis d'un professionnel de santé. Seul votre kiné décide de votre programme.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func save(_ program: EditableProgram) {
        Program.replaceAll(with: program, in: context)
        editing = nil
        sheetPhoto = nil
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Program.self, Session.self], inMemory: true)
}
