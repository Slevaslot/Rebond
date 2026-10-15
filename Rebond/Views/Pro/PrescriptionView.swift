import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI

/// The QR code of a prescribed program, to show to the patient or send as a link. Nothing goes through a server:
/// the whole program is in the link.
struct PrescriptionView: View {
    let transfer: ProgramTransfer
    var patientName: String?
    /// Keeps this program to prescribe it again; nil when it already is a template.
    var onSaveAsTemplate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var savedAsTemplate = false

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

                    if let onSaveAsTemplate {
                        Button {
                            onSaveAsTemplate()
                            withAnimation { savedAsTemplate = true }
                        } label: {
                            Label(savedAsTemplate ? "Enregistré dans vos modèles" : "Enregistrer comme modèle",
                                  systemImage: savedAsTemplate ? "checkmark" : "square.and.arrow.down.on.square")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(savedAsTemplate)
                        .sensoryFeedback(.success, trigger: savedAsTemplate)
                    }
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

/// Prescribing, in a single sheet: start from scratch or from a template, adjust the program, show its QR code,
/// and keep it as a template to prescribe it again.
struct PrescribeFlow: View {
    let program: EditableProgram
    var title: LocalizedStringKey = "Nouveau programme"
    var patientName: String?
    /// Offer the templates first (a new prescription); an adjustment starts from the patient's program.
    var startsWithTemplates = false

    @Environment(\.modelContext) private var context
    @AppStorage(PatientIdentity.physiotherapistNameKey) private var physiotherapistName = ""
    @State private var chosen: EditableProgram?
    @State private var fromTemplate = false
    @State private var prescribed: EditableProgram?

    var body: some View {
        if let prescribed {
            PrescriptionView(
                transfer: ProgramTransfer(prescribed, physiotherapist: physiotherapistName),
                patientName: patientName,
                onSaveAsTemplate: fromTemplate ? nil : {
                    let name = prescribed.name.trimmingCharacters(in: .whitespaces)
                    context.insert(ProgramTemplate(name: name.isEmpty ? prescribed.suggestedName : name, program: prescribed))
                }
            )
        } else if startsWithTemplates, chosen == nil {
            TemplatePicker { program, isTemplate in
                fromTemplate = isTemplate
                withAnimation { chosen = program }
            }
        } else {
            NavigationStack {
                ProgramEditorView(program: chosen ?? program, title: title) { program in
                    withAnimation { prescribed = program }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

/// The first step of a prescription: a new program, one of the physiotherapist's templates, or one of Rebond's.
private struct TemplatePicker: View {
    let onChoose: (_ program: EditableProgram, _ isTemplate: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ProgramTemplate.createdAt, order: .reverse) private var templates: [ProgramTemplate]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { onChoose(EditableProgram(), false) } label: {
                        Label("Nouveau programme", systemImage: "plus")
                            .font(.headline)
                    }
                }
                if !templates.isEmpty {
                    Section("Mes modèles") {
                        ForEach(templates) { template in
                            Button { onChoose(template.program, true) } label: {
                                TemplateRow(name: template.name, program: template.program)
                            }
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash", role: .destructive) { context.delete(template) }
                            }
                        }
                    }
                }
                Section("Modèles Rebond") {
                    ForEach(BuiltInTemplate.all) { item in
                        Button { onChoose(item.program, false) } label: {
                            TemplateRow(name: item.name, program: item.program)
                        }
                    }
                }
            }
            .navigationTitle("Prescrire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
    }
}

private struct TemplateRow: View {
    let name: String
    let program: EditableProgram

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text("^[\(program.exercises.count) exercice](inflect: true) · \(ProgramSchedule.describe(program.weekdays))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
