import SwiftUI
import UIKit

/// Reads the photographed sheet with the on-device model, then shows the review screen.
struct SheetReadingView: View {
    let photo: UIImage
    let onSave: (EditableProgram) -> Void

    private enum State {
        case reading
        case read(EditableProgram)
        case failed(String)
    }

    @SwiftUI.State private var state = State.reading

    var body: some View {
        switch state {
        case .reading:
            ProgressView("Lecture de la feuille…")
                .task { await read() }
        case .read(let program):
            ProgramEditorView(program: program, notice: "Programme lu sur la feuille. Vérifiez-le.", onSave: onSave)
        case .failed(let message):
            VStack(spacing: 0) {
                ContentUnavailableView("Lecture impossible", systemImage: "doc.text.magnifyingglass", description: Text(message))
                ProgramEditorView(program: EditableProgram(), notice: "Saisissez le programme à la main.", onSave: onSave)
            }
        }
    }

    private func read() async {
        if case .unavailable(let message) = SheetReader.availability {
            state = .failed(message)
            return
        }
        guard let image = Self.upright(photo) else {
            state = .failed(String(localized: "La photo n'a pas pu être ouverte."))
            return
        }
        do {
            state = .read(EditableProgram(try await SheetReader.read(image)))
        } catch {
            state = .failed(String(localized: "La feuille n'a pas pu être lue. Vous pouvez saisir le programme à la main."))
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
