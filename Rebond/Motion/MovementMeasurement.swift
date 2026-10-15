import CoreGraphics
import Foundation

/// What a filmed movement does, measured by code from the 2D body pose: the same measures make the catalog's
/// signatures (from the Kinect recordings) and describe a movement filmed at the physiotherapist's, so they can be
/// compared. Deterministic: the same frames always give the same measurement.
///
/// Every measure is independent of where the patient stands, of their size and of the camera's mirroring: angles
/// in degrees, positions as a share of the person's own leg or arm length, on both sides of the body's middle.
/// Leg and arm lengths, rather than the torso, because the Kinect and Vision don't place the hips at the same height. The two sides are put in order: the side that
/// moves the most is the "active" one, so a movement done with the left arm matches the same one done with the right.
nonisolated struct MovementMeasurement: Codable, Sendable, Equatable {
    /// One measure followed frame by frame.
    enum Channel: Int, CaseIterable, Codable, Sendable {
        case activeKnee, otherKnee
        case activeHip, otherHip
        case activeElbow, otherElbow
        case activeShoulder, otherShoulder
        /// Height of the hips above the ankles.
        case hipsHeight
        /// Hips away from the middle of the feet, sideways.
        case hipsShift
        /// Trunk leaning to a side, in degrees.
        case trunkLean
        /// Wrists above the shoulders.
        case activeWristHeight, otherWristHeight
        /// Wrists away from the body's middle, sideways.
        case activeWristReach, otherWristReach
        /// Arms' length seen on the picture, shorter when the arm points at or away from the camera.
        case activeArmLength, otherArmLength
        /// Ankles above the hips (negative: below).
        case activeAnkleHeight, otherAnkleHeight
        /// Knees above the hips (negative: below).
        case activeKneeHeight, otherKneeHeight
        /// Distance between the ankles.
        case stanceWidth

        /// Size of a meaningful change, to put angles and positions on the same scale.
        var scale: Double {
            switch self {
            case .activeKnee, .otherKnee, .activeHip, .otherHip, .activeElbow, .otherElbow,
                 .activeShoulder, .otherShoulder, .trunkLean: 45
            default: 0.25
            }
        }

        /// For the readable summary.
        var label: String {
            switch self {
            case .activeKnee, .otherKnee: "genou"
            case .activeHip, .otherHip: "hanche"
            case .activeElbow, .otherElbow: "coude"
            case .activeShoulder, .otherShoulder: "épaule"
            case .hipsHeight: "hauteur des hanches"
            case .hipsShift: "décalage des hanches"
            case .trunkLean: "inclinaison du buste"
            case .activeWristHeight, .otherWristHeight: "hauteur du poignet"
            case .activeWristReach, .otherWristReach: "écart du poignet"
            case .activeArmLength, .otherArmLength: "longueur apparente du bras"
            case .activeAnkleHeight, .otherAnkleHeight: "hauteur de la cheville"
            case .activeKneeHeight, .otherKneeHeight: "hauteur du genou"
            case .stanceWidth: "écart des pieds"
            }
        }

        var isAngle: Bool { scale == 45 }

        /// Measures of the moving side, for the side rule.
        static let activeSide: [Channel] = [.activeKnee, .activeHip, .activeElbow, .activeShoulder, .activeWristHeight,
                                            .activeWristReach, .activeArmLength, .activeAnkleHeight, .activeKneeHeight]
        static let otherSide: [Channel] = [.otherKnee, .otherHip, .otherElbow, .otherShoulder, .otherWristHeight,
                                           .otherWristReach, .otherArmLength, .otherAnkleHeight, .otherKneeHeight]
    }

    enum Side: String, Codable, Sendable {
        case left, right, both
    }

    enum Position: String, Codable, Sendable {
        /// Standing, the hips staying at their height.
        case standing
        case seated
        /// Standing, the hips going down and back up.
        case mixed
    }

    /// Plane of the main movement, as far as a front camera can tell.
    enum Plane: String, Codable, Sendable {
        /// Sideways, seen as is from the front (abduction, side lunge).
        case frontal
        /// Forward or backward, seen foreshortened from the front (squat, leg raise, flexion).
        case sagittal
        case unknown
    }

    /// Low and high values of each channel over the movement (5th and 95th percentiles), by `Channel.rawValue`.
    var low: [Double]
    var high: [Double]
    var side: Side
    var position: Position
    var plane: Plane
    var repetitions: Int
    /// Seconds per repetition (median).
    var repDuration: Double
    /// Frames measured.
    var frames: Int

    func range(_ channel: Channel) -> Double { high[channel.rawValue] - low[channel.rawValue] }

    /// The channels that change the most, on a common scale: what the movement is about.
    var mainChannels: [Channel] {
        let ranked = Channel.allCases.sorted { range($0) / $0.scale > range($1) / $1.scale }
        guard let top = ranked.first else { return [] }
        let strongest = range(top) / top.scale
        return ranked.filter { range($0) / $0.scale >= strongest * 0.5 }.prefix(3).map { $0 }
    }

    /// The numbers compared with the catalog's signatures: what moves, in what proportions, then how much.
    /// Not the posture held meanwhile (a squat is a squat with the arms raised or down), and the shape before the
    /// size: a patient in rehabilitation often does a smaller movement than the recordings.
    var vector: [Double] {
        let ranges = Channel.allCases.map { range($0) / $0.scale }
        let size = sqrt(ranges.map { $0 * $0 }.reduce(0, +))
        guard size > 0 else { return ranges + [0] }
        return ranges.map { $0 / size } + [log(size) * 0.3]
    }

    // MARK: Measuring

    /// Frames per second the pose is measured at, in the app and in the conversion of the recordings.
    static let rate = 15.0

    /// Measures a movement from its frames (15 per second). Frames without a body are skipped.
    /// Returns nil when too few frames show the body.
    static func measure(_ frames: [PoseMeasure?], rate: Double = rate) -> MovementMeasurement? {
        let poses = frames.compactMap { $0 }
        guard poses.count >= 8 else { return nil }
        // The person's leg and arm lengths: the longest seen (a limb pointing at the camera looks shorter).
        func longest(_ a: (PoseMeasure) -> CGPoint?, _ b: (PoseMeasure) -> CGPoint?) -> Double {
            let lengths = poses.compactMap { m -> Double? in
                guard let p = a(m), let q = b(m) else { return nil }
                return hypot(Double(p.x - q.x), Double(p.y - q.y))
            }
            return lengths.count >= 4 ? percentile(lengths, 0.95) : 0
        }
        let leg = max(longest(\.leftHip, \.leftAnkle), longest(\.rightHip, \.rightAnkle))
        let arm = max(longest(\.leftShoulder, \.leftWrist), longest(\.rightShoulder, \.rightWrist))
        guard leg > 0, arm > 0 else { return nil }
        let size = Size(leg: leg, arm: arm)

        // Raw values per frame, left and right kept apart before ordering the sides.
        let left = poses.map { sideValues($0, left: true, size: size) }
        let right = poses.map { sideValues($0, left: false, size: size) }
        let shared = poses.map { sharedValues($0, size: size) }

        func spread(_ series: [[Double?]], _ index: Int) -> Double {
            let values = series.compactMap { $0[index] }
            guard values.count >= 4 else { return 0 }
            return percentile(values, 0.95) - percentile(values, 0.05)
        }
        let sideCount = left.first?.count ?? 0
        let leftActivity = (0..<sideCount).map { spread(left, $0) / sideScales[$0] }.reduce(0, +)
        let rightActivity = (0..<sideCount).map { spread(right, $0) / sideScales[$0] }.reduce(0, +)
        let leftIsActive = leftActivity > rightActivity
        let balance = min(leftActivity, rightActivity) / max(max(leftActivity, rightActivity), 0.0001)
        let side: Side = balance > 0.6 ? .both : (leftIsActive ? .left : .right)
        let active = leftIsActive ? left : right
        let other = leftIsActive ? right : left

        var series = Array(repeating: [Double](), count: Channel.allCases.count)
        for f in poses.indices {
            for (k, channel) in Channel.activeSide.enumerated() {
                if let value = active[f][k] { series[channel.rawValue].append(value) }
            }
            for (k, channel) in Channel.otherSide.enumerated() {
                if let value = other[f][k] { series[channel.rawValue].append(value) }
            }
            for (channel, value) in shared[f] {
                if let value { series[channel.rawValue].append(value) }
            }
        }
        let low = series.map { $0.count >= 4 ? percentile($0, 0.05) : 0 }
        let high = series.map { $0.count >= 4 ? percentile($0, 0.95) : 0 }

        var measurement = MovementMeasurement(low: low, high: high, side: side, position: .standing, plane: .unknown,
                                              repetitions: 0, repDuration: 0, frames: poses.count)
        measurement.position = position(hipsHeight: series[Channel.hipsHeight.rawValue])
        measurement.plane = plane(measurement)
        let (reps, duration) = repetitions(of: measurement, poses: poses, active: active, other: other,
                                           shared: shared, rate: rate)
        measurement.repetitions = reps
        measurement.repDuration = duration
        return measurement
    }

    /// Scales of the side measures, in `sideValues` order.
    private static let sideScales = Channel.activeSide.map(\.scale)

    private struct Size {
        let leg: Double
        let arm: Double
    }

    /// Knee, hip, elbow, shoulder angles; wrist height and reach; arm length; ankle and knee heights.
    private static func sideValues(_ m: PoseMeasure, left: Bool, size: Size) -> [Double?] {
        let hip = left ? m.leftHip : m.rightHip, knee = left ? m.leftKnee : m.rightKnee
        let ankle = left ? m.leftAnkle : m.rightAnkle, shoulder = left ? m.leftShoulder : m.rightShoulder
        let elbow = left ? m.leftElbow : m.rightElbow, wrist = left ? m.leftWrist : m.rightWrist
        func height(_ p: CGPoint?, from base: CGPoint?, _ unit: Double) -> Double? {
            guard let p, let base else { return nil }
            return Double(p.y - base.y) / unit
        }
        return [
            angle(hip, knee, ankle),
            angle(shoulder, hip, knee),
            angle(shoulder, elbow, wrist),
            angle(hip, shoulder, elbow),
            height(wrist, from: shoulder, size.arm),
            wrist.map { abs(Double($0.x - m.neck.x)) / size.arm },
            (shoulder != nil && wrist != nil) ? hypot(Double(wrist!.x - shoulder!.x), Double(wrist!.y - shoulder!.y)) / size.arm : nil,
            height(ankle, from: m.hips, size.leg),
            height(knee, from: m.hips, size.leg),
        ]
    }

    private static func sharedValues(_ m: PoseMeasure, size: Size) -> [(Channel, Double?)] {
        let ankles = [m.leftAnkle, m.rightAnkle].compactMap { $0 }
        let feet = ankles.isEmpty ? nil : CGPoint(x: ankles.map(\.x).reduce(0, +) / CGFloat(ankles.count),
                                                  y: ankles.map(\.y).reduce(0, +) / CGFloat(ankles.count))
        // The foot on the ground: a raised leg doesn't lower the hips.
        let ground = ankles.map(\.y).min()
        let lean = atan2(abs(Double(m.neck.x - m.hips.x)), Double(m.neck.y - m.hips.y)) * 180 / .pi
        return [
            (.hipsHeight, ground.map { Double(m.hips.y - $0) / size.leg }),
            (.hipsShift, feet.map { abs(Double(m.hips.x - $0.x)) / size.leg }),
            (.trunkLean, lean),
            (.stanceWidth, ankles.count == 2 ? hypot(Double(ankles[0].x - ankles[1].x), Double(ankles[0].y - ankles[1].y)) / size.leg : nil),
        ]
    }

    private static func angle(_ a: CGPoint?, _ b: CGPoint?, _ c: CGPoint?) -> Double? {
        guard let a, let b, let c else { return nil }
        let u = CGVector(dx: a.x - b.x, dy: a.y - b.y), v = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let lengths = hypot(u.dx, u.dy) * hypot(v.dx, v.dy)
        guard lengths > 0 else { return nil }
        return acos(max(-1, min(1, Double((u.dx * v.dx + u.dy * v.dy) / lengths)))) * 180 / .pi
    }

    /// Standing still (the hips about a leg's length above the feet), going down (squat, lunge, sitting down), or
    /// seated all along.
    private static func position(hipsHeight: [Double]) -> Position {
        guard hipsHeight.count >= 4 else { return .standing }
        let low = percentile(hipsHeight, 0.05), high = percentile(hipsHeight, 0.95)
        if high < 0.8 { return .seated }
        if low < 0.8 { return .mixed }
        return .standing
    }

    /// Sideways when the active wrist or the hips move sideways more than they shorten or rise.
    private static func plane(_ m: MovementMeasurement) -> Plane {
        let sideways = max(m.range(.activeWristReach), m.range(.hipsShift))
        let forward = max(m.range(.activeArmLength), m.range(.hipsHeight) * 0.6)
        guard max(sideways, forward) > 0.1 else { return .unknown }
        return sideways > forward ? .frontal : .sagittal
    }

    /// Repetitions of the main channel: from 20% of its span, back under 12%.
    private static func repetitions(of m: MovementMeasurement, poses: [PoseMeasure], active: [[Double?]],
                                    other: [[Double?]], shared: [[(Channel, Double?)]], rate: Double) -> (Int, Double) {
        guard let main = m.mainChannels.first else { return (0, 0) }
        let values: [Double?] = poses.indices.map { f in
            if let k = Channel.activeSide.firstIndex(of: main) { return active[f][k] }
            if let k = Channel.otherSide.firstIndex(of: main) { return other[f][k] }
            return shared[f].first { $0.0 == main }?.1 ?? nil
        }
        let low = m.low[main.rawValue], span = m.range(main)
        guard span > 0 else { return (0, 0) }
        // The rest is the end the movement starts from: the first frame's side of the span.
        let first = values.compactMap { $0 }.first ?? low
        let restIsLow = first - low < span / 2
        let progress = values.map { $0.map { restIsLow ? ($0 - low) / span : (m.high[main.rawValue] - $0) / span } }
        var count = 0, durations: [Double] = [], start: Int?
        for (f, value) in progress.enumerated() {
            guard let value else { continue }
            if let s = start {
                if value <= 0.12 {
                    count += 1
                    durations.append(Double(f - s) / rate)
                    start = nil
                }
            } else if value >= 0.2 {
                start = f
            }
        }
        // A recording that ends at the far end of the movement still did the repetition.
        if let s = start, progress.compactMap({ $0 }).max() ?? 0 > 0.8 {
            count += 1
            durations.append(Double(progress.count - s) / rate)
        }
        return (count, durations.isEmpty ? 0 : median(durations))
    }

    // MARK: Summary

    /// A compact summary, e.g. « genou (côté actif) 95°→170°, hauteur des hanches 1,1→2,0, plan sagittal, debout,
    /// 3 répétitions, 2,1 s par répétition ».
    var summary: String {
        let parts = mainChannels.map { channel -> String in
            let side = Channel.activeSide.contains(channel) && self.side != .both ? " (\(sideName))" : ""
            let format = channel.isAngle ? "%.0f°→%.0f°" : "%.1f→%.1f"
            return channel.label + side + " " + String(format: format, low[channel.rawValue], high[channel.rawValue])
        }
        let planeName = switch plane {
        case .frontal: "plan frontal"
        case .sagittal: "plan sagittal"
        case .unknown: "plan indéterminé"
        }
        let positionName = switch position {
        case .standing: "debout"
        case .seated: "assis"
        case .mixed: "debout, avec descente"
        }
        return (parts + [planeName, positionName, "\(repetitions) répétition(s)",
                         String(format: "%.1f s par répétition", repDuration)]).joined(separator: ", ")
    }

    private var sideName: String {
        switch side {
        case .left: "gauche"
        case .right: "droit"
        case .both: "les deux côtés"
        }
    }

    // MARK: Helpers

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let position = p * Double(sorted.count - 1)
        let i = Int(position), fraction = position - Double(i)
        return i + 1 < sorted.count ? sorted[i] + (sorted[i + 1] - sorted[i]) * fraction : sorted[i]
    }

    static func median(_ values: [Double]) -> Double { percentile(values, 0.5) }
}
