import CoreGraphics
import Foundation
import Vision

/// A movement filmed at the physiotherapist's, done right by the patient: any exercise, learned from the video.
///
/// The body of each frame becomes a few measures (angles of the elbows, shoulders, knees and hips, height of the
/// hips, wrists and ankles). The movement is the direction in which those measures change the most from the
/// resting position: one value along it goes from 0 at rest to `target` at the end of the movement, and counts
/// the repetitions like the catalog's exercises. The average repetition (`template`) is what each repetition at
/// home is compared to, for the resemblance score shown to the patient.
nonisolated struct ReferenceMovement: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    /// Unit direction of the movement among the measures.
    let axis: [Double]
    /// Value along the axis at the end of a filmed repetition (median of them).
    let target: Double
    /// The average repetition, from its start to its return, resampled: one vector of measures per point.
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
    /// The measures of the body at rest in the film: at home, the starting position is only measured close to it.
    var rest: [Double]? = nil
    /// The patient's own body at rest and at the end of the movement, in the guide's unit box.
    let restPose: [String: CGPoint]
    let targetPose: [String: CGPoint]
    /// Images of the clearest repetition saved with it, from its start to its return.
    let frameCount: Int
    /// The image at the end of the movement, among them.
    let peakFrame: Int

    var catalogID: String { ReferenceStore.catalogPrefix + id.uuidString }

    static let symbol = "video.fill"
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
    static func resemblance(_ trajectory: [[Double]], to template: [[Double]]) -> Double {
        guard !trajectory.isEmpty, !template.isEmpty else { return 0 }
        let scale = template.map(norm).max() ?? 0
        guard scale > 0 else { return 0 }
        func score(_ points: [[Double]]) -> Double {
            let resampled = resample(points, points: template.count)
            let mean = zip(resampled, template).map { distance($0, $1) }.reduce(0, +) / Double(template.count)
            return max(0, min(1, 1 - mean / scale))
        }
        return max(score(trajectory), score(trajectory.map(swapped)))
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
    /// Times, in the video, of the clearest repetition.
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
}

