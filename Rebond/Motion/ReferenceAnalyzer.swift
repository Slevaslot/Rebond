import CoreGraphics
import Foundation
import Vision

/// Learns a movement from the frames of a video (`ReferenceSample`s, 15 per second).
///
/// 1. The body's measures on each frame (`MovementFeatures`), short gaps of Vision interpolated, measures seen on
///    too few frames left out (`featureMask`), frames walking to or from the phone left out.
/// 2. The main change: the direction along which the measures change the most, and its turning points.
/// 3. The starting position: one end of the movement, chosen from what the video shows, in this order of weight:
///    the patient stands still at the start (as the filming screen asks), the end of the video, the posture closest
///    to standing arms along the body, and only a little where the body stays the longest (a pause at the end of
///    the movement is common and must not turn it upside down). A start in the middle, with the movement going to
///    one side then the other in mirror, is an alternating movement: both sides count.
/// 4. The repetitions: from the starting position to the end of the movement and back.
/// 5. Without repetitions, a posture held still a few seconds is a held position (`kind == .hold`).
nonisolated enum ReferenceAnalyzer {
    /// Saved with the movement: movements learned by an older version can be learned again.
    static let version = 2
    static let templatePoints = 24
    /// A repetition starts and ends at these fractions of the movement, as when counting at home.
    static let startFraction = 0.2
    static let backFraction = 0.12
    /// Analyses per second, as during a session.
    static let rate = 15.0

    /// Which end of the movement is the starting position.
    enum RestChoice: Sendable {
        /// Chosen from the video.
        case automatic
        /// The other end than the one chosen from the video: the patient said it was upside down.
        case swapped
    }

    /// Learns the movement of a video. A video often shows it from the front, then from the side: each view is
    /// analyzed apart, and the front one is kept, as the patient faces the iPhone at home. When the movement is
    /// one of the catalog's, it is recognized.
    static func analyze(_ samples: [ReferenceSample], restChoice: RestChoice = .automatic) throws(ReferenceError) -> ReferenceAnalysis {
        let valid = samples.filter { $0.measure != nil }
        guard valid.count >= 20 else { throw .noBody }
        var results: [(analysis: ReferenceAnalysis, samples: [ReferenceSample], facing: Bool)] = []
        var lastError = ReferenceError.noRepetition
        for view in views(of: valid) {
            do {
                results.append((try analyzeView(view.samples, restChoice: restChoice), view.samples, view.facing))
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

    // MARK: One view

    private static func analyzeView(_ view: [ReferenceSample], restChoice: RestChoice, inner: Bool = false) throws(ReferenceError) -> ReferenceAnalysis {
        let analysis = try analyzeWhole(view, restChoice: restChoice)
        // One long "repetition": the patient got into a position first (arms raised before squats), then repeated
        // a smaller movement inside it. The inside, alone, shows the repetitions.
        if !inner, analysis.repCount <= 1, let only = analysis.repetitions.first, only.upperBound - only.lowerBound > 3 {
            let inside = view.filter { $0.time > only.lowerBound + 0.4 && $0.time < only.upperBound - 0.4 }
            if let detailed = try? analyzeView(inside, restChoice: restChoice, inner: true), detailed.repCount >= 2 {
                return detailed
            }
        }
        return analysis
    }

    private static func analyzeWhole(_ view: [ReferenceSample], restChoice: RestChoice) throws(ReferenceError) -> ReferenceAnalysis {
        guard view.count >= 20 else { throw .noBody }
        // Walking to or from the phone changes the body's size in the picture: those frames aren't the exercise.
        let overall = median(view.map { $0.measure!.torsoLength })
        guard overall > 0 else { throw .noBody }
        let valid = view.filter { abs($0.measure!.torsoLength / overall - 1) < 0.3 }
        guard valid.count >= 20 else { throw .noBody }
        let torso = median(valid.map { $0.measure!.torsoLength })
        let (features, mask) = Self.features(valid, torso: torso)

        // The main change, from the mean posture.
        let mean = columnMeans(features)
        let centered = features.map { zip($0, mean).map { $0 - $1 } }
        let mainChange = principalDirection(of: centered)
        let along = centered.map { MovementFeatures.dot($0, mainChange) }
        let range = percentile(along, 0.97) - percentile(along, 0.03)
        let turns = range > 0.15 ? turningPoints(along, threshold: range * 0.4) : []
        let lows = turns.filter { !$0.isHigh }.map(\.index), highs = turns.filter(\.isHigh).map(\.index)

        guard turns.count >= 3, !lows.isEmpty, !highs.isEmpty else {
            if let hold = holdAnalysis(valid, features: features, mask: mask) { return hold }
            throw .noRepetition
        }

        // Which end is the starting position.
        let lowLevel = median(lows.map { along[$0] }), highLevel = median(highs.map { along[$0] })
        let decision = startingPosition(along: along, features: features, mask: mask, lows: lows, highs: highs,
                                        lowLevel: lowLevel, highLevel: highLevel, range: range)
        if decision.alternates, restChoice == .automatic,
           let alternating = try? alternatingAnalysis(valid, features: features, mask: mask, start: decision.startFrames) {
            return alternating
        }
        var lowIsRest = decision.lowIsRest
        if restChoice == .swapped { lowIsRest.toggle() }
        let sign = lowIsRest ? 1.0 : -1.0
        let restLevel = lowIsRest ? lowLevel : highLevel
        let firstValues = along.map { sign * ($0 - restLevel) }
        let firstAmplitude = median((lowIsRest ? highs : lows).map { firstValues[$0] })
        guard firstAmplitude > 0.15 else { throw .noRepetition }

        // The starting position: the frames close to it, between the repetitions.
        let restFrames = firstValues.indices.filter { firstValues[$0] <= firstAmplitude * 0.15 }
        let rest = columnMedians(features, rows: restFrames.isEmpty ? Array(features.indices) : restFrames)
        var analysis = try repetitions(valid, features: features, rest: rest, mask: mask, mirrorBoth: false)
        // Once there and held a long time: a held position, not one repetition.
        if analysis.repCount == 1, analysis.longestHold >= 2.5, restChoice == .automatic,
           let hold = holdAnalysis(valid, features: features, mask: mask) {
            return hold
        }
        let reason = restChoice == .swapped
            ? String(localized: "Départ et arrivée inversés par vous")
            : decision.reason
        analysis.restReason = reason
        analysis.restConfidence = restChoice == .swapped ? 1 : decision.confidence
        return analysis
    }

    /// The repetitions from a starting position: the axis, the target, the average repetition, the clearest one.
    /// - Parameter mirrorBoth: An alternating movement: each frame is read on the side it goes to.
    private static func repetitions(_ valid: [ReferenceSample], features: [[Double]], rest: [Double], mask: [Bool],
                                    mirrorBoth: Bool) throws(ReferenceError) -> ReferenceAnalysis {
        var deviations = features.map { zip($0, rest).map { $0 - $1 } }
        var axis = principalDirection(of: deviations)
        func values(_ axis: [Double]) -> [Double] {
            deviations.map { d in
                let direct = MovementFeatures.dot(d, axis)
                return mirrorBoth ? max(direct, MovementFeatures.dot(MovementFeatures.swapped(d), axis)) : direct
            }
        }
        var along = values(axis)
        if !mirrorBoth, (along.max() ?? 0) < -(along.min() ?? 0) {
            axis = axis.map { -$0 }
            along = values(axis)
        }
        if mirrorBoth {
            // Each frame on the side it goes to: the trajectories compare with the side the axis shows.
            deviations = deviations.map { d in
                MovementFeatures.dot(d, axis) >= MovementFeatures.dot(MovementFeatures.swapped(d), axis) ? d : MovementFeatures.swapped(d)
            }
        }
        // A robust height of the movement: the high turning points, not one stray frame.
        let range = percentile(along, 0.97) - percentile(along, 0.03)
        let tops = turningPoints(along, threshold: max(range * 0.4, 0.1)).filter(\.isHigh).map { along[$0.index] }
        let height = tops.isEmpty ? percentile(along, 0.97) : median(tops)
        // Less than about 9° or 0.15 torso length: nothing moved.
        guard height > 0.15 else { throw .noRepetition }

        // The repetitions: from the start threshold, past half the movement, back under the return threshold.
        var reps: [(start: Int, peak: Int, end: Int)] = []
        var start: Int?
        var peak = 0
        for (i, value) in along.enumerated() {
            if let s = start {
                if value > along[peak] { peak = i }
                if value <= height * backFraction {
                    if along[peak] >= height * 0.5 { reps.append((s, peak, i)) }
                    start = nil
                }
            } else if value >= height * startFraction {
                start = i
                peak = i
            }
        }
        guard !reps.isEmpty else { throw .noRepetition }

        let target = median(reps.map { along[$0.peak] })
        let trajectories = reps.map { Array(deviations[$0.start...$0.end]) }
        let resampled = trajectories.map { MovementFeatures.resample($0, points: templatePoints) }
        let template = (0..<templatePoints).map { k in
            (0..<MovementFeatures.count).map { f in resampled.map { $0[k][f] }.reduce(0, +) / Double(resampled.count) }
        }
        let best = reps.indices.max {
            MovementFeatures.resemblance(trajectories[$0], to: template) < MovementFeatures.resemblance(trajectories[$1], to: template)
        }!
        let durations = reps.map { valid[$0.end].time - valid[$0.start].time }
        // The longest time the end of the movement was held, in seconds.
        let longestHold = reps.map { rep -> Double in
            var longest = 0, run = 0
            for i in rep.start...rep.end {
                run = along[i] >= along[rep.peak] * 0.85 ? run + 1 : 0
                longest = max(longest, run)
            }
            return Double(longest) / rate
        }.max() ?? 0

        // How much the end of the movement varies from one repetition to the next.
        let peaks = reps.map { deviations[$0.peak] }
        let spread = (0..<MovementFeatures.count).map { f -> Double in
            let column = peaks.map { $0[f] }
            let average = column.reduce(0, +) / Double(column.count)
            return sqrt(column.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(column.count))
        }

        // The starting position and the end of the movement, around the clearest repetition.
        let restWindow = (max(0, reps[best].start - 8)...reps[best].start).filter { along[$0] <= height * 0.2 }
        let peakWindow = (max(0, reps[best].peak - 2)...min(along.count - 1, reps[best].peak + 2)).map { $0 }
        let poses = guidePoses(rest: (restWindow.isEmpty ? [reps[best].start] : restWindow).map { valid[$0] },
                               target: peakWindow.map { valid[$0] })

        return ReferenceAnalysis(
            axis: axis,
            target: target,
            template: template,
            minDuration: median(durations) * 0.45,
            repCount: reps.count,
            highlightedJoints: movingJoints(axis),
            restPose: poses.rest,
            targetPose: poses.target,
            bestStart: valid[reps[best].start].time,
            bestPeak: valid[reps[best].peak].time,
            bestEnd: valid[reps[best].end].time,
            activeStart: valid[reps.first!.start].time,
            activeEnd: valid[reps.last!.end].time,
            rest: rest,
            featureMask: mask,
            peakSpread: spread,
            alternatesSides: mirrorBoth,
            repetitions: reps.map { valid[$0.start].time...valid[$0.end].time },
            longestHold: longestHold
        )
    }

    /// A start in the middle, then one side and the other in mirror (alternating legs or arms).
    private static func alternatingAnalysis(_ valid: [ReferenceSample], features: [[Double]], mask: [Bool],
                                            start: [Int]) throws(ReferenceError) -> ReferenceAnalysis {
        guard !start.isEmpty else { throw .noRepetition }
        let rest = columnMedians(features, rows: start)
        var analysis = try repetitions(valid, features: features, rest: rest, mask: mask, mirrorBoth: true)
        analysis.restReason = String(localized: "Départ au milieu, puis un côté et l'autre")
        analysis.restConfidence = 0.8
        return analysis
    }

    // MARK: Starting position

    private struct StartDecision {
        var lowIsRest: Bool
        var confidence: Double
        var reason: String
        var alternates: Bool
        /// The frames still at the start of the video.
        var startFrames: [Int]
    }

    private static func startingPosition(along: [Double], features: [[Double]], mask: [Bool], lows: [Int], highs: [Int],
                                         lowLevel: Double, highLevel: Double, range: Double) -> StartDecision {
        func position(_ value: Double) -> Double { (value - lowLevel) / max(highLevel - lowLevel, 1e-6) }
        var score = 0.0
        var reasons: [(weight: Double, text: String)] = []
        let tolerance = range * 0.12

        // Still at the start, as the filming screen asks: the strongest sign. Only at the very start (within
        // half a second): a video that starts moving has no such sign, and a pause later isn't the start.
        let startWindow = stillWindow(along, fromStart: true, tolerance: tolerance).flatMap { $0.lowerBound <= 8 ? $0 : nil }
        var middleStart = false
        if let window = startWindow {
            let p = position(median(Array(window.map { along[$0] })))
            if p < 0.3 {
                score += 2
                reasons.append((2, String(localized: "position du début de la vidéo")))
            } else if p > 0.7 {
                score -= 2
                reasons.append((2, String(localized: "position du début de la vidéo")))
            } else {
                middleStart = true
            }
        }
        // Still at the end of the video, before walking to the phone.
        if let window = stillWindow(along, fromStart: false, tolerance: tolerance) {
            let p = position(median(Array(window.map { along[$0] })))
            if p < 0.3 { score += 0.75 } else if p > 0.7 { score -= 0.75 }
        }
        // Closest to standing, arms along the body.
        let lowPosture = columnMedians(features, rows: lows), highPosture = columnMedians(features, rows: highs)
        let lowFromStanding = MovementFeatures.distanceFromStanding(lowPosture, mask: mask)
        let highFromStanding = MovementFeatures.distanceFromStanding(highPosture, mask: mask)
        let postureVote = max(-1, min(1, (highFromStanding - lowFromStanding) / 0.6))
        score += postureVote
        if abs(postureVote) >= 0.5 { reasons.append((abs(postureVote), String(localized: "posture la plus proche de la station debout"))) }
        // Where the body stays the longest: a weak sign, a pause at the end of the movement is common.
        let nearLow = along.filter { position($0) < 0.2 }.count, nearHigh = along.filter { position($0) > 0.8 }.count
        if nearLow != nearHigh { score += nearLow > nearHigh ? 0.3 : -0.3 }

        // Alternating: still in the middle at the start, close to standing, and both ends mirror each other.
        var alternates = false
        var startFrames: [Int] = []
        if middleStart, let window = startWindow {
            startFrames = Array(window)
            let startPosture = columnMedians(features, rows: startFrames)
            let toLow = zip(lowPosture, startPosture).map { $0 - $1 }, toHigh = zip(highPosture, startPosture).map { $0 - $1 }
            let mirrored = MovementFeatures.swapped(toLow)
            let cosine = MovementFeatures.dot(mirrored, toHigh) / max(MovementFeatures.norm(mirrored) * MovementFeatures.norm(toHigh), 1e-6)
            alternates = cosine > 0.6 && MovementFeatures.distanceFromStanding(startPosture, mask: mask) <= min(lowFromStanding, highFromStanding)
        }

        let reason = reasons.max { $0.weight < $1.weight }?.text ?? String(localized: "position où le corps reste le plus longtemps")
        return StartDecision(lowIsRest: score >= 0, confidence: min(1, abs(score) / 2), reason: reason,
                             alternates: alternates, startFrames: startFrames)
    }

    /// The first (or last) moment of about 0.6 s when the body doesn't move along the movement, in the first
    /// (or last) 40% of the video.
    static func stillWindow(_ values: [Double], fromStart: Bool, tolerance: Double, frames: Int = 9) -> Range<Int>? {
        let n = values.count
        let limit = max(frames, Int(Double(n) * 0.4))
        guard n >= frames else { return nil }
        let starts: [Int] = fromStart ? Array(0...min(limit - frames, n - frames)) : Array(stride(from: n - frames, through: max(0, n - limit), by: -1))
        for s in starts {
            let window = values[s..<s + frames]
            if (window.max() ?? 0) - (window.min() ?? 0) < tolerance { return s..<s + frames }
        }
        return nil
    }

    /// Turning points of a signal: alternately a low and a high, each at least `threshold` away from the previous
    /// one (the last one may not be confirmed yet).
    static func turningPoints(_ v: [Double], threshold: Double) -> [(index: Int, isHigh: Bool)] {
        guard v.count > 1 else { return [] }
        var result: [(index: Int, isHigh: Bool)] = []
        var direction = 0
        var candidate = 0
        var lowest = 0, highest = 0
        for i in 1..<v.count {
            switch direction {
            case 0:
                if v[i] > v[highest] { highest = i }
                if v[i] < v[lowest] { lowest = i }
                if v[highest] - v[lowest] >= threshold {
                    if highest > lowest {
                        result.append((lowest, false))
                        direction = 1
                        candidate = highest
                    } else {
                        result.append((highest, true))
                        direction = -1
                        candidate = lowest
                    }
                }
            case 1:
                if v[i] > v[candidate] {
                    candidate = i
                } else if v[candidate] - v[i] >= threshold {
                    result.append((candidate, true))
                    direction = -1
                    candidate = i
                }
            default:
                if v[i] < v[candidate] {
                    candidate = i
                } else if v[i] - v[candidate] >= threshold {
                    result.append((candidate, false))
                    direction = 1
                    candidate = i
                }
            }
        }
        if direction != 0 { result.append((candidate, direction == 1)) }
        return result
    }

    // MARK: Held position

    /// No repetition: a posture held still at least 2.5 s, away from standing and from the start of the video.
    private static func holdAnalysis(_ valid: [ReferenceSample], features: [[Double]], mask: [Bool]) -> ReferenceAnalysis? {
        let n = features.count
        guard n >= 30 else { return nil }
        let posture = MovementFeatures.posture.filter { mask[$0] }
        guard !posture.isEmpty else { return nil }
        func change(_ i: Int) -> Double {
            let a = features[max(0, i - 1)], b = features[min(n - 1, i + 1)]
            return sqrt(posture.reduce(0) { $0 + pow(a[$1] - b[$1], 2) }) / 2
        }
        // About 2.5° per frame or less.
        let still = (0..<n).map { change($0) < 0.045 }
        var best: Range<Int>?
        var runStart: Int?
        var gap = 0
        for i in 0...n {
            if i < n, still[i] {
                if runStart == nil { runStart = i }
                gap = 0
            } else if let s = runStart {
                gap += 1
                // Two frames of Vision noise don't end the hold.
                if i == n || gap > 2 {
                    let run = s..<(i - gap + 1)
                    if run.count > (best?.count ?? 0) { best = run }
                    runStart = nil
                    gap = 0
                }
            }
        }
        guard let held = best, valid[held.upperBound - 1].time - valid[held.lowerBound].time >= 2.5 else { return nil }
        let heldPosture = columnMedians(features, rows: Array(held))
        // Before the hold: the posture the patient started from, or standing.
        let before = (0..<held.lowerBound).filter { still[$0] }
        let startPosture = before.count >= 6 ? columnMedians(features, rows: Array(before.prefix(15))) : MovementFeatures.standing
        let way = zip(heldPosture, startPosture).map { $0 - $1 }
        let wayInPosture = sqrt(posture.reduce(0) { $0 + pow(way[$1], 2) })
        guard wayInPosture >= 0.6, MovementFeatures.distanceFromStanding(heldPosture, mask: mask) >= 0.6 else { return nil }

        // The axis: from the start to the held posture, over the measures seen.
        let masked = way.enumerated().map { mask[$0.offset] ? $0.element : 0 }
        let length = MovementFeatures.norm(masked)
        guard length > 0 else { return nil }
        let axis = masked.map { $0 / length }
        // Getting into the position: from the last moment close to the start, to the held posture.
        let deviations = features.map { zip($0, startPosture).map { $0 - $1 } }
        let progress = deviations.map { MovementFeatures.dot($0, axis) / length }
        let into = (0..<held.lowerBound).last { progress[$0] < 0.2 } ?? max(0, held.lowerBound - 15)
        let trajectory = Array(deviations[into...held.lowerBound])
        let seconds = valid[held.upperBound - 1].time - valid[held.lowerBound].time
        let poses = guidePoses(rest: before.isEmpty ? [valid[into]] : before.prefix(15).map { valid[$0] },
                               target: Array(held.prefix(10)).map { valid[$0] })
        let spread = (0..<MovementFeatures.count).map { f -> Double in
            let column = held.map { features[$0][f] }
            let average = column.reduce(0, +) / Double(column.count)
            return sqrt(column.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(column.count))
        }
        return ReferenceAnalysis(
            axis: axis,
            target: length,
            template: MovementFeatures.resample(trajectory, points: templatePoints),
            minDuration: 0,
            repCount: 0,
            highlightedJoints: movingJoints(axis),
            restPose: poses.rest,
            targetPose: poses.target,
            bestStart: valid[into].time,
            bestPeak: valid[held.lowerBound].time,
            bestEnd: valid[min(held.lowerBound + 15, held.upperBound - 1)].time,
            activeStart: valid[into].time,
            activeEnd: valid[held.upperBound - 1].time,
            rest: startPosture,
            kind: .hold,
            holdSeconds: Int(max(10, min(120, (seconds / 5).rounded() * 5))),
            featureMask: mask,
            peakSpread: spread,
            restReason: String(localized: "position tenue immobile"),
            restConfidence: 1,
            repetitions: [valid[held.lowerBound].time...valid[held.upperBound - 1].time]
        )
    }

    // MARK: Measures

    /// The measures of each frame: short gaps interpolated, then smoothed (median of 5, mean of 3). A measure seen
    /// on less than 70% of the frames is left out (mask false, constant 0): it can't be trusted to follow.
    static func features(_ samples: [ReferenceSample], torso: Double) -> (features: [[Double]], mask: [Bool]) {
        let raw = samples.map { $0.measure.map { MovementFeatures.vector($0, torso: torso) } ?? Array(repeating: nil, count: MovementFeatures.count) }
        let n = raw.count
        guard n > 0 else { return ([], Array(repeating: false, count: MovementFeatures.count)) }
        var mask = Array(repeating: false, count: MovementFeatures.count)
        var columns: [[Double]] = []
        for f in 0..<MovementFeatures.count {
            let known = raw.indices.filter { raw[$0][f] != nil }
            mask[f] = Double(known.count) / Double(n) >= 0.7
            guard mask[f] else {
                columns.append(Array(repeating: 0, count: n))
                continue
            }
            var column = Array(repeating: 0.0, count: n)
            var k = 0
            for i in 0..<n {
                while k + 1 < known.count, known[k + 1] <= i { k += 1 }
                let before = known[k]
                if before == i {
                    column[i] = raw[i][f]!
                } else if before > i {
                    column[i] = raw[before][f]!
                } else if k + 1 < known.count {
                    let after = known[k + 1]
                    let a = raw[before][f]!, b = raw[after][f]!
                    column[i] = a + (b - a) * Double(i - before) / Double(after - before)
                } else {
                    column[i] = raw[before][f]!
                }
            }
            columns.append(smooth(medianFiltered(column, radius: 2), radius: 1))
        }
        let features = (0..<n).map { i in columns.map { $0[i] } }
        return (features, mask)
    }

    /// How much a person moves over the video: the patient doing the exercise moves more, and more often,
    /// than the physiotherapist watching.
    static func motion(of samples: [ReferenceSample]) -> Double {
        let valid = samples.filter { $0.measure != nil }
        guard valid.count >= 20 else { return 0 }
        let torso = median(valid.map { $0.measure!.torsoLength })
        guard torso > 0 else { return 0 }
        let features = features(valid, torso: torso).features
        let mean = columnMeans(features)
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

    private static func movingJoints(_ axis: [Double]) -> [String] {
        let strongest = axis.map(abs).max() ?? 0
        var joints = Set<String>()
        for (f, weight) in axis.enumerated() where abs(weight) >= strongest * 0.35 {
            for joint in MovementFeatures.joints[f] { joints.insert(joint.rawValue.rawValue) }
        }
        return joints.sorted()
    }

    // MARK: Guide poses

    /// The patient's body at the start and at the end of the movement, in the guide's unit box (as wide as 0.65 of
    /// its height), standing on its feet: the outline they fit in before the set is their own body.
    /// Each joint is the median over a few frames (one frame may be wrong); a joint Vision didn't see is mirrored
    /// from the other side, or else placed as on a standing figure of the patient's size; a limb of an impossible
    /// length is replaced the same way. Never a deformed figure.
    static func guidePoses(rest: [ReferenceSample], target: [ReferenceSample]) -> (rest: [String: CGPoint], target: [String: CGPoint]) {
        guard let first = rest.first ?? target.first else { return ([:], [:]) }
        let aspect = first.imageSize.width / max(first.imageSize.height, 1)
        typealias Joint = VNHumanBodyPoseObservation.JointName

        /// Median of each joint seen on at least a third of the frames, in height units, origin top-left.
        func medianPoints(_ samples: [ReferenceSample]) -> [Joint: CGPoint] {
            var result: [Joint: CGPoint] = [:]
            let joints = Set(samples.flatMap { $0.points.keys })
            for joint in joints {
                let seen = samples.compactMap { $0.points[joint] }
                guard seen.count * 3 >= samples.count else { continue }
                result[joint] = CGPoint(x: median(seen.map { Double($0.x) }) * aspect, y: median(seen.map { Double($0.y) }))
            }
            return result
        }
        let restPoints = complete(medianPoints(rest))
        let targetPoints = complete(medianPoints(target), standingFrom: restPoints)

        let top = restPoints[.nose]?.y ?? restPoints[.neck].map { $0.y - 0.06 } ?? 0.1
        let feet = [restPoints[.leftAnkle], restPoints[.rightAnkle]].compactMap { $0?.y }.max() ?? 0.9
        let hips = [restPoints[.leftHip], restPoints[.rightHip]].compactMap { $0?.x }
        let centerX = hips.isEmpty ? 0.5 * aspect : hips.reduce(0, +) / Double(hips.count)
        let scale = 0.87 / max(feet - top, 0.1)

        func box(_ points: [Joint: CGPoint]) -> [String: CGPoint] {
            var result: [String: CGPoint] = [:]
            for (joint, point) in points where joint != .root {
                result[joint.rawValue.rawValue] = CGPoint(x: 0.5 + (point.x - centerX) * scale / 0.65, y: 0.08 + (point.y - top) * scale)
            }
            return result
        }
        return (box(restPoints), box(targetPoints))
    }

    /// Every joint the pictogram draws, plausible: see `guidePoses`.
    /// - Parameter standingFrom: For the end of the movement, the starting body: a joint missing there is taken
    ///   from it (the legs of an arm movement don't move).
    static func complete(_ seen: [VNHumanBodyPoseObservation.JointName: CGPoint],
                         standingFrom start: [VNHumanBodyPoseObservation.JointName: CGPoint]? = nil) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        typealias Joint = VNHumanBodyPoseObservation.JointName
        var points = seen
        func middle(_ a: Joint, _ b: Joint) -> CGPoint? {
            guard let p = points[a], let q = points[b] else { return nil }
            return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        }
        if points[.neck] == nil { points[.neck] = middle(.leftShoulder, .rightShoulder) }
        if points[.root] == nil { points[.root] = middle(.leftHip, .rightHip) }

        // The standing figure, in the patient's size and place: from the neck and the hips when seen.
        let figure = CatalogExercise.squat.guideRest
        let figureNeck = figure[.neck]!, figureHips = CGPoint(x: 0.5, y: figure[.leftHip]!.y)
        let neck = points[.neck] ?? start?[.neck], hips = points[.root] ?? start?[.root]
        let figureTorso = figureHips.y - figureNeck.y
        let torso = neck.flatMap { n in hips.map { h in hypot(h.x - n.x, h.y - n.y) } } ?? 0
        func standing(_ joint: Joint) -> CGPoint? {
            guard let neck, torso > 0.01, let p = figure[joint] else { return nil }
            // The figure's box is 0.65 as wide as high: back to height units.
            return CGPoint(x: neck.x + (p.x - figureNeck.x) * 0.65 * torso / figureTorso,
                           y: neck.y + (p.y - figureNeck.y) * torso / figureTorso)
        }
        let center = neck.map { n in hips.map { (n.x + $0.x) / 2 } ?? n.x }
        let pairs: [(Joint, Joint)] = [(.leftShoulder, .rightShoulder), (.leftElbow, .rightElbow), (.leftWrist, .rightWrist),
                                       (.leftHip, .rightHip), (.leftKnee, .rightKnee), (.leftAnkle, .rightAnkle)]
        for (a, b) in pairs {
            for (missing, other) in [(a, b), (b, a)] where points[missing] == nil {
                if let start, let p = start[missing] {
                    points[missing] = p
                } else if let p = points[other], let center {
                    points[missing] = CGPoint(x: 2 * center - p.x, y: p.y)
                } else if let p = standing(missing) {
                    points[missing] = p
                }
            }
        }
        if points[.nose] == nil, let p = standing(.nose) { points[.nose] = p }

        // A limb longer than the torso and a half, or a joint far from the body, is a detection error.
        guard torso > 0.01 else { return points }
        let limbs: [(Joint, Joint)] = [(.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow),
                                       (.rightElbow, .rightWrist), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
                                       (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)]
        for (from, to) in limbs {
            guard let a = points[from], let b = points[to] else { continue }
            if hypot(b.x - a.x, b.y - a.y) > torso * 1.5, let p = start?[to] ?? standing(to) { points[to] = p }
        }
        if let neck {
            for (joint, p) in points where hypot(p.x - neck.x, p.y - neck.y) > torso * 3.5 {
                points[joint] = start?[joint] ?? standing(joint)
            }
        }
        return points
    }

    // MARK: Math

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

    /// Moving average over `2 radius + 1` values.
    static func smooth(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { i in
            let window = values[max(0, i - radius)...min(values.count - 1, i + radius)]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// Moving median over `2 radius + 1` values: one wrong frame of Vision disappears.
    static func medianFiltered(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { i in median(Array(values[max(0, i - radius)...min(values.count - 1, i + radius)])) }
    }

    static func columnMeans(_ rows: [[Double]]) -> [Double] {
        guard !rows.isEmpty else { return Array(repeating: 0, count: MovementFeatures.count) }
        return (0..<MovementFeatures.count).map { f in rows.map { $0[f] }.reduce(0, +) / Double(rows.count) }
    }

    static func columnMedians(_ rows: [[Double]], rows indices: [Int]) -> [Double] {
        (0..<MovementFeatures.count).map { f in median(indices.map { rows[$0][f] }) }
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))]
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
