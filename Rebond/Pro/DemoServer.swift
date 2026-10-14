#if DEBUG
import Foundation
import Observation
import SwiftData

/// Prototype of the connected version (Rebond Pro with a server), for the pitch demo only: fictional patients,
/// a small server on the team's Mac (`Server/server.py`). Compiled in development builds only, never in the
/// App Store build, which stays serverless.
///
/// - The physiotherapist shows an invitation QR code; the patient scans it and their iPhone is linked.
/// - The patient's report is sent after every session; the physiotherapist's list updates by itself.
/// - The physiotherapist changes the program; the patient's iPhone offers it a few seconds later.
@Observable
final class DemoServer {
    static let shared = DemoServer()

    private enum Key {
        static let url = "demoServerURL"
        static let kineID = "demoKineID"
        static let linkedKineID = "demoLinkedKineID"
        static let linkedKineName = "demoLinkedKineName"
        static let programVersion = "demoProgramVersion"
    }

    /// Server address, e.g. `http://mon-mac.local:8080`.
    var serverURL = UserDefaults.standard.string(forKey: Key.url) ?? "" {
        didSet { UserDefaults.standard.set(serverURL, forKey: Key.url) }
    }
    /// Physiotherapist side: this iPhone's account on the server.
    private(set) var kineID = UserDefaults.standard.string(forKey: Key.kineID) {
        didSet { UserDefaults.standard.set(kineID, forKey: Key.kineID) }
    }
    /// Patient side: the physiotherapist this iPhone is linked to.
    private(set) var linkedKineID = UserDefaults.standard.string(forKey: Key.linkedKineID) {
        didSet { UserDefaults.standard.set(linkedKineID, forKey: Key.linkedKineID) }
    }
    private(set) var linkedKineName = UserDefaults.standard.string(forKey: Key.linkedKineName) {
        didSet { UserDefaults.standard.set(linkedKineName, forKey: Key.linkedKineName) }
    }
    private var appliedProgramVersion = UserDefaults.standard.integer(forKey: Key.programVersion) {
        didSet { UserDefaults.standard.set(appliedProgramVersion, forKey: Key.programVersion) }
    }

    /// A program changed by the physiotherapist, waiting for the patient to check it.
    private(set) var pendingProgram: (version: Int, program: ProgramTransfer)?
    /// Patients linked through the server, shown as "connected" in the physiotherapist's list.
    private(set) var connectedPatients: Set<UUID> = []
    private(set) var lastError: String?

    var isConfigured: Bool { URL(string: serverURL)?.host() != nil }
    var isLinked: Bool { linkedKineID != nil && isConfigured }

    // MARK: Physiotherapist

    /// Creates the physiotherapist's account on the server the first time.
    func registerIfNeeded(name: String) async {
        guard isConfigured, kineID == nil else { return }
        struct Created: Decodable { let id: String }
        if let created: Created = await request("POST", "/kines", body: ["name": name]) {
            kineID = created.id
        }
    }

    /// Link scanned by the patient: `rebond://connecter?s=<server>&k=<physiotherapist>&n=<name>`.
    func invitation(name: String) -> URL? {
        guard let kineID else { return nil }
        var components = URLComponents()
        components.scheme = ProgramTransfer.scheme
        components.host = "connecter"
        components.queryItems = [
            URLQueryItem(name: "s", value: serverURL),
            URLQueryItem(name: "k", value: kineID),
            URLQueryItem(name: "n", value: name),
        ]
        return components.url
    }

    /// Fetches the linked patients' last reports into the list.
    func refreshPatients(into context: ModelContext) async {
        guard let kineID else { return }
        struct Entry: Decodable { let patientID: UUID; let report: ReportTransfer? }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries: [Entry] = await request("GET", "/kines/\(kineID)/patients", decoder: decoder) else { return }
        connectedPatients = Set(entries.map(\.patientID))
        for entry in entries {
            // Linked patients are a Pro feature: no free-offer limit here.
            if let report = entry.report, let data = try? report.encoded() {
                _ = try? TrackedPatient.receive(data, in: context)
            }
        }
    }

    /// Sends a changed program: the patient's iPhone picks it up by itself.
    func send(_ program: ProgramTransfer, to patientID: UUID) async -> Bool {
        struct Sent: Decodable { let version: Int }
        let sent: Sent? = await request("PUT", "/patients/\(patientID.uuidString)/program", json: program)
        return sent != nil
    }

    // MARK: Patient

    /// Handles the invitation link. Returns false when the URL isn't one.
    func link(from url: URL) async -> Bool {
        guard url.scheme == ProgramTransfer.scheme, url.host() == "connecter",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let server = items.first(where: { $0.name == "s" })?.value,
              let kine = items.first(where: { $0.name == "k" })?.value
        else { return false }
        serverURL = server
        linkedKineID = kine
        linkedKineName = items.first(where: { $0.name == "n" })?.value
        appliedProgramVersion = 0
        let name = UserDefaults.standard.string(forKey: PatientIdentity.nameKey) ?? ""
        struct Linked: Decodable { let ok: Bool }
        let _: Linked? = await request("POST", "/patients/\(PatientIdentity.id.uuidString)/link", body: ["kineID": kine, "name": name])
        return true
    }

    func unlink() {
        linkedKineID = nil
        linkedKineName = nil
        pendingProgram = nil
    }

    /// Sends the current report, after each session.
    func pushReport(context: ModelContext) async {
        guard isLinked else { return }
        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let program = try? context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).first
        let report = ReportTransfer.current(sessions: sessions, program: program)
        struct Saved: Decodable { let ok: Bool }
        let _: Saved? = await request("PUT", "/patients/\(PatientIdentity.id.uuidString)/report", body: try? report.encoded())
    }

    /// Looks for a program changed by the physiotherapist.
    func checkProgram() async {
        guard isLinked, pendingProgram == nil else { return }
        struct Prescribed: Decodable { let version: Int; let program: ProgramTransfer }
        guard let prescribed: Prescribed = await request("GET", "/patients/\(PatientIdentity.id.uuidString)/program"),
              prescribed.version > appliedProgramVersion
        else { return }
        pendingProgram = (prescribed.version, prescribed.program)
    }

    /// The patient saved or dismissed the changed program: it isn't offered again.
    func settlePendingProgram() {
        if let pendingProgram { appliedProgramVersion = pendingProgram.version }
        pendingProgram = nil
    }

    // MARK: Network

    private func request<Response: Decodable>(_ method: String, _ path: String, body: [String: String]) async -> Response? {
        await request(method, path, body: try? JSONEncoder().encode(body))
    }

    private func request<Response: Decodable, Body: Encodable>(_ method: String, _ path: String, json: Body) async -> Response? {
        await request(method, path, body: try? JSONEncoder().encode(json))
    }

    private func request<Response: Decodable>(_ method: String, _ path: String, body: Data? = nil,
                                              decoder: JSONDecoder = JSONDecoder()) async -> Response? {
        guard let base = URL(string: serverURL), let url = URL(string: path, relativeTo: base) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            lastError = nil
            return try decoder.decode(Response.self, from: data)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
#endif
