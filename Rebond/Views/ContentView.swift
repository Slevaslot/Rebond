import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(CatalogExercise.squat.name)
                    .font(.title.bold())
                Text("1 série de 10 répétitions")
                    .foregroundStyle(.secondary)
                NavigationLink("Démarrer la séance") {
                    SessionView(exercise: .squat, targetReps: 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Rebond")
        }
    }
}

#Preview {
    ContentView()
}