nonisolated enum ReferenceAnalyzer {
    static let templatePoints = 24
    /// A repetition starts and ends at these fractions of the movement, as when counting at home.
    static let startFraction = 0.2
    static let backFraction = 0.12

    /// Learns the movement of a video. A video often shows it from the front, then from the side: each view is
    /// analyzed apart, and the front one is kept, as the patient faces the iPhone at home. When the movement is
    /// one of the catalog's, it is recognized.
    static func analyze(_ samples: [ReferenceSample]) throws(ReferenceError) -> ReferenceAnalysis {
        let valid = samples.filter { $0.measure != nil }
        guard valid.count >= 20 else { throw .noBody }
        var results: [(analysis: ReferenceAnalysis, samples: [ReferenceSample], facing: Bool)] = []
        var lastError = ReferenceError.noRepetition
        for view in views(of: valid) {
            do {
                results.append((try analyzeView(view.samples), view.samples, view.facing))
            } catch {
                lastError = error
            }
        }
        // Facing the camera first, then the most repetitions.
        guard var best = results.max(by: { ($0.facing ? 1 : 0, $0.analysis.repCount) < ($1.facing ? 1 : 0, $1.analysis.repCount) })
        else { throw lastError }
        // Measured over the repetitions only, with half a second around them.
        let active = best.samples.filter {
            $0.time >= best.analysis.activeStart - 0.5 && $0.time <= best.analysis.activeEnd + 0.5
        }
        best.analysis.measurement = MovementMeasurement.measure((active.count >= 20 ? active : best.samples).map(\.measure))
        return best.analysis
    }

    /// The parts of the video seen from one side: from the front (both shoulders apart) or from the side.
    /// A change of view must last a second and a half to count, so turning a little doesn't split it.
    static func views(of samples: [ReferenceSample]) -> [(samples: [ReferenceSample], facing: Bool)] {
        let widths = samples.map { sample -> Double in
            guard let m = sample.measure, let l = m.leftShoulder, let r = m.rightShoulder, m.torsoLength > 0 else { return 0.5 }
            return abs(Double(l.x - r.x)) / m.torsoLength
        }
        let facing = widths.indices.map { i -> Bool in
            let window = widths[max(0, i - 7)...min(widths.count - 1, i + 7)]
            return median(Array(window)) > 0.45
        }
        var runs: [(range: Range<Int>, facing: Bool)] = []
        var start = 0
        for i in 1...facing.count where i == facing.count || facing[i] != facing[start] {
            runs.append((start..<i, facing[start]))
            start = i
        }
        // Short runs join the run before them.
        var merged: [(range: Range<Int>, facing: Bool)] = []
        for run in runs {
            let seconds = samples[run.range.upperBound - 1].time - samples[run.range.lowerBound].time
            if let last = merged.last, seconds < 1.5 || last.facing == run.facing {
                merged[merged.count - 1].range = last.range.lowerBound..<run.range.upperBound
            } else {
                merged.append(run)
            }
        }
        return merged.map { (Array(samples[$0.range]), $0.facing) }
    }

    private static func analyzeView(_ valid: [ReferenceSample]) throws(ReferenceError) -> ReferenceAnalysis {
        guard valid.count >= 20 else { throw .noBody }

        let torso = median(valid.map { $0.measure!.torsoLength })
        guard torso > 0 else { throw .noBody }

        // Measures of every frame; a measure missing on a frame keeps its last value.
        let features = filledFeatures(valid, torso: torso)

        // The resting position can be anywhere in the video (the patient settles, the physiotherapist talks):
        // along the main change, it is the end where the body stays the longest.
        let mean = (0..<MovementFeatures.count).map { f in features.map { $0[f] }.reduce(0, +) / Double(features.count) }
        let centered = features.map { zip($0, mean).map { $0 - $1 } }
        let mainChange = principalDirection(of: centered)
        let along = centered.map { MovementFeatures.dot($0, mainChange) }
        let low = along.min() ?? 0, high = along.max() ?? 0
        let band = (high - low) * 0.15
        let nearLow = along.indices.filter { along[$0] <= low + band }
        let nearHigh = along.indices.filter { along[$0] >= high - band }
        let restFrames = nearLow.count >= nearHigh.count ? nearLow : nearHigh
        let rest = (0..<MovementFeatures.count).map { f in median(restFrames.map { features[$0][f] }) }
        let deviations = features.map { zip($0, rest).map { $0 - $1 } }

        // The movement's direction: where the measures change the most, together.
        var axis = principalDirection(of: deviations)
        var values = deviations.map { MovementFeatures.dot($0, axis) }
        if (values.max() ?? 0) < -(values.min() ?? 0) {
            axis = axis.map { -$0 }
            values = values.map { -$0 }
        }
        let highest = values.max() ?? 0
        // Less than about 9° or 0.15 torso length: nothing moved.
        guard highest > 0.15 else { throw .noRepetition }

        // The repetitions: from the start threshold, past half the movement, back under the return threshold.
        var reps: [(start: Int, peak: Int, end: Int)] = []
        var start: Int?
        var peak = 0
        for (i, value) in values.enumerated() {
            if let s = start {
                if value > values[peak] { peak = i }
                if value <= highest * backFraction {
                    if values[peak] >= highest * 0.5 { reps.append((s, peak, i)) }
                    start = nil
                }
            } else if value >= highest * startFraction {
                start = i
                peak = i
            }
        }
        guard !reps.isEmpty else { throw .noRepetition }

        let target = median(reps.map { values[$0.peak] })
        let trajectories = reps.map { Array(deviations[$0.start...$0.end]) }
        let resampled = trajectories.map { MovementFeatures.resample($0, points: templatePoints) }
        let template = (0..<templatePoints).map { k in
            (0..<MovementFeatures.count).map { f in resampled.map { $0[k][f] }.reduce(0, +) / Double(resampled.count) }
        }
        let best = reps.indices.max {
            MovementFeatures.resemblance(trajectories[$0], to: template) < MovementFeatures.resemblance(trajectories[$1], to: template)
        }!
        let durations = reps.map { valid[$0.end].time - valid[$0.start].time }

        let strongest = axis.map(abs).max() ?? 0
        var joints = Set<String>()
        for (f, weight) in axis.enumerated() where abs(weight) >= strongest * 0.35 {
            for joint in MovementFeatures.joints[f] { joints.insert(joint.rawValue.rawValue) }
        }

        let restFrame = valid[restFrames.min { MovementFeatures.norm(deviations[$0]) < MovementFeatures.norm(deviations[$1]) } ?? 0]
        let peakFrame = valid[reps[best].peak]
        let poses = guidePoses(rest: restFrame, target: peakFrame)

        return ReferenceAnalysis(
            axis: axis,
            target: target,
            template: template,
            minDuration: median(durations) * 0.45,
            repCount: reps.count,
            highlightedJoints: joints.sorted(),
            restPose: poses.rest,
            targetPose: poses.target,
            bestStart: valid[reps[best].start].time,
            bestPeak: peakFrame.time,
            bestEnd: valid[reps[best].end].time,
            activeStart: valid[reps.first!.start].time,
            activeEnd: valid[reps.last!.end].time,
            rest: rest
        )
    }

    /// The measures of each frame, smoothed; one missing on a frame keeps its last value.
    static func filledFeatures(_ samples: [ReferenceSample], torso: Double) -> [[Double]] {
        var raw = samples.compactMap { $0.measure.map { MovementFeatures.vector($0, torso: torso) } }
        for f in 0..<MovementFeatures.count {
            var last = raw.lazy.compactMap { $0[f] }.first ?? 0
            for i in raw.indices {
                if let value = raw[i][f] { last = value } else { raw[i][f] = last }
            }
        }
        return smooth(raw.map { $0.map { $0 ?? 0 } })
    }

    /// How much a person moves over the video: the patient doing the exercise moves more, and more often,
    /// than the physiotherapist watching.
    static func motion(of samples: [ReferenceSample]) -> Double {
        let valid = samples.filter { $0.measure != nil }
        guard valid.count >= 20 else { return 0 }
        let torso = median(valid.map { $0.measure!.torsoLength })
        guard torso > 0 else { return 0 }
        let features = filledFeatures(valid, torso: torso)
        let mean = (0..<MovementFeatures.count).map { f in features.map { $0[f] }.reduce(0, +) / Double(features.count) }
        let spread = features.map { MovementFeatures.distance($0, mean) }.reduce(0, +) / Double(features.count)
        return spread * Double(valid.count)
    }

    /// A name from what moves, so nothing has to be typed: "Bras", "Jambes", "Bras et jambes", "Buste".
    static func suggestedName(moving joints: [String]) -> String {
        typealias Joint = VNHumanBodyPoseObservation.JointName
        let names = Set(joints)
        func moves(_ list: [Joint]) -> Bool { list.contains { names.contains($0.rawValue.rawValue) } }
        let arms = moves([.leftElbow, .rightElbow, .leftWrist, .rightWrist])
        let legs = moves([.leftKnee, .rightKnee, .leftAnkle, .rightAnkle])
        switch (arms, legs) {
        case (true, true): return String(localized: "Bras et jambes")
        case (true, false): return String(localized: "Bras")
        case (false, true): return String(localized: "Jambes")
        case (false, false): return String(localized: "Buste")
        }
    }

    /// The patient's body at rest and at the end of the movement, in the guide's unit box (as wide as 0.65 of
    /// its height), standing on its feet: the outline they fit in before the set is their own body.
    static func guidePoses(rest: ReferenceSample, target: ReferenceSample) -> (rest: [String: CGPoint], target: [String: CGPoint]) {
        let aspect = rest.imageSize.width / max(rest.imageSize.height, 1)
        func inHeightUnits(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let restPoints = rest.points.mapValues(inHeightUnits)
        let top = restPoints[.nose]?.y ?? restPoints[.neck].map { $0.y - 0.06 } ?? 0.1
        let feet = [restPoints[.leftAnkle], restPoints[.rightAnkle]].compactMap { $0?.y }.max() ?? 0.9
        let hips = [restPoints[.leftHip], restPoints[.rightHip], restPoints[.root]].compactMap { $0?.x }
        let centerX = hips.isEmpty ? 0.5 * aspect : hips.reduce(0, +) / Double(hips.count)
        let scale = 0.87 / max(feet - top, 0.1)

        func box(_ points: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> [String: CGPoint] {
            // The pictogram needs every joint: the ones Vision didn't see come from a standing figure.
            var result = CatalogExercise.squat.guideRest
            for (joint, point) in points.mapValues(inHeightUnits) {
                result[joint] = CGPoint(x: 0.5 + (point.x - centerX) * scale / 0.65, y: 0.08 + (point.y - top) * scale)
            }
            result[.root] = nil
            return Dictionary(uniqueKeysWithValues: result.map { ($0.key.rawValue.rawValue, $0.value) })
        }
        return (box(rest.points), box(target.points))
    }

    /// The direction along which the deviations spread the most (power iteration).
    static func principalDirection(of vectors: [[Double]]) -> [Double] {
        let n = MovementFeatures.count
        var direction = vectors.max { MovementFeatures.norm($0) < MovementFeatures.norm($1) } ?? Array(repeating: 1, count: n)
        for _ in 0..<60 {
            var next = Array(repeating: 0.0, count: n)
            for v in vectors {
                let projection = MovementFeatures.dot(v, direction)
                for f in 0..<n { next[f] += v[f] * projection }
            }
            let length = MovementFeatures.norm(next)
            guard length > 0 else { break }
            direction = next.map { $0 / length }
        }
        let length = MovementFeatures.norm(direction)
        return length > 0 ? direction.map { $0 / length } : direction
    }

    /// Moving average over three frames: Vision's points shake a little from one frame to the next.
    static func smooth(_ vectors: [[Double]]) -> [[Double]] {
        vectors.indices.map { i in
            let window = vectors[max(0, i - 1)...min(vectors.count - 1, i + 1)]
            return (0..<MovementFeatures.count).map { f in window.map { $0[f] }.reduce(0, +) / Double(window.count) }
        }
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

// MARK: - Counting at home

/// Counts the repetitions of a filmed movement and scores each one against the film.
/// The resting position is measured once the patient stands still, and again whenever they rest still.
nonisolated struct ReferenceCounter: MovementCounter {
    let movement: ReferenceMovement
    private var cycle: RepCycle
    private var rest: [Double]?
    private var torso = 0.0
    /// Recent frames, to find a still moment.
    private var recent: [(features: [Double?], torso: Double)] = []
    private var trajectory: [[Double]] = []
    private var collecting = false
    /// The side being done, kept from the last clear movement (at rest, both sides look alike).
    private var sidesSwapped = false
    /// The last repetition cut like the film's, and when it ended.
    private var finished: (points: [[Double]], time: Double)?
    private let stillFrames = 10
    /// The film's way there, from rest to the end of the movement: what the body should look like at each moment.
    private let wayThere: [[Double]]
    /// The body part that differs from the film, and for how many frames in a row.
    private var mismatch: (fault: Correction, frames: Int)?
    /// Said once per repetition at most.
    private var saidThisRepetition = false
    /// A difference must last this many frames (0.3 s) to be shown: Vision is sometimes wrong on a frame.
    private let mismatchFrames = 5
    /// About 25° of a joint, or a quarter of the torso length: a visible difference, not detection noise.
    private let mismatchThreshold = 0.42

    init(movement: ReferenceMovement) {
        self.movement = movement
        let along = movement.template.map { MovementFeatures.dot($0, movement.axis) }
        let peak = along.indices.max { along[$0] < along[$1] } ?? 0
        wayThere = Array(movement.template.prefix(peak + 1))
        let target = movement.target
        cycle = RepCycle(start: target * ReferenceAnalyzer.startFraction, target: target,
                         back: target * ReferenceAnalyzer.backFraction, reversalMargin: target * 0.1,
                         noise: target * 0.4, minDuration: movement.minDuration, shortfall: .followReference)
    }

    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure else {
            cycle.abandon()
            trajectory = []
            collecting = false
            recent = []
            return CounterUpdate(progress: 0, event: nil)
        }

        var calibratedNow = false
        recent.append((MovementFeatures.vector(measure, torso: torso > 0 ? torso : measure.torsoLength), measure.torsoLength))
        if recent.count > stillFrames { recent.removeFirst() }
        let wasInRepetition = cycle.isInRepetition
        if !wasInRepetition, let still = stillPosition(), looksLikeFilmRest(still.features) {
            if rest == nil { calibratedNow = true }
            // Again at each still moment at rest: the patient may have moved a little in the room.
            if rest == nil || abs(deviationValue(still.features)) < movement.target * 0.15 {
                rest = still.features
                torso = still.torso
            }
        }
        guard let rest else { return CounterUpdate(progress: 0, event: nil) }

        let features = MovementFeatures.vector(measure, torso: torso).enumerated().map { $1 ?? rest[$0] }
        let deviation = zip(features, rest).map { $0 - $1 }
        let direct = MovementFeatures.dot(deviation, movement.axis)
        let mirrored = MovementFeatures.dot(MovementFeatures.swapped(deviation), movement.axis)
        let value = max(direct, mirrored)
        if value >= movement.target * ReferenceAnalyzer.startFraction { sidesSwapped = mirrored > direct }

        var (event, posture) = cycle.advance(value, fault: nil, at: time)
        let progress = min(1, max(0, value / movement.target))
        let inRepetition = cycle.isInRepetition

        // Compared with the film at the same moment of the movement: the body part that differs the most.
        if inRepetition, progress >= 0.3, posture == nil,
           let fault = difference(mirrored > direct ? MovementFeatures.swapped(deviation) : deviation, value: value,
                                  sidesSwapped: mirrored > direct) {
            let frames = mismatch?.fault == fault ? mismatch!.frames + 1 : 1
            mismatch = (fault, frames)
            if frames >= mismatchFrames {
                posture = fault
                if !saidThisRepetition, event == nil {
                    saidThisRepetition = true
                    event = .correction(fault)
                }
            }
        } else {
            mismatch = nil
        }
        if !inRepetition {
            saidThisRepetition = false
            mismatch = nil
        }
        // The repetition as the film's were cut: from 20% of the movement to the return under 12%.
        if collecting {
            trajectory.append(deviation)
            if value <= movement.target * ReferenceAnalyzer.backFraction {
                collecting = false
                finished = (trajectory, time)
                trajectory = []
            }
        } else if value >= movement.target * ReferenceAnalyzer.startFraction {
            collecting = true
            trajectory = [deviation]
        }

        var result = event
        if case .repCompleted(let rep) = event {
            // How close to the film: the repetition just ended, or the one going on.
            let points = finished.flatMap { time - $0.time < 1.5 ? $0.points : nil } ?? trajectory
            let score = points.count >= 3 ? MovementFeatures.resemblance(points, to: movement.template) : rep.amplitude
            // Too fast compared with the film's own pace (15 measures per second).
            let tooFast = points.count >= 3 ? Double(points.count) / 15 < movement.minDuration : rep.tooFast
            result = .repCompleted(RepResult(amplitude: score, tooFast: tooFast))
            finished = nil
        }
        if calibratedNow, case .none = result { result = .calibrated }
        return CounterUpdate(progress: progress, event: result, posture: posture, sidesSwapped: sidesSwapped)
    }

    /// The body part furthest from the film's body at the same point of the movement, if far enough to show.
    private func difference(_ deviation: [Double], value: Double, sidesSwapped: Bool) -> Correction? {
        guard !wayThere.isEmpty else { return nil }
        let reference = wayThere.min {
            abs(MovementFeatures.dot($0, movement.axis) - value) < abs(MovementFeatures.dot($1, movement.axis) - value)
        }!
        let errors = zip(deviation, reference).map { abs($0 - $1) }
        guard let worst = errors.indices.max(by: { errors[$0] < errors[$1] }), errors[worst] >= mismatchThreshold
        else { return nil }
        let part = MovementFeatures.bodyPart(of: worst)
        return sidesSwapped ? part.otherSide : part
    }

    /// Standing as in the film's resting position: a pause at the end of the movement isn't the start.
    private func looksLikeFilmRest(_ features: [Double]) -> Bool {
        guard let filmRest = movement.rest, filmRest.count == features.count else { return true }
        let gap = MovementFeatures.bodyRelative.map { features[$0] - filmRest[$0] }
        return MovementFeatures.norm(gap) < 0.6
    }

    /// The mean measures of the last frames, when the body barely moved over them.
    private func stillPosition() -> (features: [Double], torso: Double)? {
        guard recent.count == stillFrames else { return nil }
        let mean = (0..<MovementFeatures.count).map { f -> Double in
            let values = recent.compactMap { $0.features[f] }
            return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        let isStill = recent.allSatisfy { frame in
            let filled = frame.features.enumerated().map { $1 ?? mean[$0] }
            return MovementFeatures.distance(filled, mean) < 0.3
        }
        guard isStill else { return nil }
        return (mean, recent.map(\.torso).reduce(0, +) / Double(recent.count))
    }

    private func deviationValue(_ features: [Double]) -> Double {
        guard let rest else { return 0 }
        return MovementFeatures.dot(zip(features, rest).map { $0 - $1 }, movement.axis)
    }
}
