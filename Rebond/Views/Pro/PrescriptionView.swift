import CoreImage.CIFilterBuiltins
import SwiftUI

/// The QR code of a prescribed program, to show to the patient or send as a link. Nothing goes through a server:
/// the whole program is in the link.
struct PrescriptionView: View {
    let transfer: ProgramTransfer
    var patientName: String?
    @Environment(\.dismiss) private var dismiss

    private var instruction: Text {
        if let patientName {
            Text("\(patientName) scanne ce code avec l'appareil photo de son iPhone : le programme s'ouvre dans Rebond.")
        } else {
            Text("Votre patient scanne ce code avec l'appareil photo de son iPhone : le programme s'ouvre dans Rebond.")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let url = transfer.url {
                        QRCodeView(url: url)
                        instruction
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Impossible de créer le QR code.", systemImage: "exclamationmark.triangle")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("^[\(transfer.f) séance](inflect: true) par semaine")
                            .font(.headline)
                        ForEach(Array(transfer.e.enumerated()), id: \.offset) { _, exercise in
                            HStack {
                                Text(exercise.n)
                                Spacer()
                                Group {
                                    if let hold = exercise.h {
                                        Text("\(exercise.s) × \(hold) s")
                                    } else {
                                        Text("\(exercise.s) × \(exercise.r)")
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Programme prescrit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
                }
                if let url = transfer.url {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url, subject: Text("Votre programme Rebond"),
                                  message: Text("Ouvrez ce lien sur votre iPhone pour retrouver votre programme dans Rebond."))
                            .accessibilityLabel("Envoyer le lien du programme")
                    }
                }
            }
        }
    }
}

/// A link as a QR code, on white so any camera reads it.
struct QRCodeView: View {
    let url: URL

    var body: some View {
        if let image = Self.qrCode(for: url.absoluteString) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .padding()
                .background(.white, in: .rect(cornerRadius: 24))
                .accessibilityLabel("QR code du programme")
        }
    }

    static func qrCode(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Composing a program, then its QR code, in a single sheet.
struct PrescribeFlow: View {
    let program: EditableProgram
    var title: LocalizedStringKey = "Nouveau programme"
    var patientName: String?

    @AppStorage(PatientIdentity.physiotherapistNameKey) private var physiotherapistName = ""
    @State private var transfer: ProgramTransfer?

    var body: some View {
        if let transfer {
            PrescriptionView(transfer: transfer, patientName: patientName)
        } else {
            NavigationStack {
                ProgramEditorView(program: program, title: title) { program in
                    withAnimation { transfer = ProgramTransfer(program, physiotherapist: physiotherapistName) }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}
