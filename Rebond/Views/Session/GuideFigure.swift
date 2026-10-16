import CoreGraphics
import Vision

/// The movement pictogram's body at one moment of the movement, in points: a torso along the spine, a head,
/// and limbs made of segments. Built from two guide poses (rest and target) and cleaned up on the way, so any
/// pose gives a sane figure: missing joints are made up from their neighbours, crossed hips or shoulders keep
/// a torso of normal width, limbs keep a plausible length, and the torso never leans more than 45°.
/// Pure geometry, without SwiftUI: `MovementGuide` turns it into a single contour.
nonisolated struct GuideFigure: Equatable, Sendable {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    /// How the figure is seen. The camera sees the patient from the front; a movement done toward the camera
    /// (a knee or a leg raised in front, a forward lunge) reads better from the side.
    enum View: Sendable {
        case front
        /// From the side, facing right: the arms and legs start from the middle of the torso, with feet.
        case profile
    }

    /// A straight piece of limb with round ends. `endWidth` is larger than `width` when the end comes
    /// toward the camera: seen from the front, the hand of the forearm pointing at the camera grows.
    struct Segment: Equatable, Sendable {
        var start: CGPoint
        var end: CGPoint
        var width: CGFloat
        var endWidth: CGFloat
    }

    /// Torso: a rounded rectangle centered on `torsoCenter`, `torsoSize.height` long along the spine,
    /// turned by `torsoAngle` (radians, 0 upright, positive leaning right).
    var torsoCenter: CGPoint
    var torsoSize: CGSize
    var torsoAngle: CGFloat
    var torsoCornerRadius: CGFloat
    var head: CGPoint
    var headRadius: CGFloat
    var neck: Segment
    var limbs: [Segment]
    /// A chair, for the exercises that start seated: lines (legs, seat, backrest from the side).
    var chair: [[CGPoint]]
    var chairWidth: CGFloat

    /// Every point of the figure, to check it stays sane.
    var points: [CGPoint] {
        [torsoCenter, head, neck.start, neck.end] + limbs.flatMap { [$0.start, $0.end] } + chair.flatMap { $0 }
    }

    // MARK: - Proportions, in figure heights

    static let limbWidth = 0.075
    static let armWidth = limbWidth * 0.8
    static let headRadiusRatio = 0.065
    /// Hips span (between the hip joints): from the side, the torso keeps this minimum thickness.
    static let minimumHipSpan = 0.06
    static let maximumHipSpan = 0.2
    static let torsoLengthRange = 0.18...0.42
    /// The torso leans at most this much (radians) from upright: more is an error of the pose.
    static let maximumLean = Double.pi / 6
    static let maximumUpperLimb = 0.22
    static let maximumLowerLimb = 0.28
    /// Shoulder to hand without an elbow.
    static let maximumArm = 0.36
    /// A hand or a foot nearer its shoulder or hip than this is an error of the pose: the limb hangs instead.
    static let minimumArm = 0.08
    static let minimumLeg = 0.2
    /// A hand or a foot moving less than this stays planted: it follows a straight line instead of an arc.
    static let plantedDistance = 0.04
    static let footLength = 0.075

    /// The figure between `rest` (progress 0) and `target` (progress 1), in `box` (points in the poses are
    /// fractions of the box, origin top-left).
    init(rest: GuidePose, target: GuidePose, armStyle: CatalogExercise.ArmStyle, progress: Double, in box: CGRect,
         view: View = .front) {
        // A detection can mix up the sides (crossed hips of a body turning, a leg seen on the other side): each limb
        // then starts from the side of the body where it is at rest, instead of crossing the body.
        let crossings = (arms: Self.isCrossed(rest, Self.armPairs), legs: Self.isCrossed(rest, Self.legPairs))
        let rest = Self.sorted(rest, crossings)
        let target = Self.sorted(target, crossings)
        let height = box.height
        let t = progress.isFinite ? min(max(progress, 0), 1) : 0
        let limb = height * Self.limbWidth
        let arm = height * Self.armWidth

        func place(_ pose: GuidePose, _ joint: Joint) -> CGPoint? {
            guard let point = pose[joint], point.x.isFinite, point.y.isFinite else { return nil }
            return CGPoint(x: box.minX + min(max(point.x, -0.3), 1.3) * box.width,
                           y: box.minY + min(max(point.y, -0.3), 1.3) * box.height)
        }

        // The torso of each pose, then in between.
        let restTorso = Torso(pose: rest, place: place, height: height, box: box)
        let targetTorso = Torso(pose: target, place: place, height: height, box: box)
        let torso = restTorso.mixed(with: targetTorso, t)
        let frame = torso.frame(limb: limb)

        torsoCenter = frame.center
        torsoSize = CGSize(width: frame.width, height: frame.length)
        torsoAngle = atan2(torso.up.dx, -torso.up.dy)
        torsoCornerRadius = arm / 2

        // Head above the torso, along the spine, joined by a short neck.
        headRadius = height * Self.headRadiusRatio
        head = frame.top + torso.up * (height * 0.02 + headRadius)
        neck = Segment(start: head, end: frame.top - torso.up * arm, width: headRadius * 0.9, endWidth: headRadius * 0.9)

        var limbs: [Segment] = []
        // The floor: where the resting pose's feet are.
        let floor = [place(rest, .leftAnkle), place(rest, .rightAnkle)].compactMap { $0?.y }.max() ?? box.minY + 0.95 * height
        let sides: [(side: CGFloat, shoulder: Joint, elbow: Joint, wrist: Joint, hip: Joint, knee: Joint, ankle: Joint)] = [
            (-1, .leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle),
            (1, .rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightKnee, .rightAnkle),
        ]

        // Arms.
        for side in sides {
            func anchor(_ torso: Torso) -> CGPoint {
                torso.frame(limb: limb).shoulderAnchor(offset: torso.shoulderOffset(side.side), arm: arm)
            }
            switch armStyle {
            case .straight:
                // A hand missing from both poses hangs along the body.
                let hanging = CGVector(dx: side.side * height * 0.06, dy: height * 0.3)
                limbs += Self.chain(
                    anchors: (anchor(restTorso), anchor(targetTorso), anchor(torso)),
                    middle: (place(rest, side.elbow), place(target, side.elbow)),
                    end: (place(rest, side.wrist), place(target, side.wrist)),
                    fallback: hanging, minimum: Self.minimumArm * height,
                    maximum: (Self.maximumUpperLimb * height, Self.maximumUpperLimb * height, Self.maximumArm * height),
                    width: arm, t: t, height: height)
            case .handsToChest:
                limbs += Self.handsToChest(side: side.side, wrist: side.wrist, rest: rest, place: place,
                                           restTorso: restTorso, torso: torso, limb: limb, arm: arm, t: t, height: height)
            }
        }

        // Legs.
        for side in sides {
            func anchor(_ torso: Torso) -> CGPoint {
                torso.frame(limb: limb).hipAnchor(offset: torso.hipOffset(side.side), limb: limb)
            }
            let legs = Self.chain(
                anchors: (anchor(restTorso), anchor(targetTorso), anchor(torso)),
                middle: (place(rest, side.knee), place(target, side.knee)),
                end: (place(rest, side.ankle), place(target, side.ankle)),
                fallback: CGVector(dx: 0, dy: height * 0.45), minimum: Self.minimumLeg * height,
                maximum: (Self.maximumLowerLimb * height, Self.maximumLowerLimb * height, 2 * Self.maximumLowerLimb * height),
                width: limb, t: t, height: height)
            limbs += legs
            // From the side, a foot shows which way the figure faces: square to the shin, toward the front,
            // but never through the floor: a raised heel puts the toes down on it.
            if view == .profile, let shin = legs.last {
                let length = height * Self.footLength
                let along = (shin.end - shin.start).unit
                var foot = CGVector(dx: -along.dy, dy: along.dx)
                if foot.dx < 0 { foot = foot * -1 }
                let above = floor - shin.end.y
                if foot.dy > 0, foot.dy * length > above {
                    let drop = min(max(above, 0), length * 0.8)
                    foot = CGVector(dx: sqrt(length * length - drop * drop), dy: drop).unit
                }
                limbs.append(Segment(start: shin.end, end: shin.end + foot * length,
                                     width: limb * 0.8, endWidth: limb * 0.8))
            }
        }
        self.limbs = limbs

        // The chair stays where the resting pose puts it: the figure sits on it, then stands in front of it.
        if let seat = place(rest, .guideChairSeat) {
            switch view {
            case .front:
                // Seen from the front: a seat wider than the figure, with its two legs.
                let half = box.width * 0.36
                chair = [[CGPoint(x: seat.x - half, y: floor), CGPoint(x: seat.x - half, y: seat.y),
                          CGPoint(x: seat.x + half, y: seat.y), CGPoint(x: seat.x + half, y: floor)]]
            case .profile:
                // From the side: the backrest behind the figure, the seat under its thighs, two legs.
                let depth = height * 0.11
                let back = seat.x - depth, front = seat.x + depth
                chair = [[CGPoint(x: back, y: seat.y - height * 0.26), CGPoint(x: back, y: floor)],
                         [CGPoint(x: back, y: seat.y), CGPoint(x: front, y: seat.y), CGPoint(x: front, y: floor)]]
            }
        } else {
            chair = []
        }
        chairWidth = arm * 0.8
    }

    // MARK: - Limbs

    /// A limb from its anchor on the torso, through an optional middle joint (elbow, knee), to its end (hand, foot).
    /// A planted end (feet during a squat) moves in a straight line, the rest of the limb following; a moving end
    /// turns around the anchor in an arc, each segment keeping its length, as a real arm or leg does.
    private static func chain(
        anchors: (rest: CGPoint, target: CGPoint, now: CGPoint),
        middle: (rest: CGPoint?, target: CGPoint?),
        end: (rest: CGPoint?, target: CGPoint?),
        fallback: CGVector, minimum: CGFloat, maximum: (upper: CGFloat, lower: CGFloat, whole: CGFloat),
        width: CGFloat, t: Double, height: CGFloat
    ) -> [Segment] {
        // Ends: the other pose's when one is missing or too near its anchor, hanging from the anchor when both are.
        func usable(_ end: CGPoint?, _ anchor: CGPoint) -> CGPoint? {
            end.flatMap { ($0 - anchor).length >= minimum ? $0 : nil }
        }
        var middle = middle
        let usableRest = usable(end.rest, anchors.rest), usableTarget = usable(end.target, anchors.target)
        if usableRest == nil { middle.rest = nil }
        if usableTarget == nil { middle.target = nil }
        let endRest = usableRest ?? usableTarget.map { anchors.rest + ($0 - anchors.target) } ?? anchors.rest + fallback
        let endTarget = usableTarget ?? usableRest.map { anchors.target + ($0 - anchors.rest) } ?? anchors.target + fallback
        let planted = (endTarget - endRest).length < plantedDistance * height
        let t = CGFloat(t)

        guard middle.rest != nil || middle.target != nil else {
            // One straight segment.
            let restVector = (endRest - anchors.rest).clamped(to: maximum.whole)
            let targetVector = (endTarget - anchors.target).clamped(to: maximum.whole)
            let vector = planted
                ? (anchors.rest + restVector).mixed(with: anchors.target + targetVector, t) - anchors.now
                : restVector.turned(toward: targetVector, t)
            return [Segment(start: anchors.now, end: anchors.now + vector, width: width,
                            endWidth: width * taper(vector, restVector, targetVector, planted: planted))]
        }

        // A missing middle joint: halfway along the limb of that pose.
        let middleRest = middle.rest ?? anchors.rest.mixed(with: endRest, 0.5)
        let middleTarget = middle.target ?? anchors.target.mixed(with: endTarget, 0.5)
        let upperRest = (middleRest - anchors.rest).clamped(to: maximum.upper)
        let upperTarget = (middleTarget - anchors.target).clamped(to: maximum.upper)
        let lowerRest = (endRest - (anchors.rest + upperRest)).clamped(to: maximum.lower)
        let lowerTarget = (endTarget - (anchors.target + upperTarget)).clamped(to: maximum.lower)

        let middleNow: CGPoint, endNow: CGPoint, lower: CGVector
        if planted {
            middleNow = (anchors.rest + upperRest).mixed(with: anchors.target + upperTarget, t)
            endNow = (anchors.rest + upperRest + lowerRest).mixed(with: anchors.target + upperTarget + lowerTarget, t)
            lower = endNow - middleNow
        } else {
            middleNow = anchors.now + upperRest.turned(toward: upperTarget, t)
            lower = lowerRest.turned(toward: lowerTarget, t)
            endNow = middleNow + lower
        }
        return [
            Segment(start: anchors.now, end: middleNow, width: width, endWidth: width),
            Segment(start: middleNow, end: endNow, width: width,
                    endWidth: width * taper(lower, lowerRest, lowerTarget, planted: planted)),
        ]
    }

    /// How much wider the end of a segment is drawn: seen from the front, a forearm that turns toward the camera
    /// looks shorter, and its hand, closer, looks bigger.
    private static func taper(_ now: CGVector, _ rest: CGVector, _ target: CGVector, planted: Bool) -> CGFloat {
        guard !planted else { return 1 }
        let full = max(rest.length, target.length)
        guard full > 0 else { return 1 }
        let shortening = now.length / full
        return 1 + 0.7 * min(max((0.85 - shortening) / 0.6, 0), 1)
    }

    /// Arms straight when standing; going down, the elbows bend and the hands come together in front of the chest.
    /// Upper arm and forearm keep their length.
    private static func handsToChest(
        side: CGFloat, wrist: Joint, rest: GuidePose, place: (GuidePose, Joint) -> CGPoint?,
        restTorso: Torso, torso: Torso, limb: CGFloat, arm: CGFloat, t: Double, height: CGFloat
    ) -> [Segment] {
        let standingFrame = restTorso.frame(limb: limb)
        let frame = torso.frame(limb: limb)
        let standingStart = standingFrame.shoulderAnchor(offset: restTorso.shoulderOffset(side), arm: arm)
        let standingHand = place(rest, wrist) ?? standingStart + CGVector(dx: side * height * 0.06, dy: height * 0.3)
        let straight = (standingHand - standingStart).clamped(to: 2 * maximumUpperLimb * height)
        let segment = straight.length / 2
        let start = frame.shoulderAnchor(offset: torso.shoulderOffset(side), arm: arm)
        guard segment > 0 else { return [] }

        // At the bottom: hands joined in front of the chest, elbows out and down.
        let chest = frame.top - torso.up * (frame.length * 0.3)
        let reach = min((chest - start).length, segment * 2 * 0.999)
        let toChest = (chest - start).unit
        let bend = sqrt(max(0, segment * segment - reach * reach / 4))
        var normal = CGVector(dx: -toChest.dy, dy: toChest.dx)
        if normal.dot(frame.right) * side < 0 { normal = normal * -1 }
        let bottomElbow = start + toChest * (reach / 2) + normal * bend
        let bottomUpper = (bottomElbow - start).unit
        let bottomFore = (chest - bottomElbow).unit

        // In between, each segment turns smoothly from straight to bent.
        let t = CGFloat(t)
        let upper = straight.unit.mixed(with: bottomUpper, t).unit
        let fore = straight.unit.mixed(with: bottomFore, t).unit
        let elbow = start + upper * segment
        let hand = elbow + fore * segment
        return [
            Segment(start: start, end: elbow, width: arm, endWidth: arm),
            Segment(start: elbow, end: hand, width: arm, endWidth: arm),
        ]
    }
}

