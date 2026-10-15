import SwiftUI

/// The physiotherapist's message (text message, email, notes), pasted or typed, read by the on-device model,
/// then shown on the review screen.
struct MessageReadingView: View {
    let onSave: (EditableProgram) -> Void

    private enum State {
        case writing
        case reading
        case read(EditableProgram)
        case failed(String, opensSettings: Bool)
    }

    @SwiftUI.State private var state = State.writing
    @SwiftUI.State private var message = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch state {
        case .writing:
            writing
        case .reading:
            reading
                .task { await read() }
        case .read(let program):
            ProgramEditorView(
                program: program,
                notice: "Exercices trouvés par Apple Intelligence dans le message de votre kiné, sur votre iPhone. Vérifiez-les.",
                noticeSymbol: "apple.intelligence",
                onSave: onSave
            )
        case .failed(let message, let opensSettings):
            ProgramEditorView(
                program: EditableProgram(),
                notice: "\(message) Saisissez le programme en vous aidant du message.",
                noticeSymbol: "exclamationmark.triangle",
                opensSettings: opensSettings,
                onSave: onSave
            )
        }
    }

    private var writing: some View {
        Form {
            Section {
                TextEditor(text: $message)
                    .focused($focused)
                    .frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Ex. : « Squats 3x10, élévations des bras 3x12, gainage 30 s. 3 fois par semaine. »")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } footer: {
                Text("Apple Intelligence trouve les exercices dans le message, sur votre iPhone. Vous vérifiez ensuite le programme.")
            }

            Section {
                PasteButton(payloadType: String.self) { strings in
                    message = strings.joined(separator: "\n")
                }
                .buttonBorderShape(.capsule)
                #if DEBUG
                Button("Exemple de message", systemImage: "text.bubble") {
                    message = "Bonjour, comme vu ensemble : squats 3x10, élévations latérales des bras 3x12, gainage 3 fois 30 secondes. À faire 3 fois par semaine. Bon courage !"
                }
                #endif
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Message du kiné")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lire", systemImage: "checkmark") {
                    focused = false
                    state = .reading
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private var reading: some View {
        ContentUnavailableView {
            Label {
                Text("Lecture du message…")
            } icon: {
                ProgressView()
                    .controlSize(.extraLarge)
            }
        } description: {
            Text("Apple Intelligence cherche les exercices sur l'iPhone. Rien n'est envoyé.")
        }
        .navigationTitle("Lecture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func read() async {
        if case .unavailable(let reason, let opensSettings) = SheetReader.messageAvailability {
            state = .failed(reason, opensSettings: opensSettings)
            return
        }
        do {
            let draft = try await SheetReader.read(message: message)
            state = draft.exercises.isEmpty
                ? .failed(String(localized: "Aucun exercice trouvé dans ce message."), opensSettings: false)
                : .read(EditableProgram(draft))
        } catch {
            state = .failed(String(localized: "Le message n'a pas pu être lu."), opensSettings: false)
        }
    }
}
