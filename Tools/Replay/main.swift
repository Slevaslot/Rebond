import Foundation
import simd

// Replays UI-PRMD Kinect repetitions through the app's real counters, seen from the front.
// usage: replay <root of correct or incorrect> <c|i> <movement 1|2|3|4|5|6|7|9|10> <target> [verbose]
// Environment: PERSP=<cm> phone distance (default 250, 0 = orthographic), DIAG=1 measure distributions,
// DEBUG=sXXeYY frame-by-frame trace of one repetition, ORDER=<zxy…> Euler order (see kinect.swift).
let a = CommandLine.arguments
let root = a[1], suffix = a[2] == "c" ? "" : "_inc", movement = Int(a[3])!, target = Double(a[4])!
let verbose = a.count > 5

func mid(_ p: SIMD3<Double>, _ q: SIMD3<Double>) -> SIMD3<Double> { (p + q) / 2 }
/// Front view, as Vision would see it: x lateral, y up. Kinect cm scaled to roughly image-height units.
/// Vision's root and neck are the middles of the hips and of the shoulders.
/// Phone distance in cm (PERSP, default 250): perspective projection from a camera at the standing hip height,
/// in front of the patient, as in the app. PERSP=0 keeps the orthographic view.
let distance = Double(ProcessInfo.processInfo.environment["PERSP"] ?? "250")!
var camera = SIMD3<Double>(0, 0, 0)
func measure(_ j: [SIMD3<Double>]) -> PoseMeasure {
    func p(_ v: SIMD3<Double>) -> CGPoint {
        guard distance > 0 else { return CGPoint(x: v.x / 200, y: v.y / 200) }
        let depth = camera.z - v.z
        return CGPoint(x: (v.x - camera.x) / depth + 1, y: (v.y - camera.y) / depth + 1)
    }
    return PoseMeasure(
        hips: p(mid(j[14], j[18])), neck: p(mid(j[7], j[11])),
        leftHip: p(j[14]), rightHip: p(j[18]), leftKnee: p(j[15]), rightKnee: p(j[19]),
        leftAnkle: p(j[16]), rightAnkle: p(j[20]),
        leftShoulder: p(j[7]), rightShoulder: p(j[11]), leftElbow: p(j[8]), rightElbow: p(j[12]),
        leftWrist: p(j[9]), rightWrist: p(j[13])
    )
}

/// One counter per UI-PRMD movement: add a case here for a new exercise.
func makeCounter() -> any MovementCounter {
    switch movement {
    case 1: RepCounter(targetDepth: target)
    case 3: LungeCounter(direction: .forward, target: target)
    case 4: LungeCounter(direction: .side, target: target)
    case 5: SitToStandCounter(targetRise: target)
    case 2: LegRaiseCounter(targetLift: target, style: .bentKnee)
    case 6: LegRaiseCounter(targetLift: target)
    case 9: ShoulderRotationCounter(targetTurn: target)
    default: ArmRaiseCounter(targetAngle: target, arms: .either)
    }
}