// MARK: - Sides

nonisolated extension GuideFigure {
    private static let armPairs: [(Joint, Joint)] = [(.leftShoulder, .rightShoulder), (.leftElbow, .rightElbow), (.leftWrist, .rightWrist)]
    private static let legPairs: [(Joint, Joint)] = [(.leftKnee, .rightKnee), (.leftAnkle, .rightAnkle)]

    /// Whether the left limb is clearly right of the right one (seen from the front), judged on its joints after
    /// the shoulder or hip.
    static func isCrossed(_ pose: GuidePose, _ pairs: [(Joint, Joint)]) -> Bool {
        let limb = pairs.count > 2 ? Array(pairs.dropFirst()) : pairs
        let left = limb.compactMap { pose[$0.0]?.x }, right = limb.compactMap { pose[$0.1]?.x }
        guard !left.isEmpty, left.count == right.count, left.allSatisfy(\.isFinite), right.allSatisfy(\.isFinite)
        else { return false }
        return left.reduce(0, +) / Double(left.count) > right.reduce(0, +) / Double(right.count) + 0.02
    }

    static func sorted(_ pose: GuidePose, _ crossings: (arms: Bool, legs: Bool)) -> GuidePose {
        var result = pose
        for (left, right) in (crossings.arms ? armPairs : []) + (crossings.legs ? legPairs : []) {
            result[left] = pose[right]
            result[right] = pose[left]
        }
        return result
    }
}

