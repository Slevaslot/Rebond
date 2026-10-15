import SwiftData
import SwiftUI

/// One program: when and how long, a button to start it, then its exercises in order. An exercise opens its
/// page (the movement, how it is followed, do it alone). Changing or deleting the program is in the ⋯ menu.
struct ProgramDetailView: View {
    let program: Program
    let color: Color

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditingItem?
    @State private var confirmingDelete = false
    @State private var savedEdit = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary

                Text("Exercices")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(program.orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                        if index > 0 { Divider().padding(.leading, 70) }
                        NavigationLink {
                            ExerciseDetailView(program: program, index: index)
                        } label: {
                            ExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))

                // Following and deleting, at the end of the page, as in Contacts.
                VStack(spacing: 0) {
                    Button {
                        program.isActive.toggle()
                    } label: {
                        Label(program.isActive ? "Ne plus suivre ce programme" : "Suivre ce programme",
                              systemImage: program.isActive ? "checkmark.circle.badge.xmark" : "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    Divider().padding(.leading)
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Supprimer le programme", systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
                .padding(.top, 10)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [color.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .ignoresSafeArea()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(program.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { editing = EditingItem(program: EditableProgram(program)) }
            }
        }
        .confirmationDialog("Supprimer « \(program.title) » ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Supprimer le programme", role: .destructive) {
                dismiss()
                context.delete(program)
            }
        } message: {
            Text("Vos séances passées restent dans votre suivi.")
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                ProgramEditorView(program: item.program, title: "Modifier le programme") { saved in
                    program.update(with: saved, in: context)
                    editing = nil
                    savedEdit += 1
                }
            }
            .interactiveDismissDisabled()
        }
        .sensoryFeedback(.success, trigger: savedEdit)
    }

    /// When, how long, who prescribed it, and the main action.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                BigValue(value: "\(program.estimatedMinutes)", unit: "min")
                Spacer()
                Text("^[\(program.exercises.count) exercice](inflect: true)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            DaysStrip(days: program.days, color: color)
            if let prescriber = program.prescriber, !prescriber.isEmpty {
                Label("Prescrit par \(prescriber)", systemImage: "stethoscope")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                router.startWorkout(program)
            } label: {
                Text("Commencer ce programme")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }

    private struct EditingItem: Identifiable {
        let id = UUID()
        let program: EditableProgram
    }
}

/// The week's seven days, the program's days filled in its color.
struct DaysStrip: View {
    let days: [Int]
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProgramSchedule.mondayFirst, id: \.self) { weekday in
                let planned = days.contains(weekday)
                Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .foregroundStyle(planned ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .background(planned ? AnyShapeStyle(color) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .circle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Jours : \(ProgramSchedule.describe(days))"))
    }
}

/// An exercise in a program's list: pictogram, name, what to do, how it is followed.
private struct ExerciseRow: View {
    let exercise: PlannedExercise

    var body: some View {
        HStack(spacing: 14) {
            ExerciseBadge(exercise: exercise, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(exercise.prescriptionDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: exercise.trackingSymbol)
                .foregroundStyle(exercise.catalogExercise != nil ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .accessibilityLabel(exercise.trackingLabel)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
