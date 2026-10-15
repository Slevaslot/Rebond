import Foundation
import SwiftData

/// A patient followed in the physiotherapist space, from the last report they sent.
@Model
final class TrackedPatient {
    @Attribute(.unique) var patientID: UUID
    var name: String
    /// When the last report was generated on the patient's iPhone.
    var updatedAt: Date
    /// The last `ReportTransfer` received, as sent.
    var report: Data

    init(patientID: UUID, name: String, updatedAt: Date, report: Data) {
        self.patientID = patientID
        self.name = name
        self.updatedAt = updatedAt
        self.report = report
    }

    var transfer: ReportTransfer? {
        try? ReportTransfer.decode(report)
    }

    enum Reception {
        case added(TrackedPatient)
        case updated(TrackedPatient)
        /// A new patient beyond the free offer's limit: nothing was saved.
        case limitReached
    }

    /// Adds the patient, or updates them with a newer report. A new patient is only added when `canAddNew`.
    static func receive(_ data: Data, in context: ModelContext, canAddNew: Bool = true) throws -> Reception {
        let transfer = try ReportTransfer.decode(data)
        let id = transfer.patientID
        if let existing = try context.fetch(FetchDescriptor<TrackedPatient>(predicate: #Predicate { $0.patientID == id })).first {
            if transfer.generatedAt >= existing.updatedAt {
                existing.name = transfer.patientName
                existing.updatedAt = transfer.generatedAt
                existing.report = data
            }
            return .updated(existing)
        }
        guard canAddNew else { return .limitReached }
        let patient = TrackedPatient(patientID: id, name: transfer.patientName, updatedAt: transfer.generatedAt, report: data)
        context.insert(patient)
        return .added(patient)
    }

    enum ImportResult: Equatable {
        /// The patient was added or updated.
        case imported(UUID)
        /// A new patient beyond the free offer's limit: nothing was saved.
        case limitReached
        /// The file isn't a Rebond report.
        case invalid
    }

    /// Reads a `.rebond` report shared by a patient (Files, Mail, Messages…). A new patient beyond the free limit isn't added.
    @discardableResult
    static func importReport(at url: URL, into context: ModelContext, hasPro: Bool) -> ImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .invalid }
        return importReport(data, into: context, hasPro: hasPro)
    }

    static func importReport(_ data: Data, into context: ModelContext, hasPro: Bool) -> ImportResult {
        guard let reception = try? receive(data, in: context, canAddNew: canAddNew(in: context, hasPro: hasPro)) else { return .invalid }
        switch reception {
        case .added(let patient), .updated(let patient):
            // Saved right away: the report may have opened the app, which can be closed just after.
            try? context.save()
            return .imported(patient.patientID)
        case .limitReached: return .limitReached
        }
    }

    /// Whether one more patient can be followed: always with Rebond Pro, up to the limit without.
    static func canAddNew(in context: ModelContext, hasPro: Bool) -> Bool {
        hasPro || ((try? context.fetchCount(FetchDescriptor<TrackedPatient>())) ?? 0) < ProStore.freePatientLimit
    }
}
