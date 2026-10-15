import SwiftUI
import UIKit

/// Reads the scanned sheet with the on-device model, then shows the review screen.
struct SheetReadingView: View {
    let photo: UIImage
    let onSave: (EditableProgram) -> Void

    private enum State {
        case reading
        case read(EditableProgram)
        case failed(String, opensSettings: Bool)
    }

    @SwiftUI.State private var state = State.reading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch state {
        case .reading:
            reading
                .task { await read() }
        case .read(let program):
            ProgramEditorView(
                program: program,
                photo: photo,
                notice: "Exercices lus par Apple Intelligence, sur votre iPhone. Vérifiez-les : l'écriture manuscrite peut être mal lue.",
                onSave: onSave
            )
        case .failed(let message, let opensSettings):
            ProgramEditorView(
                program: EditableProgram(),
                photo: photo,
                notice: "\(message) Saisissez les exercices en vous aidant de la feuille.",
                noticeSymbol: "exclamationmark.triangle",
                opensSettings: opensSettings,
                onSave: onSave
            )
        }
    }

    /// The sheet stays visible, faded, behind a standard loading state.
    private var reading: some View {
        ContentUnavailableView {
            Label {
                Text("Lecture de la feuille…")
            } icon: {
                ProgressView()
                    .controlSize(.extraLarge)
            }
        } description: {
            Text("Apple Intelligence lit vos exercices sur l'iPhone. Rien n'est envoyé.")
        }
        .background {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .opacity(0.15)
                .padding()
                .accessibilityHidden(true)
        }
        .navigationTitle("Lecture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
            }
        }
    }

    private func read() async {
        if case .unavailable(let message, let opensSettings) = SheetReader.availability {
            state = .failed(message, opensSettings: opensSettings)
            return
        }
        guard let image = Self.upright(photo) else {
            state = .failed(String(localized: "La photo n'a pas pu être ouverte."), opensSettings: false)
            return
        }
        do {
            state = .read(EditableProgram(try await SheetReader.read(image)))
        } catch {
            state = .failed(String(localized: "La feuille n'a pas pu être lue."), opensSettings: false)
        }
    }

    /// Camera photos carry their rotation separately: draw them upright, at a size the model handles well.
    private static func upright(_ photo: UIImage) -> CGImage? {
        let scale = min(1, 1600 / max(photo.size.width, photo.size.height))
        let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
