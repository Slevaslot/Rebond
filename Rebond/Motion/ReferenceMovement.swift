import CoreGraphics
import Foundation
import Vision

/// A movement filmed at the physiotherapist's, done right by the patient: any exercise, learned from the video.
///
/// The body of each frame becomes a few measures (angles of the elbows, shoulders, knees and hips, height of the
/// hips, wrists and ankles). The movement is the direction in which those measures change the most from the
/// starting position: one value along it goes from 0 at rest to `target` at the end of the movement, and counts
/// the repetitions like the catalog's exercises. The average repetition (`template`) is what each repetition at
/// home is compared to, for the resemblance score shown to the patient.
///
/// A held position (`kind == .hold`) has no repetition: `target` is the way from the start to the held posture,
/// and the timer runs while the patient keeps it (`HoldCounter`).
///
/// Learned by `ReferenceAnalyzer` (ReferenceAnalyzer.swift), counted at home by `ReferenceCounter`.
nonisolated struct ReferenceMovement: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    /// Unit direction of the movement among the measures, from the starting position to the end of the movement.
    let axis: [Double]
    /// Value along the axis at the end of a filmed repetition (median of them).
    let target: Double
    /// The average repetition, from its start to its return, resampled: one vector of measures per point,
    /// relative to the starting position.
    let template: [[Double]]
    /// Seconds: a repetition faster than that is flagged "too fast".
    let minDuration: Double
    /// Repetitions found in the video.
    let repCount: Int
    /// Raw names of the joints that move, highlighted on the skeleton.
    let highlightedJoints: [String]
    /// The catalog exercise it was recognized as (a squat filmed at the physiotherapist's): only its name and
    /// symbol are shown; the film alone counts the repetitions.
    var recognizedID: String? = nil
    /// Raw name of the SF Symbol shown for it, chosen by Apple Intelligence when it was learned.
    var symbol: String? = nil
    /// What the recognition measured and decided, in a few words (for the page of the exercise).
    var recognitionNote: String? = nil
    /// Sets, repetitions, rest and progression, by rules from the measurement.
    var plan: SessionPlan? = nil
    /// The patient's instructions, put into words from the plan.
    var instructions: PatientInstructions? = nil
    /// The measures of the body at the starting position in the film: at home, the starting position is only
    /// measured close to it.
    var rest: [Double]? = nil
    /// The patient's own body at the start and at the end of the movement, in the guide's unit box.
    let restPose: [String: CGPoint]
    let targetPose: [String: CGPoint]
    /// Images of the clearest repetition saved with it, from its start to its return.
    let frameCount: Int
    /// The image at the end of the movement, among them.
    let peakFrame: Int

    // Learned since the second version of the analysis (nil for movements learned before).

    /// Version of `ReferenceAnalyzer` that learned it.
    var version: Int? = nil
    /// Repetitions or a held position.
    var kind: Kind? = nil
    /// For a held position: seconds the film held it (a suggestion for the program).
    var holdSeconds: Int? = nil
    /// Measures seen well enough in the film to be followed; the others are ignored at home.
    var featureMask: [Bool]? = nil
    /// How much each measure varies from one filmed repetition to the next at the end of the movement: a
    /// difference at home within it isn't worth a tip.
    var peakSpread: [Double]? = nil
    /// The starting position is in the middle and the movement goes to one side then the other (alternating
    /// legs or arms): both sides count.
    var alternatesSides: Bool? = nil
    /// How the starting position was chosen, in a few words, and how sure it is (0 to 1): shown on the review.
    var restReason: String? = nil
    var restConfidence: Double? = nil
    /// The patient swapped the start and the end on the review: kept when the movement is learned again.
    var restSwapped: Bool? = nil
    /// The kept video was turned over when it was learned (imported from Photos).
    var videoMirrored: Bool? = nil
    /// Incremented each time it is learned again: its images changed.
    var revision: Int? = nil

    enum Kind: String, Codable, Sendable {
        case repetitions
        case hold
    }

    var catalogID: String { ReferenceStore.catalogPrefix + id.uuidString }

    var isHold: Bool { kind == .hold }

    /// The patient's side the film shows, when the movement is mostly on one side (one arm, one leg).
    /// Nil for a movement of both sides alike (a squat, both arms) or alternating sides.
    var filmedSide: BodySide? {
        guard alternatesSides != true else { return nil }
        let weight = { (indices: [Int]) in indices.reduce(0) { $0 + abs(axis.indices.contains($1) ? axis[$1] : 0) } }
        let left = weight(MovementFeatures.sidePairs.map(\.0)), right = weight(MovementFeatures.sidePairs.map(\.1))
        if left > right * 1.5 { return .left }
        if right > left * 1.5 { return .right }
        return nil
    }

    /// Measures followed at home.
    var followedFeatures: [Bool] {
        featureMask ?? Array(repeating: true, count: MovementFeatures.count)
    }

    /// The measures that carry the movement: those weighing at least a fifth of the strongest along the axis.
    /// Without them, nothing can be said about the repetition.
    var keyFeatures: [Int] {
        let strongest = axis.map(abs).max() ?? 0
        return axis.indices.filter { abs(axis[$0]) >= strongest * 0.2 && followedFeatures[$0] }
    }

    /// The joints that must be seen to follow it.
    var requiredJoints: Set<VNHumanBodyPoseObservation.JointName> {
        Set(keyFeatures.flatMap { MovementFeatures.joints[$0] })
    }

    static let symbol = "video.fill"
}