var counted = 0, incomplete = 0, total = 0, silent = 0
var faults: [String: Int] = [:]
var diag: [String: [Double]] = [:]
for s in 1...10 { for e in 1...10 {
    guard let skeleton = load(root, movement, s, e, suffix) else { continue }
    let standing = skeleton.max { mid($0[14], $0[18]).y < mid($1[14], $1[18]).y }!
    let restHips = mid(skeleton[0][14], skeleton[0][18])
    camera = SIMD3(restHips.x, mid(standing[14], standing[18]).y, restHips.z + distance)
    var frames = stride(from: 0, to: skeleton.count, by: 2).map { measure(skeleton[$0]) }
    if movement == 5 {
        // UI-PRMD goes standing → seated → standing; the app starts seated: replay from the seated moment.
        let seated = frames.indices.min { frames[$0].hips.y < frames[$1].hips.y }!
        frames = Array(frames[seated...] + frames[..<seated])
    }
    // 1 s still at both ends, so the counter can calibrate and finish.
    frames = Array(repeating: frames.first!, count: 15) + frames + Array(repeating: frames.last!, count: 15)
    var counter = makeCounter()
    // Diagnostics against the first (resting) frame, in resting torso lengths.
    let f0 = frames[0], t0 = f0.torsoLength
    let lean0 = (f0.neck.x - f0.hips.x) / t0
    diag["hipsDrop", default: []].append(frames.map { (f0.hips.y - $0.hips.y) / t0 }.max()!)
    diag["hipsRise", default: []].append(frames.map { ($0.hips.y - f0.hips.y) / t0 }.max()!)
    diag["sideLean", default: []].append(frames.map { abs(($0.neck.x - $0.hips.x) / $0.torsoLength - lean0) }.max()!)
    diag["torsoRatioMin", default: []].append(frames.map { $0.torsoLength / t0 }.min()!)
    if movement == 6 {
        // Raised leg: the one whose knee rises most.
        let lk = frames.map { ($0.leftKnee!.y - f0.leftKnee!.y) / t0 }, rk = frames.map { ($0.rightKnee!.y - f0.rightKnee!.y) / t0 }
        let left = lk.max()! > rk.max()!
        let kneeRise = left ? lk : rk
        let ankleRise = frames.map { ((left ? $0.leftAnkle! : $0.rightAnkle!).y - (left ? f0.leftAnkle! : f0.rightAnkle!).y) / t0 }
        func shin(_ m: PoseMeasure) -> Double { left ? hypot(m.leftKnee!.x - m.leftAnkle!.x, m.leftKnee!.y - m.leftAnkle!.y) : hypot(m.rightKnee!.x - m.rightAnkle!.x, m.rightKnee!.y - m.rightAnkle!.y) }
        let peak = kneeRise.indices.max { kneeRise[$0] < kneeRise[$1] }!
        diag["kneeRise", default: []].append(kneeRise[peak])
        diag["ankleRise", default: []].append(ankleRise.max()!)
        diag["ankleRise@kneePeak", default: []].append(ankleRise[peak])
        diag["shinRatio@kneePeak", default: []].append(shin(frames[peak]) / shin(f0))
    }
    diag["hipsShiftX", default: []].append(frames.map { abs($0.hips.x - f0.hips.x) / t0 }.max()!)
    var events: [String] = []
    var maxProgress = 0.0
    var any = false
    for (k, m) in frames.enumerated() {
        let u = counter.process(m, at: Double(k) / 15)
        maxProgress = max(maxProgress, u.progress)
        if ProcessInfo.processInfo.environment["DEBUG"] == String(format: "s%02de%02d", s, e) {
            let arms = ArmRaiseCounter.arms(in: m)
            let t = m.torsoLength
            print(m.kneeAngles.map { String(format: "%.0f", $0) }.joined(separator: "/"), terminator: " ")
            print(String(format: "%3d p=%.2f L=%.0f R=%.0f hipsY=%.2f lean=%.3f torso=%.3f | kneeY L %.2f R %.2f ankleY L %.2f R %.2f", k, u.progress, arms?.left.angle ?? -1, arms?.right.angle ?? -1, m.hips.y / t, (m.neck.x - m.hips.x) / t, t, m.leftKnee!.y / t, m.rightKnee!.y / t, m.leftAnkle!.y / t, m.rightAnkle!.y / t), u.event.map { "\($0)" } ?? "")
        }
        if let ev = u.event {
            switch ev {
            case .calibrated: events.append("cal")
            case .bottomReached: break
            case .repCompleted(let r): counted += 1; any = true; events.append(String(format: "OK %.2f%@", r.amplitude, r.tooFast ? " fast" : ""))
            case .repIncomplete(let d): incomplete += 1; any = true; events.append(String(format: "INCOMPLETE %.2f", d))
            case .correction(let c): faults["\(c)", default: 0] += 1; any = true; events.append("\(c)")
            }
        }
    }
    if !any { silent += 1 }
    total += 1
    if verbose {
        print(String(format: "s%02d e%02d n=%3d maxProgress=%.2f ", s, e, frames.count, maxProgress) + events.joined(separator: ", "))
    }
}}
if ProcessInfo.processInfo.environment["DIAG"] != nil {
    for (name, values) in diag.sorted(by: { $0.key < $1.key }) {
        let v = values.sorted()
        print(name, [0.0, 0.1, 0.5, 0.9, 1.0].map { String(format: "%.2f", v[min(v.count - 1, Int($0 * Double(v.count)))]) }.joined(separator: " "))
    }
}
print(String(format: "m%02d %@ target %.2f: %d reps, counted %d (%.0f%%), incomplete %d, silent %d, faults %@",
             movement, suffix.isEmpty ? "correct" : "incorrect", target, total, counted, Double(counted) / Double(total) * 100, incomplete, silent, faults.description))
