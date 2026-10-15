import CoreGraphics
import Foundation

/// The final choice among the preselected candidates: one of them, or none ("non reconnu").
nonisolated struct RecognitionChoice: Sendable, Equatable {
    /// A candidate's id, or nil when none fits.
    let id: String?
    /// 0 to 1.
    let confidence: Double
    /// One short sentence describing the movement.
    let description: String
}

/// Makes the final choice. The language model on the device, or the distance alone (tests, devices without it).
nonisolated protocol RecognitionChooser: Sendable {
    func choose(summary: String, candidates: [ExerciseSignature], images: [CGImage]) async -> RecognitionChoice?
}

/// The first candidate, with a confidence from how far ahead it is and whether both preselections put it first.
/// Deterministic.
nonisolated struct DistanceChooser: RecognitionChooser {
    let distances: [String: Double]
    /// The signatures and the nearest recordings agree on the first candidate.
    var agreement = false

    func choose(summary: String, candidates: [ExerciseSignature], images: [CGImage]) async -> RecognitionChoice? {
        guard let first = candidates.first, let d1 = distances[first.id] else { return nil }
        let others = candidates.dropFirst().compactMap { distances[$0.id] }
        let d2 = others.min() ?? d1 * 2
        // Alone in front: confident; neck and neck with the second: unsure.
        let margin = d2 > 0 ? max(0, (d2 - d1) / d2) : 0
        let confidence = min(1, 0.4 + margin * 1.5 + (agreement ? 0.25 : 0))
        return RecognitionChoice(id: first.id, confidence: confidence, description: summary)
    }
}

/// What the recognition decided.
nonisolated enum RecognitionResult: Sendable, Equatable {
    case recognized(id: String, name: String, confidence: Double, description: String)
    /// Not in the catalog, or not sure enough: a custom exercise, named from what was measured.
    case notRecognized(name: String, reason: String)

    var name: String {
        switch self {
        case .recognized(_, let name, _, _): name
        case .notRecognized(let name, _): name
        }
    }

    var catalogID: String? {
        if case .recognized(let id, _, _, _) = self { id } else { nil }
    }
}

/// Identifies a filmed movement in three passes: measured by code (already done), narrowed down to a few
/// candidates and chosen among them, then checked against the chosen exercise's signature.
nonisolated struct ExerciseRecognizer: Sendable {
    let catalog: ExerciseCatalogFile
    /// Below this confidence, the movement is not recognized.
    var minimumConfidence = 0.5
    /// Candidates handed to the final choice.
    var candidateCount = 5
    /// Two seconds of movement at least.
    static let minimumFrames = 30

    /// The candidates, from both preselections: their ranks added up, the nearest first.
    func preselect(_ measurement: MovementMeasurement) -> [Preselection.Candidate] {
        // The hips going down (or not) is the surest thing seen from the front: only the exercises that do the same.
        var narrowed = catalog
        let lowering = measurement.position == .mixed
        narrowed.signatures.removeAll { ($0.position == .mixed) != lowering }
        let kept = Set(narrowed.signatures.map(\.id))
        narrowed.examples.removeAll { !kept.contains($0.exercise) }
        if narrowed.signatures.isEmpty { narrowed = catalog }
        let preselection = Preselection(catalog: narrowed)
        let all = narrowed.signatures.count
        let byNeighbors = preselection.byNeighbors(measurement, count: all)
        let byCentroid = preselection.byCentroid(measurement, count: all)
        func rank(_ list: [Preselection.Candidate], _ id: String) -> Int { list.firstIndex { $0.id == id } ?? all }
        let scored: [(Preselection.Candidate, Int)] = byCentroid.map { candidate in
            (candidate, rank(byNeighbors, candidate.id) + rank(byCentroid, candidate.id))
        }
        let ordered = scored.sorted { a, b in
            a.1 != b.1 ? a.1 < b.1 : (a.0.distance != b.0.distance ? a.0.distance < b.0.distance : a.0.id < b.0.id)
        }
        return Array(ordered.prefix(candidateCount).map(\.0))
    }

    func recognize(_ measurement: MovementMeasurement, images: [CGImage] = [],
                   chooser: (any RecognitionChooser)? = nil) async -> RecognitionResult {
        let candidates = preselect(measurement)
        let signatures = candidates.compactMap { candidate in catalog.signatures.first { $0.id == candidate.id } }
        let distances = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.distance) })
        let preselection = Preselection(catalog: catalog)
        let agreement = preselection.byNeighbors(measurement, count: 1).first?.id
            == preselection.byCentroid(measurement, count: 1).first?.id
        let fallback = DistanceChooser(distances: distances, agreement: agreement)
        let choice: RecognitionChoice?
        if let chooser {
            if let chosen = await chooser.choose(summary: measurement.summary, candidates: signatures, images: images) {
                choice = chosen
            } else {
                choice = await fallback.choose(summary: measurement.summary, candidates: signatures, images: images)
            }
        } else {
            choice = await fallback.choose(summary: measurement.summary, candidates: signatures, images: images)
        }
        let custom = CustomExerciseName.make(for: measurement, avoiding: catalog.signatures.map(\.name))
        // A movement of a moment (someone walking back to the phone) is not an exercise to name.
        guard measurement.frames >= Self.minimumFrames else {
            return .notRecognized(name: custom, reason: "Mouvement trop court pour être reconnu.")
        }

        guard let choice, let id = choice.id, let signature = signatures.first(where: { $0.id == id }) else {
            return .notRecognized(name: custom, reason: "Aucun exercice du catalogue ne correspond.")
        }
        guard choice.confidence >= minimumConfidence else {
            return .notRecognized(name: custom, reason: "Pas assez sûr : \(signature.name) ?")
        }
        if let problem = SignatureCheck.mismatch(measurement, signature) {
            return .notRecognized(name: custom, reason: "Ne ressemble pas à « \(signature.name) » : \(problem).")
        }
        return .recognized(id: signature.id, name: signature.name, confidence: choice.confidence,
                           description: choice.description)
    }
}

