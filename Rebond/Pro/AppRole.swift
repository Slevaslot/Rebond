import Foundation

/// Who uses this iPhone. Everyone has the patient app; a physiotherapist also turns on the physiotherapist
/// space, which adds the Kiné tab (and opens on it at launch) without hiding the patient app.
enum AppRole: String {
    case patient
    case physiotherapist

    static let key = "appRole"
    /// Set once the first-launch screen (patient or physiotherapist) was answered.
    static let welcomeSeenKey = "welcomeSeen"

    /// Whether the physiotherapist space is turned on. Kept from one launch to the next.
    static var isPhysiotherapistEnabled: Bool {
        UserDefaults.standard.string(forKey: key) == physiotherapist.rawValue
    }
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