// MARK: - Torso

nonisolated extension GuideFigure {
    /// The torso of a pose: where the hips are, which way the spine goes, how wide the hips are,
    /// and where each shoulder and hip sits across it.
    struct Torso {
        var hips: CGPoint
        var up: CGVector
        var length: CGFloat
        var hipSpan: CGFloat
        /// Across the spine, toward the right of the screen: left then right shoulder, left then right hip.
        var shoulders: (left: CGFloat, right: CGFloat)
        var hipJoints: (left: CGFloat, right: CGFloat)

        init(pose: GuidePose, place: (GuidePose, Joint) -> CGPoint?, height: CGFloat, box: CGRect) {
            let leftShoulder = place(pose, .leftShoulder), rightShoulder = place(pose, .rightShoulder)
            let leftHip = place(pose, .leftHip), rightHip = place(pose, .rightHip)
            // One shoulder or one hip missing: the middle is above or below the other pair's middle.
            let shoulderPair = CGPoint.middle(of: [leftShoulder, rightShoulder])
            let hipPair = CGPoint.middle(of: [leftHip, rightHip])
            func middle(_ a: CGPoint?, _ b: CGPoint?, pair: CGPoint?, other: CGPoint?) -> CGPoint? {
                guard let pair else { return nil }
                guard a == nil || b == nil, let other else { return pair }
                return CGPoint(x: other.x, y: pair.y)
            }
            let shoulderCenter = middle(leftShoulder, rightShoulder, pair: shoulderPair, other: hipPair)
            let hipCenter = middle(leftHip, rightHip, pair: hipPair, other: shoulderPair)
            let standing = CGVector(dx: 0, dy: -height * 0.3)

            // Without hips or shoulders, the standing figure's torso, in the middle of the box.
            let hips = hipCenter ?? shoulderCenter.map { $0 - standing }
                ?? CGPoint(x: box.midX, y: box.minY + height * 0.5)
            var spine = shoulderCenter.map { $0 - hips } ?? standing
            // Nearly upright, and of a plausible length: a shoulder seen below the hips, or a body lying flat,
            // is an error of the pose.
            let range = GuideFigure.torsoLengthRange
            let length = min(max(spine.length, range.lowerBound * height), range.upperBound * height)
            if spine.length < 0.001 || spine.dy >= 0 {
                spine = standing
            } else {
                let lean = atan2(spine.dx, -spine.dy)
                let limit = GuideFigure.maximumLean
                if abs(lean) > limit {
                    let clamped = lean > 0 ? limit : -limit
                    spine = CGVector(dx: sin(clamped), dy: -cos(clamped))
                }
            }
            self.hips = hips
            up = spine.unit
            self.length = length

            let right = CGVector(dx: -up.dy, dy: up.dx)
            func across(_ point: CGPoint?, from center: CGPoint?) -> CGFloat? {
                guard let point, let center else { return nil }
                return (point - center).dot(right)
            }
            // The hips' width, whatever their order: crossed hips (a body turning) keep a normal torso.
            let span = (leftHip.flatMap { left in rightHip.map { abs(($0 - left).dot(right)) } }) ?? height * 0.104
            hipSpan = min(max(span, GuideFigure.minimumHipSpan * height), GuideFigure.maximumHipSpan * height)
            let shoulderDefault = height * 0.09
            // Left one on the left: crossed shoulders or hips don't cross the limbs.
            let shoulderOffsets = [across(leftShoulder, from: shoulderCenter) ?? -shoulderDefault,
                                   across(rightShoulder, from: shoulderCenter) ?? shoulderDefault]
            let hipOffsets = [across(leftHip, from: hipCenter) ?? -hipSpan / 2, across(rightHip, from: hipCenter) ?? hipSpan / 2]
            shoulders = (shoulderOffsets.min()!, shoulderOffsets.max()!)
            hipJoints = (hipOffsets.min()!, hipOffsets.max()!)
        }

        func shoulderOffset(_ side: CGFloat) -> CGFloat { side < 0 ? shoulders.left : shoulders.right }
        func hipOffset(_ side: CGFloat) -> CGFloat { side < 0 ? hipJoints.left : hipJoints.right }

        func mixed(with other: Torso, _ t: Double) -> Torso {
            let t = CGFloat(t)
            var result = self
            result.hips = hips.mixed(with: other.hips, t)
            result.up = up.turned(toward: other.up, t).unit
            result.length = length + (other.length - length) * t
            result.hipSpan = hipSpan + (other.hipSpan - hipSpan) * t
            result.shoulders = (shoulders.left + (other.shoulders.left - shoulders.left) * t,
                                shoulders.right + (other.shoulders.right - shoulders.right) * t)
            result.hipJoints = (hipJoints.left + (other.hipJoints.left - hipJoints.left) * t,
                                hipJoints.right + (other.hipJoints.right - hipJoints.right) * t)
            return result
        }

        func frame(limb: CGFloat) -> Frame {
            Frame(hips: hips, up: up, length: length, width: hipSpan + limb, limb: limb)
        }
    }

    /// The torso drawn: as wide as the hips plus a leg, from the shoulders' height to just under the hips.
    struct Frame {
        let hips: CGPoint
        let up: CGVector
        let spine: CGFloat
        let width: CGFloat
        let limb: CGFloat

        init(hips: CGPoint, up: CGVector, length: CGFloat, width: CGFloat, limb: CGFloat) {
            self.hips = hips
            self.up = up
            spine = length
            self.width = width
            self.limb = limb
        }

        var right: CGVector { CGVector(dx: -up.dy, dy: up.dx) }
        var top: CGPoint { hips + up * spine }
        var bottom: CGPoint { hips - up * (limb / 2) }
        var length: CGFloat { spine + limb / 2 }
        var center: CGPoint { top.mixed(with: bottom, 0.5) }

        /// Where an arm starts: at a top corner of the torso, or nearer the middle when the shoulders are
        /// (seen from the side).
        func shoulderAnchor(offset: CGFloat, arm: CGFloat) -> CGPoint {
            let limit = max(0, width / 2 - arm / 2)
            return top + right * min(max(offset, -limit), limit) - up * (arm / 2)
        }

        /// Where a leg starts: under its hip, inside the torso.
        func hipAnchor(offset: CGFloat, limb: CGFloat) -> CGPoint {
            let limit = max(0, width / 2 - limb / 2)
            return hips + up * (limb / 2) + right * min(max(offset, -limit), limit)
        }
    }
}