/// The third pass: does the measured movement fit the chosen exercise? Rules on what is robust from a phone in
/// front (the posture, the sides, what moves); not the exact amplitudes, as patients often move less.
nonisolated enum SignatureCheck {
    /// Why the movement doesn't fit, or nil when it does.
    static func mismatch(_ m: MovementMeasurement, _ s: ExerciseSignature) -> String? {
        if s.position == .standing, m.position == .seated { return "position assise" }
        if s.position != .standing, m.position == .standing, s.mainChannels.contains(.hipsHeight) {
            return "les hanches ne descendent pas"
        }
        // One side or both: not checked, patients often do one side then the other.
        // Standing on one leg, the other knee bent or kept straight: a knee raise bends it (below 125°), a
        // straight-leg raise keeps it straight (above 110°). Not for squats and lunges, where the knee bending
        // toward the camera looks straighter than it is.
        if s.position == .standing, region(of: s).contains(.activeKnee) {
            let usual = s.low[MovementMeasurement.Channel.activeKnee.rawValue].p50
            let measured = m.low[MovementMeasurement.Channel.activeKnee.rawValue]
            if usual < 110, measured > 125 { return "le genou ne se plie pas assez" }
            if usual >= 130, measured < 110 { return "le genou se plie" }
        }
        for channel in MovementMeasurement.Channel.allCases {
            let expected = s.range(channel)
            let measured = m.range(channel) / channel.scale
            // The exercise's main measures move in nearly every recording (95 % of them move at least
            // `expected.p5`): they must move, at least a third as much, as patients often do a smaller movement
            // (a half squat against the recordings' deep squat).
            if s.mainChannels.contains(channel), expected.p5 / channel.scale >= 0.3, m.range(channel) < expected.p5 / 3 {
                return "\(channel.label) bouge trop peu"
            }
            // What stays still in the exercise must not move much.
            if expected.p95 / channel.scale < 0.25, measured > 1 {
                return "\(channel.label) bouge trop"
            }
            // What moves must not go well past where it goes in the recordings (going less far is fine: patients
            // often do a smaller movement). A straight leg raised to the hip isn't a knee raise.
            if region(of: s).contains(channel) {
                let i = channel.rawValue
                let margin = max((s.high[i].p95 - s.high[i].p5) * 0.25, channel.scale * 0.25)
                if m.high[i] > s.high[i].p95 + margin { return "\(channel.label) va trop haut" }
            }
        }
        return nil
    }

    private static let legs: Set<MovementMeasurement.Channel> = [
        .activeKnee, .activeHip, .activeAnkleHeight, .activeKneeHeight, .hipsHeight, .hipsShift, .stanceWidth,
    ]
    private static let arms: Set<MovementMeasurement.Channel> = [
        .activeShoulder, .activeElbow, .activeWristHeight, .activeWristReach, .activeArmLength,
    ]

    /// The measures of the part of the body the exercise works: its legs, its arm, or both. The other limbs may
    /// do anything meanwhile (arms swinging during a leg raise).
    private static func region(of s: ExerciseSignature) -> Set<MovementMeasurement.Channel> {
        var region = Set(s.mainChannels)
        if s.mainChannels.contains(where: legs.contains) { region.formUnion(legs) }
        if s.mainChannels.contains(where: arms.contains) { region.formUnion(arms) }
        return region
    }

}