nonisolated extension ReferenceMovement {
    /// What a video taught, under a name.
    init(id: UUID, name: String, createdAt: Date = .now, analysis: ReferenceAnalysis, frameCount: Int, peakFrame: Int) {
        self.init(
            id: id, name: name, createdAt: createdAt,
            axis: analysis.axis, target: analysis.target, template: analysis.template,
            minDuration: analysis.minDuration, repCount: analysis.repCount,
            highlightedJoints: analysis.highlightedJoints,
            recognizedID: analysis.recognizedID,
            rest: analysis.rest,
            restPose: analysis.restPose, targetPose: analysis.targetPose,
            frameCount: frameCount, peakFrame: peakFrame,
            version: ReferenceAnalyzer.version,
            kind: analysis.kind,
            holdSeconds: analysis.holdSeconds,
            featureMask: analysis.featureMask,
            peakSpread: analysis.peakSpread,
            alternatesSides: analysis.alternatesSides,
            restReason: analysis.restReason,
            restConfidence: analysis.restConfidence
        )
    }
}

// MARK: - Measures

/// The measures of one body that make a movement, comparable from one body to the other: angles in units of
/// 60°, positions in torso lengths.
nonisolated enum MovementFeatures {
    static let count = 16
    /// Left and right measures, swapped when the patient does the movement on the other side.
    static let sidePairs = [(0, 1), (2, 3), (4, 5), (6, 7), (11, 12), (14, 15)]
    /// Measures that don't depend on where the body stands in the picture: angles and heights from the hips.
    static let bodyRelative = [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 14, 15]
    /// Sideways positions, reversed with the side.
    static let sidewaysIndices = [9, 10]
    /// The angles of the limbs and the lean of the torso: what makes a posture, wherever the body stands.
    static let posture = [0, 1, 2, 3, 4, 5, 6, 7, 10]

    /// Standing still, arms along the body, as most exercises start (measured on the films of the team).
    /// Used only to tell the starting position from the end of the movement when the video doesn't say.
    static let standing: [Double] = [2.9, 2.9, 0.38, 0.38, 2.95, 2.95, 2.85, 2.85, 0, 0, 0, 0, 0, 0, -1.95, -1.95]

    /// Readable names, for the tools and the tests.
    static let names = ["coude G", "coude D", "épaule G", "épaule D", "genou G", "genou D", "hanche G", "hanche D",
                        "hanches ↕", "hanches ↔", "buste", "poignet G", "poignet D", "cou ↕", "cheville G", "cheville D"]

    /// Joints each measure follows, to highlight the moving ones.
    static let joints: [[VNHumanBodyPoseObservation.JointName]] = [
        [.leftShoulder, .leftElbow, .leftWrist], [.rightShoulder, .rightElbow, .rightWrist],
        [.leftShoulder, .leftElbow], [.rightShoulder, .rightElbow],
        [.leftHip, .leftKnee, .leftAnkle], [.rightHip, .rightKnee, .rightAnkle],
        [.leftHip, .leftKnee], [.rightHip, .rightKnee],
        [.leftHip, .rightHip], [.leftHip, .rightHip], [.neck],
        [.leftWrist], [.rightWrist], [.neck],
        [.leftAnkle], [.rightAnkle],
    ]

    /// - Parameter torso: The body's scale, measured at rest.
    static func vector(_ m: PoseMeasure, torso: Double) -> [Double?] {
        let scale = max(torso, 0.01)
        func angle(_ a: CGPoint?, _ b: CGPoint?, _ c: CGPoint?) -> Double? {
            guard let a, let b, let c else { return nil }
            let u = CGVector(dx: a.x - b.x, dy: a.y - b.y), v = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            let lengths = hypot(u.dx, u.dy) * hypot(v.dx, v.dy)
            guard lengths > 0 else { return nil }
            let cosine = Double((u.dx * v.dx + u.dy * v.dy) / lengths)
            return acos(max(-1, min(1, cosine))) * 180 / .pi / 60
        }
        func height(_ p: CGPoint?) -> Double? {
            p.map { (Double($0.y) - Double(m.hips.y)) / scale }
        }
        return [
            angle(m.leftShoulder, m.leftElbow, m.leftWrist),
            angle(m.rightShoulder, m.rightElbow, m.rightWrist),
            angle(m.leftHip, m.leftShoulder, m.leftElbow),
            angle(m.rightHip, m.rightShoulder, m.rightElbow),
            angle(m.leftHip, m.leftKnee, m.leftAnkle),
            angle(m.rightHip, m.rightKnee, m.rightAnkle),
            angle(m.leftShoulder, m.leftHip, m.leftKnee),
            angle(m.rightShoulder, m.rightHip, m.rightKnee),
            Double(m.hips.y) / scale,
            Double(m.hips.x) / scale,
            (Double(m.neck.x) - Double(m.hips.x)) / scale,
            height(m.leftWrist),
            height(m.rightWrist),
            Double(m.neck.y) / scale,
            height(m.leftAnkle),
            height(m.rightAnkle),
        ]
    }

    /// The same measures with left and right swapped.
    static func swapped(_ v: [Double]) -> [Double] {
        var result = v
        for (a, b) in sidePairs { (result[a], result[b]) = (v[b], v[a]) }
        for i in sidewaysIndices { result[i] = -v[i] }
        return result
    }

    static func swapped(_ v: [Double?]) -> [Double?] {
        var result = v
        for (a, b) in sidePairs { (result[a], result[b]) = (v[b], v[a]) }
        for i in sidewaysIndices { result[i] = v[i].map { -$0 } }
        return result
    }

    static func swapped(_ v: [Bool]) -> [Bool] {
        var result = v
        for (a, b) in sidePairs { (result[a], result[b]) = (v[b], v[a]) }
        return result
    }

    /// The body part a measure belongs to, to point at it on the skeleton.
    static func bodyPart(of index: Int) -> Correction {
        switch index {
        case 0, 2, 11: .matchLeftArm
        case 1, 3, 12: .matchRightArm
        case 4, 6, 14: .matchLeftLeg
        case 5, 7, 15: .matchRightLeg
        default: .matchTrunk
        }
    }

    /// How far a posture is from standing still arms along the body, over the measures seen.
    static func distanceFromStanding(_ v: [Double], mask: [Bool]? = nil) -> Double {
        let used = posture.filter { mask?[$0] ?? true }
        guard !used.isEmpty else { return 0 }
        return sqrt(used.reduce(0) { $0 + pow(v[$1] - standing[$1], 2) })
    }

    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    static func distance(_ a: [Double], _ b: [Double]) -> Double {
        sqrt(zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) })
    }

    static func norm(_ a: [Double]) -> Double { sqrt(dot(a, a)) }

    /// Points of a repetition, evenly spaced from its start to its end.
    static func resample(_ trajectory: [[Double]], points: Int) -> [[Double]] {
        guard let first = trajectory.first else { return [] }
        guard trajectory.count > 1 else { return Array(repeating: first, count: points) }
        return (0..<points).map { k in
            let position = Double(k) / Double(points - 1) * Double(trajectory.count - 1)
            let i = Int(position), fraction = position - Double(i)
            let a = trajectory[i], b = trajectory[min(i + 1, trajectory.count - 1)]
            return zip(a, b).map { $0 + ($1 - $0) * fraction }
        }
    }

    /// How close a repetition is to the filmed one: 1 for the same, 0 when it differs by the whole movement.
    /// The side is the one the repetition was counted on: never the best of both, which would hide a wrong side.
    static func resemblance(_ trajectory: [[Double]], to template: [[Double]]) -> Double {
        guard !trajectory.isEmpty, !template.isEmpty else { return 0 }
        let scale = template.map(norm).max() ?? 0
        guard scale > 0 else { return 0 }
        let resampled = resample(trajectory, points: template.count)
        let mean = zip(resampled, template).map { distance($0, $1) }.reduce(0, +) / Double(template.count)
        return max(0, min(1, 1 - mean / scale))
    }
}

