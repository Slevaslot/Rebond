import Foundation

/// Who uses this iPhone: a patient (free app) or a physiotherapist (physiotherapist space, Rebond Pro).
enum AppRole: String {
    case patient
    case physiotherapist

    static let key = "appRole"
}

/// Settings stored on the patient's iPhone and sent with the reports.
enum PatientIdentity {
    static let nameKey = "patientName"
    static let idKey = "patientID"
    static let physiotherapistNameKey = "physiotherapistName"

    /// Created once, so the physiotherapist's list updates the same patient with each new report.
    static var id: UUID {
        if let stored = UserDefaults.standard.string(forKey: idKey).flatMap(UUID.init(uuidString:)) {
            return stored
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: idKey)
        return id
    }
}
