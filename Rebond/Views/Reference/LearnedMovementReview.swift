import SwiftUI

/// What Rebond learned from a film, to check before using it: the clearest repetition in a loop, the start and the
/// end side by side, what was found, and a hint when the analysis wasn't sure which position is the start.
/// The patient can swap the start and the end, or try the movement with the camera before saving it.
struct LearnedMovementReview: View {
    @Binding var movement: ReferenceMovement
    /// The exercise's name, when this review names it (a new film).
    var name: Binding<String>?
    let saveTitle: LocalizedStringKey
    /// The movement is already one of the patient's exercises: a swap is kept right away, and said so.
    var swapIsSaved = false
    /// "Choisir une autre vidéo", for a new film.
    var onChooseOtherVideo: (() -> Void)?
    let onSave: () -> Void

    @State private var swapping = false
    @State private var swapResult: SwapResult?
    @State private var trying = false

    private enum SwapResult { case done, failed }

    private var review: MovementReview { MovementReview(movement) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ReferenceFramesView(movement: movement)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(Color.black)
                    .clipShape(.rect(cornerRadius: 26))
                    .accessibilityLabel(Text("Vidéo de la répétition la plus nette, en boucle"))

                found

                startAndEnd

                if let name {
                    TextField("Nom", text: name, prompt: Text(movement.name))
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.sentences)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                }

                Button(action: onSave) {
                    Text(saveTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)

                Button("Essayer maintenant", systemImage: "camera.viewfinder") { trying = true }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                if let onChooseOtherVideo {
                    Button("Choisir une autre vidéo", action: onChooseOtherVideo)
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                }
            }
            .disabled(swapping)
            .padding()
        }
        .fullScreenCover(isPresented: $trying) {
            // A try with the camera, before saving: nothing is recorded.
            NavigationStack {
                SessionView(exercise: movement.catalogExercise, targetReps: 5, setTitle: "Essai") { _ in trying = false }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Fermer l'essai", systemImage: "xmark") { trying = false }
                        }
                    }
            }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var found: some View {
        VStack(spacing: 4) {
            Label {
                switch review.found {
                case .repetitions(let count): Text("^[\(count) répétition repérée](inflect: true)")
                case .held(let seconds?): Text("Position tenue \(seconds) s")
                case .held(nil): Text("Position tenue repérée")
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.headline)
            if review.alternatesSides {
                Text("Un côté puis l'autre")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The two images the gauge goes between during the session, and the way to swap them.
    private var startAndEnd: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                frame(progress: 0, title: Text("Départ"))
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .accessibilityHidden(true)
                frame(progress: 1, title: endTitle)
            }
            .overlay {
                if swapping {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                        .accessibilityLabel(Text("Inversion du départ et de l'arrivée…"))
                }
            }

            if review.needsChecking {
                checkHint
            }

            gaugeExplanation
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: swap) {
                Label("Inverser départ et arrivée", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            switch swapResult {
            case .done:
                Label {
                    Text(swapIsSaved
                         ? "Départ et arrivée inversés. C'est enregistré : touchez à nouveau pour revenir."
                         : "Départ et arrivée inversés. Touchez à nouveau pour revenir.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.subheadline)
            case .failed:
                Label {
                    Text(onChooseOtherVideo == nil
                         ? "L'inversion n'a pas pu se faire, le mouvement est resté comme avant. Réessayez dans un instant."
                         : "L'inversion n'a pas pu se faire, le mouvement est resté comme avant. Réessayez, ou choisissez une autre vidéo.")
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                }
                .font(.subheadline)
            case nil:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }

    /// "À vérifier": the analysis hesitated between the start and the end.
    private var checkHint: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("À vérifier").font(.subheadline.weight(.semibold))
                Group {
                    if let reason = review.reason {
                        Text("Rebond n'est pas sûr du départ, choisi d'après : \(reason). Le départ doit être la position où vous commencez.")
                    } else {
                        Text("Rebond n'est pas sûr du départ. Le départ doit être la position où vous commencez.")
                    }
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func frame(progress: Double, title: Text) -> some View {
        VStack(spacing: 8) {
            ReferenceFramesView(movement: movement, progress: progress)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color.black)
                .clipShape(.rect(cornerRadius: 18))
            title
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isImage)
    }

    private var endTitle: Text {
        switch review.end {
        case .endOfMovement: Text("Arrivée")
        case .hold(let seconds?): Text("Position à tenir · \(seconds) s")
        case .hold(nil): Text("Position à tenir")
        }
    }

    private var gaugeExplanation: Text {
        switch review.end {
        case .endOfMovement: Text("Pendant la séance, la jauge se remplit du départ vers l'arrivée. Si c'est à l'envers, inversez-les.")
        case .hold: Text("Pendant la séance, la jauge se remplit du départ vers la position à tenir. Si c'est à l'envers, inversez-les.")
        }
    }

    // MARK: Swap

    /// Learns the movement again with its start and end swapped (or back), from the body saved with it.
    private func swap() {
        let swapped = review.swapRequest
        swapping = true
        swapResult = nil
        Task {
            do {
                movement = try await ReferenceStore.relearn(movement, swapped: swapped)
                swapResult = .done
            } catch {
                swapResult = .failed
            }
            swapping = false
        }
    }
}

/// "Vérifier le mouvement" from the page of a filmed exercise. A swap is saved right away (the review says so):
/// closing keeps the movement as it is now.
struct MovementCheckSheet: View {
    @State var movement: ReferenceMovement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LearnedMovementReview(movement: $movement, saveTitle: "Terminé", swapIsSaved: true) { dismiss() }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Vérifier le mouvement")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
                }
        }
    }
}
