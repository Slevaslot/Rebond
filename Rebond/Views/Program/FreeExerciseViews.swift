import SwiftData
import SwiftUI

/// One exercise on its own, outside any program: pick it in "Mes exercices", choose how many, start.
struct FreeExerciseCard: View {
    var body: some View {
        SummaryCard(title: Text("Essayer un exercice"), systemImage: "figure.mixed.cardio", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: -6) {
                    ForEach(CatalogExercise.all.prefix(6)) { exercise in
                        Image(systemName: exercise.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(.tint)
                            .frame(width: 38, height: 38)
                            .background(Color(.tertiarySystemGroupedBackground), in: .circle)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                // Pushed, not in a sheet: the exercise's page starts the session over the whole screen.
                NavigationLink {
                    FreeExerciseList()
                } label: {
                    Text("Choisir un exercice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
    }
}

/// "Mes exercices", as in the Exercices tab and "Composer moi-même": filmed, Rebond's, then without the camera.
/// An exercise opens its page, which does it now (how many, which side) or adds it to a program.
private struct FreeExerciseList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryExercise.createdAt) private var library: [LibraryExercise]
    @State private var addingWithoutCamera = false

    var body: some View {
        List {
            ForEach(LibraryExercise.grouped(library, keepingWithoutCamera: true), id: \.group) { group, exercises in
                Section {
                    ForEach(exercises) { exercise in
                        NavigationLink {
                            LibraryExerciseView(exercise: exercise)
                        } label: {
                            LibraryExerciseRow(exercise: exercise, isSelected: nil, showsChevron: false)
                        }
                    }
                    if group == .withoutCamera {
                        Button("Compté à la main ou minuteur", systemImage: "plus") { addingWithoutCamera = true }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if group == .withoutCamera {
                        Text("Pour un exercice que la caméra ne suit pas : vous comptez vous-même, ou un minuteur pour une position tenue.")
                    }
                }
            }
        }
        .navigationTitle("Choisir un exercice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingWithoutCamera) {
            WithoutCameraExercisePicker { catalogID, name, holdSeconds in
                LibraryExercise.insert(LibraryExercise(catalogID: catalogID, name: name, holdSeconds: holdSeconds), in: context)
            }
        }
    }
}