// MARK: - Learning from the video

/// One analyzed frame of the filmed video.
nonisolated struct ReferenceSample: Sendable {
    let time: Double
    let measure: PoseMeasure?
    /// Joints in the image, normalized, origin top-left.
    let points: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let imageSize: CGSize
}

nonisolated enum ReferenceError: Error {
    /// The body wasn't seen well enough.
    case noBody
    /// The body was seen, but no movement repeated.
    case noRepetition
    /// The capture is too poor to measure: what to change when filming again.
    case poorCapture(String)
}

/// What the video taught: everything of a `ReferenceMovement` but its name, and when its clearest repetition is.
nonisolated struct ReferenceAnalysis: Sendable {
    let axis: [Double]
    let target: Double
    let template: [[Double]]
    let minDuration: Double
    let repCount: Int
    let highlightedJoints: [String]
    let restPose: [String: CGPoint]
    let targetPose: [String: CGPoint]
    /// Times, in the video, of the clearest repetition (for a held position: getting into it, holding it).
    let bestStart: Double
    let bestPeak: Double
    let bestEnd: Double
    /// From the first repetition's start to the last one's end: the exercise, without getting in place before
    /// or walking to the phone after.
    var activeStart: Double = 0
    var activeEnd: Double = .infinity
    /// The catalog exercise it was recognized as, for its name and symbol.
    var recognizedID: String? = nil
    var rest: [Double] = []
    /// The measurement of the view kept, for the recognition.
    var measurement: MovementMeasurement? = nil
    var kind = ReferenceMovement.Kind.repetitions
    var holdSeconds: Int? = nil
    var featureMask: [Bool] = Array(repeating: true, count: MovementFeatures.count)
    var peakSpread: [Double] = Array(repeating: 0, count: MovementFeatures.count)
    var alternatesSides = false
    /// How the starting position was chosen, and how sure (0 to 1).
    var restReason = ""
    var restConfidence = 1.0
    /// Times of every repetition found, start and end, for the review.
    var repetitions: [ClosedRange<Double>] = []
    /// The longest time the end of a repetition was held, in seconds.
    var longestHold = 0.0
}