// MARK: - Following the patient

/// A position on screen that follows the patient without shaking (the outline standing on their feet):
/// a one-frame error of the detection is dropped (median of the last frames), small wobbles are ignored,
/// a real move is followed smoothly. When the feet aren't seen, it stays where it was.
nonisolated struct GuideAnchor: Equatable, Sendable {
    private(set) var value: Double?
    private var recent: [Double] = []
    private var isMoving = false

    /// - Parameter tolerance: moves smaller than this, in the same unit, are ignored.
    mutating func update(_ measured: Double?, tolerance: Double) {
        guard let measured, measured.isFinite else { return }
        recent.append(measured)
        if recent.count > 5 { recent.removeFirst() }
        let median = recent.sorted()[recent.count / 2]
        guard let current = value else {
            value = median
            return
        }
        if abs(median - current) > tolerance { isMoving = true }
        guard isMoving else { return }
        let next = current + (median - current) * 0.3
        value = next
        if abs(median - next) < tolerance * 0.1 { isMoving = false }
    }
}

// MARK: - Vector helpers

fileprivate nonisolated extension CGPoint {
    static func + (point: CGPoint, vector: CGVector) -> CGPoint { CGPoint(x: point.x + vector.dx, y: point.y + vector.dy) }
    static func - (point: CGPoint, vector: CGVector) -> CGPoint { CGPoint(x: point.x - vector.dx, y: point.y - vector.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }

    func mixed(with other: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }

    /// The middle of the points given, or nil if none is.
    static func middle(of points: [CGPoint?]) -> CGPoint? {
        let points = points.compactMap { $0 }
        guard !points.isEmpty else { return nil }
        return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                       y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }
}

fileprivate nonisolated extension CGVector {
    static func * (vector: CGVector, scale: CGFloat) -> CGVector { CGVector(dx: vector.dx * scale, dy: vector.dy * scale) }

    var length: CGFloat { hypot(dx, dy) }
    var unit: CGVector {
        let length = max(self.length, 0.0001)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    func dot(_ other: CGVector) -> CGFloat { dx * other.dx + dy * other.dy }

    func mixed(with other: CGVector, _ t: CGFloat) -> CGVector {
        CGVector(dx: dx + (other.dx - dx) * t, dy: dy + (other.dy - dy) * t)
    }

    /// No longer than `maximum`.
    func clamped(to maximum: CGFloat) -> CGVector {
        length > maximum ? unit * maximum : self
    }

    /// Turned the short way toward `other` and stretched toward its length: a limb moving in an arc.
    func turned(toward other: CGVector, _ t: CGFloat) -> CGVector {
        let from = length, to = other.length
        guard from > 0.0001, to > 0.0001 else { return mixed(with: other, t) }
        var turn = atan2(other.dy, other.dx) - atan2(dy, dx)
        if turn > .pi { turn -= 2 * .pi }
        if turn < -.pi { turn += 2 * .pi }
        let angle = atan2(dy, dx) + turn * t
        let size = from + (to - from) * t
        return CGVector(dx: cos(angle) * size, dy: sin(angle) * size)
    }
}
