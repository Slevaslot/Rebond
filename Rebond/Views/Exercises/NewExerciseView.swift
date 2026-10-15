import PhotosUI
import SwiftUI

/// "Nouvel exercice": a video of the patient doing the movement, filmed now or picked in Photos. Rebond learns it,
/// then one screen to check it and name it. The exercise joins "Mes exercices", apart from any séance.
/// Also replaces the video of an exercise, which keeps its name and its séances.
struct NewExerciseView: View {
    /// The exercise whose video is replaced; nil creates one.
    var replacing: ReferenceMovement?
    let onDone: (ReferenceMovement) -> Void

    private enum Stage {
        case choose
        case analyzing
        case review(ReferenceMovement)
        case failed(LocalizedStringResource)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseLibrary.self) private var library
    @State private var stage = Stage.choose
    @State private var name = ""
    @State private var filming = false
    @State private var filmed: [URL] = []
    @State private var picking = false
    @State private var picked: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choose: choose
                case .analyzing: analyzing
                case .review(let movement): review(movement)
                case .failed(let reason): failed(reason)
                }
            }
            .navigationTitle(replacing == nil ? "Nouvel exercice" : "Nouvelle vidéo")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark", role: .cancel) { cancel() }
                }
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $filming, onDismiss: {
            guard let video = filmed.first else { return }
            filmed = []
            learn(video, mirrored: false)
        }) {
            RecordMovementView(allowsSeveral: false) { filmed = $0 }
        }
        .photosPicker(isPresented: $picking, selection: $picked, matching: .videos)
        .onChange(of: picked) {
            guard let item = picked else { return }
            picked = nil
            stage = .analyzing
            Task {
                guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
                    stage = .failed("Cette vidéo n'a pas pu être ouverte.")
                    return
                }
                // Filmed with the Camera app, not like a mirror: turned over to look like the session's camera.
                learn(movie.url, mirrored: true)
            }
        }
    }

    // MARK: Stages

    private var choose: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Une vidéo de vous faisant le mouvement avec votre kiné : de face, le corps entier, immobile au début.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                HStack(spacing: 12) {
                    ChoiceTile(title: "Filmer", detail: "Maintenant, avec cet iPhone", symbol: "video.fill") { filming = true }
                    ChoiceTile(title: "Choisir une vidéo", detail: "Déjà filmée, dans Photos", symbol: "photo.on.rectangle") { picking = true }
                }
            }
            .padding()
        }
    }

    private var analyzing: some View {
        ContentUnavailableView {
            Label {
                Text("Analyse du mouvement…")
            } icon: {
                ProgressView().controlSize(.extraLarge)
            }
        } description: {
            Text("Rebond apprend le mouvement sur votre iPhone. La vidéo n'est envoyée nulle part.")
        }
    }

    private func review(_ movement: ReferenceMovement) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ReferenceFramesView(movement: movement)
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)
                    .background(Color.black)
                    .clipShape(.rect(cornerRadius: 26))
                Label("^[\(movement.repCount) répétition repérée](inflect: true)", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                if replacing == nil {
                    TextField("Nom", text: $name, prompt: Text(movement.name))
                        .font(.title3.weight(.semibold))
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                }
                Button { save(movement) } label: {
                    Text(replacing == nil ? "Enregistrer l'exercice" : "Utiliser cette vidéo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                Button("Choisir une autre vidéo") { retry() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            .padding()
        }
    }

    private func failed(_ reason: LocalizedStringResource) -> some View {
        ContentUnavailableView {
            Label("Mouvement non reconnu", systemImage: "figure.stand")
        } description: {
            Text(reason)
        } actions: {
            Button("Essayer une autre vidéo") { retry() }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
        }
    }

    // MARK: Steps

    private func learn(_ video: URL, mirrored: Bool) {
        stage = .analyzing
        Task {
            do {
                stage = .review(try await ReferenceStore.learn(from: video, name: "", mirrored: mirrored))
            } catch ReferenceError.noBody {
                stage = .failed("Rebond n'a pas bien vu le corps. Filmez de face, le corps entier dans l'image, pieds compris.")
            } catch {
                stage = .failed("Rebond n'a pas trouvé de mouvement répété. Restez immobile au début, puis faites 3 à 5 répétitions bien marquées.")
            }
        }
    }

    private func save(_ movement: ReferenceMovement) {
        if let replacing {
            library.replaceVideo(of: replacing, with: movement)
            onDone(replacing)
        } else {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { ReferenceStore.rename(movement.id, to: trimmed) }
            library.reload()
            onDone(ReferenceStore.load(movement.id) ?? movement)
        }
        dismiss()
    }

    private func retry() {
        discardLearned()
        name = ""
        stage = .choose
    }

    private func cancel() {
        discardLearned()
        dismiss()
    }

    /// A video analyzed but not kept leaves nothing behind.
    private func discardLearned() {
        if case .review(let movement) = stage { ReferenceStore.delete(movement.id) }
    }
}

/// A large choice tile: a symbol, a title and a short line.
struct ChoiceTile: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                Spacer(minLength: 12)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}
