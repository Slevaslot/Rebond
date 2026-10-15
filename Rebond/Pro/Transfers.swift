import Foundation
import UniformTypeIdentifiers

/// A program prescribed by the physiotherapist, carried in a link (`rebond://programme?d=…`) shown as a QR code.
/// The patient scans it with the iPhone camera: Rebond opens with the program to check. No server involved.
nonisolated struct ProgramTransfer: Codable, Equatable, Sendable {
    struct Exercise: Codable, Equatable, Sendable {
        /// Name.
        var n: String
        /// Catalog entry followed by the camera.
        var c: String?
        /// Sets.
        var s: Int
        /// Repetitions.
        var r: Int
        /// Seconds held, for a held exercise.
        var h: Int?
        /// Both sides, one then the other. Absent from older links and when false.
        var b: Bool? = nil
    }

    static let scheme = "rebond"
    static let host = "programme"

    var v = 1
    /// Sessions per week.
    var f: Int
    var e: [Exercise]
    /// Physiotherapist's name, shown to the patient.
    var k: String?
    /// Session days (Calendar weekdays, 1 is Sunday). Absent from older links: spread from `f`.
    var w: [Int]?
    /// Program name, when the physiotherapist gave one.
    var t: String?

    init(_ program: EditableProgram, physiotherapist: String?) {
        f = program.sessionsPerWeek
        w = program.weekdays
        let title = program.name.trimmingCharacters(in: .whitespaces)
        t = title.isEmpty ? nil : title
        e = program.exercises.map {
            Exercise(n: program.displayName(of: $0), c: $0.mode == .reps ? $0.catalogID : nil, s: $0.sets, r: $0.reps,
                     h: $0.mode == .hold ? $0.holdSeconds : nil, b: $0.bothSides ? true : nil)
        }
        let name = physiotherapist?.trimmingCharacters(in: .whitespaces)
        k = name?.isEmpty == false ? name : nil
    }

    var url: URL? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [URLQueryItem(name: "d", value: data.base64URLEncoded)]
        return components.url
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == Self.host,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value,
              let data = Data(base64URLEncoded: value),
              let transfer = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = transfer
    }

    var editableProgram: EditableProgram {
        var program = EditableProgram()
        program.sessionsPerWeek = min(max(f, 1), 7)
        if let w, !w.isEmpty { program.weekdays = ProgramSchedule.days(weekdays: w.filter { (1...7).contains($0) }, sessionsPerWeek: f) }
        program.name = t ?? ""
        program.exercises = e.map { exercise in
            var item = EditableProgram.Exercise(name: exercise.n, catalogID: exercise.c.flatMap { CatalogExercise.find($0)?.id }, sets: exercise.s, reps: exercise.r)
            if let hold = exercise.h {
                item.mode = .hold
                item.holdSeconds = hold
            }
            item.bothSides = exercise.b ?? false
            return item
        }
        return program
    }
}

extension UTType {
    /// A patient's report, readable by Rebond in the physiotherapist space.
    nonisolated static let rebondReport = UTType(exportedAs: "app.rebond.report")
}

/// The patient's last weeks, in a `.rebond` file sent with the PDF. Opened in Rebond Pro, it adds or updates
/// the patient in the physiotherapist's list, with the same charts as on the patient's iPhone.
nonisolated struct ReportTransfer: Codable, Sendable {
    struct SessionItem: Codable, Sendable {
        let date: Date
        let pain: Int
        let results: [ResultItem]
    }

    struct ResultItem: Codable, Sendable {
        let name: String
        let order: Int
        let plannedReps: Int
        let completedReps: Int
        let incompleteReps: Int
        let plannedSeconds: Int
        let heldSeconds: Int
        let amplitude: Double?
    }

    var version = 1
    /// Stable identifier of the patient's app, so a new report updates the same patient.
    let patientID: UUID
    let patientName: String
    let generatedAt: Date
    let sessionsPerWeek: Int
    let sessions: [SessionItem]
    /// The patient's current program, so the physiotherapist can adjust it and send it back.
    var program: ProgramTransfer?

    init(patientID: UUID, patientName: String, generatedAt: Date = .now, sessionsPerWeek: Int, sessions: [WeeklyReport.SessionData],
         program: ProgramTransfer? = nil) {
        self.program = program
        self.patientID = patientID
        self.patientName = patientName
        self.generatedAt = generatedAt
        self.sessionsPerWeek = sessionsPerWeek
        self.sessions = sessions.map { session in
            SessionItem(date: session.date, pain: session.pain, results: session.results.map {
                ResultItem(name: $0.name, order: $0.order, plannedReps: $0.plannedReps, completedReps: $0.completedReps,
                           incompleteReps: $0.incompleteReps, plannedSeconds: $0.plannedSeconds, heldSeconds: $0.heldSeconds,
                           amplitude: $0.amplitude)
            })
        }
    }

    var sessionData: [WeeklyReport.SessionData] {
        sessions.map { session in
            WeeklyReport.SessionData(date: session.date, pain: session.pain, results: session.results.map {
                WeeklyReport.ResultData(name: $0.name, order: $0.order, plannedReps: $0.plannedReps, completedReps: $0.completedReps,
                                        incompleteReps: $0.incompleteReps, plannedSeconds: $0.plannedSeconds,
                                        heldSeconds: $0.heldSeconds, amplitude: $0.amplitude)
            })
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ReportTransfer {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }

    /// Writes the file to share next to the PDF.
    func write() -> URL? {
        let url = URL.temporaryDirectory.appending(path: String(localized: "Bilan Rebond")).appendingPathExtension(for: .rebondReport)
        guard let data = try? encoded(), (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}

nonisolated extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

extension ReportTransfer {
    /// The report of this iPhone's patient: the last 6 weeks, for the charts, and the current program.
    static func current(sessions: [Session], programs: [Program]) -> ReportTransfer {
        let program = EditableProgram(merging: programs)
        let since = Calendar.current.date(byAdding: .weekOfYear, value: -6, to: .now) ?? .now
        let name = (UserDefaults.standard.string(forKey: PatientIdentity.nameKey) ?? "").trimmingCharacters(in: .whitespaces)
        return ReportTransfer(
            patientID: PatientIdentity.id,
            patientName: name.isEmpty ? String(localized: "Patient") : name,
            sessionsPerWeek: program.exercises.isEmpty ? 3 : program.sessionsPerWeek,
            sessions: sessions.filter { $0.date >= since }.map(\.reportData),
            program: program.exercises.isEmpty ? nil : ProgramTransfer(program, physiotherapist: nil)
        )
    }
}
