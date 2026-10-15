import SwiftData
import SwiftUI

/// One exercise of a program: the movement drawn in a loop, what to do, how Rebond follows it,
/// how it went last time, and a button to do this exercise alone.
struct ExerciseDetailView: View {
    let program: Program
    let index: Int

    @Environment(AppRouter.self) private var router
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @State private var demonstrationStart = Date.now

    private var exercise: PlannedExercise? {
        let exercises = program.orderedExercises
        return exercises.indices.contains(index) ? exercises[index] : nil
    }

    /// The last time this exercise was done, in any program.
    private var last: (date: Date, result: ExerciseResult)? {
        guard let exercise else { return nil }
        for session in sessions {
            if let result = session.results.first(where: { $0.exerciseName == exercise.name }) {
                return (session.date, result)
            }
        }
        return nil
    }

    var body: some View {
        if let exercise {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    movement(exercise)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(exercise.prescriptionDetail)
                            .font(.title3.weight(.semibold))
                        TrackingBadge(exercise: exercise)
                        Text(howItIsFollowed(exercise))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))

                    if let last {
                        lastTime(last.date, last.result)
                    }

                    Button {
                        router.startWorkout(program, exercise: index)
                    } label: {
                        Label("Faire cet exercice", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
                    .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(exercise.name)
            // Exercise names are long: in the bar, on two lines if needed, rather than cut in large type.
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Exercice introuvable", systemImage: "questionmark.circle")
        }
    }

    /// The camera's exercises show their pictogram doing the movement; the others, their symbol.
    @ViewBuilder
    private func movement(_ exercise: PlannedExercise) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.accentColor.gradient)
            if let catalog = exercise.catalogExercise {
                MovementGuide(exercise: catalog, skeleton: nil, isDemonstrating: true,
                              demonstrationStart: demonstrationStart, isCompact: true, lineWidth: 5)
                    .padding(24)
            } else {
                Image(systemName: exercise.figureSymbol)
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 260)
        .accessibilityElement()
        .accessibilityLabel(Text("Mouvement : \(exercise.name)"))
    }

    private func howItIsFollowed(_ exercise: PlannedExercise) -> LocalizedStringKey {
        if exercise.catalogExercise != nil {
            return "La caméra compte vos répétitions et vous conseille pendant le mouvement. Posez l'iPhone debout, à 2 ou 3 mètres, et placez-vous face à lui."
        }
        return exercise.holdSeconds == nil
            ? "Vous comptez vos répétitions avec les boutons, à votre rythme."
            : "Un minuteur compte le temps de maintien et vous prévient à la fin."
    }

    private func lastTime(_ date: Date, _ result: ExerciseResult) -> some View {
        SummaryCard(title: Text("Dernière fois"), systemImage: "clock.arrow.circlepath", color: .accentColor) {
            Text(date, format: .dateTime.weekday(.wide).day().month())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } content: {
            HStack(alignment: .bottom, spacing: 24) {
                if result.isHeld {
                    BigValue(value: "\(result.heldSeconds)", unit: "s tenues")
                } else {
                    BigValue(value: "\(result.completedReps)", unit: "répétitions")
                }
                if let amplitude = result.amplitude {
                    BigValue(value: "\(Int(amplitude.rounded()))", unit: "% d'amplitude")
                }
            }
        }
    }
}