/// A descriptive name for a movement outside the catalog, built from what was measured: « Flexion du genou droit,
/// debout ». Never one of the catalog's names.
nonisolated enum CustomExerciseName {
    static func make(for m: MovementMeasurement, avoiding names: [String]) -> String {
        let main = m.mainChannels.first
        let side: String = switch m.side {
        case .left: " gauche"
        case .right: " droit"
        case .both: ""
        }
        let both = m.side == .both
        let action: String = switch main {
        case .activeKnee, .otherKnee: both ? "Flexion des genoux" : "Flexion du genou\(side)"
        case .activeHip, .otherHip: both ? "Flexion des hanches" : "Flexion de la hanche\(side.replacingOccurrences(of: "droit", with: "droite"))"
        case .activeElbow, .otherElbow: both ? "Flexion des coudes" : "Flexion du coude\(side)"
        case .activeShoulder, .otherShoulder, .activeWristHeight, .otherWristHeight:
            both ? "Élévation des bras" : "Mouvement du bras\(side)"
        case .activeWristReach, .otherWristReach: both ? "Ouverture des bras" : "Ouverture du bras\(side)"
        case .activeArmLength, .otherArmLength: both ? "Bras vers l'avant" : "Bras\(side) vers l'avant"
        case .activeAnkleHeight, .otherAnkleHeight, .activeKneeHeight, .otherKneeHeight:
            both ? "Mouvement des jambes" : "Élévation de la jambe\(side.replacingOccurrences(of: "droit", with: "droite"))"
        case .hipsHeight: "Descente des hanches"
        case .hipsShift: "Transfert de poids latéral"
        case .trunkLean: "Inclinaison du buste"
        case .stanceWidth: "Écart des pieds"
        case nil: "Mouvement"
        }
        let position: String = switch m.position {
        case .standing, .mixed: "debout"
        case .seated: "assis"
        }
        var name = "\(action), \(position)"
        // Never a catalog name, even by chance.
        if names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { name += " (personnalisé)" }
        return name
    }
}

/// Is the filmed movement usable? Rejects a capture before measuring it, with what to change when filming again.
nonisolated enum CaptureQuality {
    /// Joints Vision gave in at least this share of the frames: the rest is too unsure to measure.
    static let minimumPresence = 0.6

    /// What is wrong with the capture, or nil when it is good enough.
    /// - Parameter frameCount: Frames analyzed in the video, with or without the patient.
    static func problem(_ samples: [ReferenceSample], frameCount: Int) -> String? {
        guard !samples.isEmpty else { return "Personne n'est visible. Filmez le patient de face, le corps entier dans l'image." }
        let withBody = samples.filter { $0.measure != nil }
        if Double(withBody.count) / Double(max(frameCount, samples.count)) < 0.5 {
            return "Le corps n'est visible que par moments. Filmez de face, sans rien devant le patient."
        }
        /// Share of the frames where one side at least shows all these joints (seen from the side, the other is hidden).
        func presence(_ left: [KeyPath<PoseMeasure, CGPoint?>], _ right: [KeyPath<PoseMeasure, CGPoint?>]) -> Double {
            let seen = withBody.filter { sample in
                left.allSatisfy { sample.measure![keyPath: $0] != nil } || right.allSatisfy { sample.measure![keyPath: $0] != nil }
            }
            return Double(seen.count) / Double(withBody.count)
        }
        if presence([\.leftAnkle], [\.rightAnkle]) < minimumPresence {
            return "Les pieds sortent de l'image. Reculez l'iPhone pour voir le corps entier, pieds compris."
        }
        if presence([\.leftHip, \.leftKnee], [\.rightHip, \.rightKnee]) < minimumPresence {
            return "Les jambes sont mal visibles. Filmez de face, avec une tenue qui se distingue du fond."
        }
        if presence([\.leftShoulder, \.leftElbow, \.leftWrist], [\.rightShoulder, \.rightElbow, \.rightWrist]) < minimumPresence {
            return "Les bras sont mal visibles. Filmez de face, le corps entier dans l'image, sans contre-jour."
        }
        // Joints at the very edge of the picture: the body is cut.
        let atEdge = withBody.filter { sample in
            sample.points.values.contains { $0.x < 0.01 || $0.x > 0.99 || $0.y < 0.01 || $0.y > 0.99 }
        }
        if Double(atEdge.count) / Double(withBody.count) > 0.3 {
            return "Le corps touche le bord de l'image. Reculez l'iPhone ou centrez le patient."
        }
        return nil
    }
}
