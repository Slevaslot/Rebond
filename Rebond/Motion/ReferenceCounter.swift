import CoreGraphics
import Foundation

/// Which side of the body the patient does a filmed movement with, compared with the film.
nonisolated enum MovementSide: Sendable, Equatable {
    /// As in the film.
    case asFilmed
    /// The other side: the film read as in a mirror.
    case mirrored
    /// Either side, chosen at each repetition (an alternating movement).
    case either
}

/// Counts the repetitions of a filmed movement and scores each one against the film.
///
/// - The starting position is measured once the patient stands still close to the film's, and again whenever they
///   rest still there.
/// - Only the measures seen right now count: a joint Vision doesn't see is never replaced by its resting position
///   (that would look like a return to rest). Without the joints that carry the movement, nothing is counted nor
///   advised (`CounterUpdate.isMeasured` false), and the repetition is dropped after a second.
/// - The side is the one asked (`MovementSide`), fixed for a whole repetition: never the best of both sides at each
///   frame, which would hide a wrong side. Done on the other side, the patient is told so.
/// - A tip ("Placez ce bras comme sur la vidéo") only at the end of the movement, held still a moment, and only for
///   a difference larger than the film's own repetitions vary.
nonisolated struct ReferenceCounter: MovementCounter {
    let movement: ReferenceMovement
    let side: MovementSide
    private var cycle: RepCycle
    private var rest: [Double]?
    private var torso = 0.0
    /// Recent frames, to find a still moment.
    private var recent: [(features: [Double?], torso: Double)] = []
    /// The last values, for a median: one wrong frame of Vision doesn't make a repetition.
    private var lastValues: [Double] = []
    private var trajectory: [[Double]] = []
    private var collecting = false
    /// The last repetition cut like the film's, and when it ended.
    private var finished: (points: [[Double]], time: Double)?
    /// The side of the repetition going on: read as in a mirror or not.
    private var repetitionMirrored: Bool?
    /// The side being done, kept from the last clear movement (at rest, both sides look alike).
    private var sidesSwapped = false
    private var unmeasuredSince: Double?
    private var lastProgress = 0.0
    private let stillFrames = 10
    /// The film's way there, from rest to the end of the movement: what the body should look like at each moment.
    private let wayThere: [[Double]]
    /// The body part that differs from the film at the end of the movement, and for how many frames in a row.
    private var mismatch: (fault: Correction, frames: Int)?
    private var saidThisRepetition = false
    /// Frames in a row the other side does the movement while the asked one stays at rest.
    private var otherSideFrames = 0
    private var saidOtherSide = false
    /// A difference must last this many frames (0.3 s) to be shown.
    private let mismatchFrames = 5
    /// About 25° of a joint, or a quarter of the torso length: a visible difference, not detection noise.
    private let mismatchThreshold = 0.42
    /// Without the joints of the movement for this long, the repetition is forgotten.
    private let lostTimeout = 1.0
    /// A repetition starts past 35% of the film's movement and ends back under 25%: at home, between quick
    /// repetitions, patients rarely come all the way back (the film's own cut, 20% and 12%, missed them).
    static let startFraction = 0.35
    static let backFraction = 0.25
    /// Shorter than this (in frames), a "repetition" is a glitch of Vision.
    private let minimumFrames = 4

    init(movement: ReferenceMovement, side: MovementSide = .asFilmed) {
        self.movement = movement
        self.side = movement.alternatesSides == true ? .either : side
        let along = movement.template.map { MovementFeatures.dot($0, movement.axis) }
        let peak = along.indices.max { along[$0] < along[$1] } ?? 0
        wayThere = Array(movement.template.prefix(peak + 1))
        let target = movement.target
        cycle = RepCycle(start: target * Self.startFraction, target: target,
                         back: target * Self.backFraction, reversalMargin: target * 0.1,
                         noise: target * 0.4, minDuration: movement.minDuration, shortfall: .followReference)
    }

    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure else { return unmeasured(at: time) }

        var calibratedNow = false
        let raw = MovementFeatures.vector(measure, torso: torso > 0 ? torso : measure.torsoLength)
        recent.append((raw, measure.torsoLength))
        if recent.count > stillFrames { recent.removeFirst() }
        if !cycle.isInRepetition, let still = stillPosition(), looksLikeFilmRest(still.features) {
            if rest == nil { calibratedNow = true }
            // Again at each still moment at rest: the patient may have moved a little in the room.
            if rest == nil || abs(restValue(still.features)) < movement.target * 0.15 {
                rest = still.features
                torso = still.torso
            }
        }
        guard let rest else { return CounterUpdate(progress: 0, event: nil) }
        // Walking to the phone (or away): the body's size changes, it isn't the exercise.
        guard abs(measure.torsoLength / max(torso, 0.01) - 1) < 0.35 else { return unmeasured(at: time) }

        let current = MovementFeatures.vector(measure, torso: torso)
        let deviation: [Double?] = current.enumerated().map { f, value in value.map { $0 - rest[f] } }
        let direct = side == .mirrored ? nil : reading(deviation, mirrored: false)
        let mirror = side == .asFilmed ? nil : reading(deviation, mirrored: true)
        let chosen: Reading?
        switch side {
        case .asFilmed: chosen = direct
        case .mirrored: chosen = mirror
        case .either:
            if let repetitionMirrored, cycle.isInRepetition {
                chosen = repetitionMirrored ? mirror : direct
            } else {
                chosen = [direct, mirror].compactMap { $0 }.max { $0.value < $1.value }
            }
        }
        guard let chosen else { return unmeasured(at: time) }
        unmeasuredSince = nil

        lastValues.append(chosen.value)
        if lastValues.count > 3 { lastValues.removeFirst() }
        let value = ReferenceAnalyzer.median(lastValues)
        if value >= movement.target * ReferenceAnalyzer.startFraction { sidesSwapped = chosen.mirrored }
        let wasInRepetition = cycle.isInRepetition
        var (event, posture) = cycle.advance(value, fault: nil, at: time)
        if !wasInRepetition, cycle.isInRepetition { repetitionMirrored = chosen.mirrored }
        let progress = min(1, max(0, value / movement.target))
        lastProgress = progress

        // The other side moving while the asked one stays at rest: say it once.
        if side != .either, value < cycle.start,
           let other = reading(deviation, mirrored: side == .asFilmed), other.value >= cycle.counted {
            otherSideFrames += 1
            if otherSideFrames >= mismatchFrames, !saidOtherSide, event == nil {
                saidOtherSide = true
                event = .correction(.useOtherSide)
            }
        } else {
            otherSideFrames = 0
        }

        // At the end of the movement, held still: the body part that differs the most from the film.
        if case .targetReached = cycle.phase, value >= cycle.peak * 0.9, isHeldStill(),
           let fault = difference(chosen.deviation, value: value, mirrored: chosen.mirrored) {
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
        if !cycle.isInRepetition {
            saidThisRepetition = false
            mismatch = nil
        }

        // The repetition, from its start to its return.
        if collecting {
            trajectory.append(chosen.deviation)
            if value <= movement.target * Self.backFraction {
                collecting = false
                finished = (trajectory, time)
                trajectory = []
            }
        } else if value >= movement.target * Self.startFraction {
            collecting = true
            trajectory = [chosen.deviation]
        }

        var result = event
        if case .repCompleted(let rep) = event {
            // How close to the film: the repetition just ended, or the one going on.
            let points = finished.flatMap { time - $0.time < 1.5 ? $0.points : nil } ?? trajectory
            finished = nil
            repetitionMirrored = nil
            if points.count < minimumFrames {
                // Up and down in a few frames: Vision jumped, nobody moved like that.
                result = nil
            } else {
                let score = MovementFeatures.resemblance(points, to: movement.template)
                // Too fast compared with the film's own pace.
                let tooFast = Double(points.count) / ReferenceAnalyzer.rate < movement.minDuration
                // The range stays the amplitude (saved, in the report); the resemblance is only the live feedback.
                result = .repCompleted(RepResult(amplitude: rep.amplitude, tooFast: tooFast, resemblance: score))
            }
        } else if case .repIncomplete = event {
            repetitionMirrored = nil
        }
        if calibratedNow, case .none = result { result = .calibrated }
        return CounterUpdate(progress: progress, event: result, posture: posture, sidesSwapped: sidesSwapped)
    }

    /// The movement read on one side: its value along the film's axis, and the deviation it was read from.
    private struct Reading {
        let value: Double
        let deviation: [Double]
        let mirrored: Bool
    }

    /// The measures seen must carry at least this share of the movement (squared weights along the axis).
    static let minimumVisibleWeight = 0.4

    /// Nil when the measures that carry the movement aren't seen well enough.
    /// The value is estimated from the measures seen only (least squares along the axis): a joint Vision misses on
    /// a frame is neither at rest nor at the target, it just doesn't take part. The shoulder angle and the height
    /// of the wrist tell the same arm raise: one of them is enough.
    private func reading(_ deviation: [Double?], mirrored: Bool) -> Reading? {
        let seen = mirrored ? MovementFeatures.swapped(deviation) : deviation
        let followed = movement.followedFeatures
        let axis = movement.axis
        let total = movement.keyFeatures.reduce(0) { $0 + axis[$1] * axis[$1] }
        let visible = (0..<MovementFeatures.count).filter { followed[$0] && seen[$0] != nil }
        let visibleKey = movement.keyFeatures.filter { seen[$0] != nil }.reduce(0) { $0 + axis[$1] * axis[$1] }
        guard total > 0, visibleKey / total >= Self.minimumVisibleWeight else { return nil }
        let weight = visible.reduce(0) { $0 + axis[$1] * axis[$1] }
        let value = visible.reduce(0) { $0 + seen[$1]! * axis[$1] } / max(weight, 1e-6)
        // The measures not seen are completed along the movement, for the comparison with the film.
        let filled = (0..<MovementFeatures.count).map { f -> Double in
            guard followed[f] else { return 0 }
            return seen[f] ?? value * axis[f]
        }
        return Reading(value: value, deviation: filled, mirrored: mirrored)
    }

    /// The joints of the movement aren't seen: nothing is counted nor advised, and after a second the repetition
    /// going on is forgotten rather than guessed.
    private mutating func unmeasured(at time: Double) -> CounterUpdate {
        if unmeasuredSince == nil { unmeasuredSince = time }
        if time - (unmeasuredSince ?? time) >= lostTimeout {
            cycle.abandon()
            collecting = false
            trajectory = []
            repetitionMirrored = nil
            lastValues = []
        }
        recent = []
        mismatch = nil
        return CounterUpdate(progress: lastProgress, event: nil, isMeasured: false)
    }

    /// The body barely moves over the last frames (0.4 s): the end of the movement is held.
    private func isHeldStill() -> Bool {
        let frames = recent.suffix(6)
        guard frames.count == 6 else { return false }
        let key = movement.keyFeatures
        return key.allSatisfy { f in
            let values = frames.compactMap { $0.features[f] }
            guard values.count >= 4 else { return false }
            return (values.max()! - values.min()!) < 0.15
        }
    }

    /// The body part furthest from the film's body at the same point of the movement, if far enough to show:
    /// beyond what the film's own repetitions vary. Only posture measures (not where the body stands).
    private func difference(_ deviation: [Double], value: Double, mirrored: Bool) -> Correction? {
        guard !wayThere.isEmpty else { return nil }
        let reference = wayThere.min {
            abs(MovementFeatures.dot($0, movement.axis) - value) < abs(MovementFeatures.dot($1, movement.axis) - value)
        }!
        let followed = movement.followedFeatures
        let spread = movement.peakSpread ?? Array(repeating: 0, count: MovementFeatures.count)
        let candidates = MovementFeatures.bodyRelative.filter { followed[$0] }
        let errors = candidates.map { f -> (Int, Double) in
            let error = abs(deviation[f] - reference[f])
            return (f, error - max(mismatchThreshold, spread[f] * 3))
        }
        guard let worst = errors.max(by: { $0.1 < $1.1 }), worst.1 > 0 else { return nil }
        let part = MovementFeatures.bodyPart(of: worst.0)
        return mirrored ? part.otherSide : part
    }

    /// Standing as in the film's starting position: a pause at the end of the movement isn't the start.
    private func looksLikeFilmRest(_ features: [Double]) -> Bool {
        guard let filmRest = movement.rest, filmRest.count == features.count else { return true }
        let followed = movement.followedFeatures
        func gap(_ reference: [Double], _ mask: [Bool]) -> Double {
            MovementFeatures.norm(MovementFeatures.bodyRelative.filter { mask[$0] }.map { features[$0] - reference[$0] })
        }
        switch side {
        case .asFilmed: return gap(filmRest, followed) < 0.6
        case .mirrored: return gap(MovementFeatures.swapped(filmRest), MovementFeatures.swapped(followed)) < 0.6
        case .either: return min(gap(filmRest, followed), gap(MovementFeatures.swapped(filmRest), MovementFeatures.swapped(followed))) < 0.6
        }
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

    /// Where a still posture is along the movement, from the current starting position.
    private func restValue(_ features: [Double]) -> Double {
        guard let rest else { return 0 }
        let deviation = zip(features, rest).map { $0 - $1 }
        switch side {
        case .asFilmed: return MovementFeatures.dot(deviation, movement.axis)
        case .mirrored: return MovementFeatures.dot(MovementFeatures.swapped(deviation), movement.axis)
        case .either:
            return max(MovementFeatures.dot(deviation, movement.axis), MovementFeatures.dot(MovementFeatures.swapped(deviation), movement.axis))
        }
    }
}

/// A held position filmed at the physiotherapist's (a wall sit, standing on one leg, arms held out): the timer runs
/// while the patient's posture is the film's, and stops when they leave it or can't be seen.
///
/// `CounterUpdate.progress` is how close to the position (0 at the start, 1 in it); `isHolding` says whether the
/// timer runs. Events: `.bottomReached` when the position is reached, `.correction(.holdPosition)` when it is left.
nonisolated struct HoldCounter: MovementCounter {
    let movement: ReferenceMovement
    let side: MovementSide
    private var holding = false
    private var inFrames = 0
    private var outFrames = 0
    private var lastValues: [Double] = []
    private var unmeasuredSince: Double?
    private var calibrated = false
    /// The film's held posture.
    private let held: [Double]
    /// Frames needed to start (0.3 s) or stop (0.5 s) the timer: Vision's noise doesn't stop it.
    private let framesToStart = 5
    private let framesToStop = 8

    init(movement: ReferenceMovement, side: MovementSide = .asFilmed) {
        self.movement = movement
        self.side = side
        let start = movement.rest ?? MovementFeatures.standing
        held = zip(start, movement.template.last ?? Array(repeating: 0, count: MovementFeatures.count)).map { $0 + $1 }
    }

    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure else { return unmeasured(at: time) }
        let raw = MovementFeatures.vector(measure, torso: measure.torsoLength)
        let current = side == .mirrored ? MovementFeatures.swapped(raw) : raw
        let followed = movement.followedFeatures
        // The measures that make the position (angles, heights from the hips), not where the body stands.
        let key = MovementFeatures.bodyRelative.filter { followed[$0] && abs(movement.axis[$0]) > 0.05 }
        let measures = key.isEmpty ? MovementFeatures.posture.filter { followed[$0] } : key
        let seen = measures.filter { current[$0] != nil }
        guard !measures.isEmpty, Double(seen.count) / Double(measures.count) >= 0.75 else { return unmeasured(at: time) }
        unmeasuredSince = nil

        // How far along the way from the start to the position, from the measures seen (least squares).
        let start = movement.rest ?? MovementFeatures.standing
        let weight = seen.reduce(0) { $0 + movement.axis[$1] * movement.axis[$1] }
        let way = seen.reduce(0) { $0 + (current[$1]! - start[$1]) * movement.axis[$1] } / max(weight, 1e-6)
        lastValues.append(way / max(movement.target, 0.01))
        if lastValues.count > 3 { lastValues.removeFirst() }
        let progress = min(1, max(0, ReferenceAnalyzer.median(lastValues)))

        // In the position: every measure close to the film's, within what the film itself varied.
        let spread = movement.peakSpread ?? Array(repeating: 0, count: MovementFeatures.count)
        let inPosition = seen.allSatisfy { abs(current[$0]! - held[$0]) <= max(0.5, spread[$0] * 3) } && progress >= 0.7

        var event: RepEvent?
        if !calibrated {
            calibrated = true
            event = .calibrated
        }
        if inPosition {
            inFrames += 1
            outFrames = 0
            if !holding, inFrames >= framesToStart {
                holding = true
                event = .bottomReached
            }
        } else {
            outFrames += 1
            inFrames = 0
            if holding, outFrames >= framesToStop {
                holding = false
                event = .correction(.holdPosition)
            }
        }
        return CounterUpdate(progress: progress, event: event, isHolding: holding)
    }

    private mutating func unmeasured(at time: Double) -> CounterUpdate {
        if unmeasuredSince == nil { unmeasuredSince = time }
        inFrames = 0
        // Half a second without seeing the position: the timer stops, nothing is guessed.
        if holding, time - (unmeasuredSince ?? time) >= 0.5 {
            holding = false
        }
        return CounterUpdate(progress: lastValues.last ?? 0, event: nil, isMeasured: false, isHolding: holding)
    }
}
