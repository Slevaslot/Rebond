import Foundation
import simd

// UI-PRMD Kinect: 22 joints, positions relative to parent, Euler angles (degrees). Conversion copied from uiprmd_data.py.
// Joints: 0 waist, 1 spine, 2 chest, 3 neck, 4 head, 5 head tip, 6 L collar, 7 L shoulder, 8 L elbow, 9 L wrist,
// 10 R collar, 11 R shoulder, 12 R elbow, 13 R wrist, 14 L hip, 15 L knee, 16 L ankle, 17 L foot, 18 R hip, 19 R knee, 20 R ankle, 21 R foot.
func rot(_ e: SIMD3<Double>) -> simd_double3x3 {
    let (x, y, z) = (e.x * .pi / 180, e.y * .pi / 180, e.z * .pi / 180)
    let rx = simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cos(x), -sin(x)), SIMD3(0, sin(x), cos(x))])
    let ry = simd_double3x3(rows: [SIMD3(cos(y), 0, sin(y)), SIMD3(0, 1, 0), SIMD3(-sin(y), 0, cos(y))])
    let rz = simd_double3x3(rows: [SIMD3(cos(z), -sin(z), 0), SIMD3(sin(z), cos(z), 0), SIMD3(0, 0, 1)])
    // BVH convention (Zrotation Xrotation Yrotation): the order of uiprmd_data.py (z*y*x) flips raised legs at ~90°.
    switch ProcessInfo.processInfo.environment["ORDER"] ?? "zxy" {
    case "zyx": return rz * ry * rx
    case "yxz": return ry * rx * rz
    case "xyz": return rx * ry * rz
    case "yzx": return ry * rz * rx
    case "xzy": return rx * rz * ry
    default: return rz * rx * ry
    }
}
let parents = [-1, 0, 1, 2, 3, 4, 2, 6, 7, 8, 2, 10, 11, 12, 0, 14, 15, 16, 0, 18, 19, 20]
func read(_ path: String) -> [[SIMD3<Double>]] {
    try! String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map { line in
        let v = line.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces))! }
        return (0..<22).map { SIMD3(v[$0 * 3], v[$0 * 3 + 1], v[$0 * 3 + 2]) }
    }
}
func absolute(_ p: [SIMD3<Double>], _ a: [SIMD3<Double>]) -> [SIMD3<Double>] {
    var j = p
    let mode = ProcessInfo.processInfo.environment["MODE"] ?? "mixed"
    if mode != "mixed" {
        // "abs": each angle is the joint's global orientation; "rel": relative to the parent, cumulated along the chain.
        var global = [simd_double3x3](repeating: matrix_identity_double3x3, count: 22)
        global[0] = rot(a[0])
        for i in 1..<22 {
            let parent = parents[i]
            j[i] = global[parent] * p[i] + j[parent]
            global[i] = mode == "abs" ? rot(a[i]) : global[parent] * rot(a[i])
        }
        return j
    }
    var r = rot(a[0]); j[1] = r * j[1] + j[0]
    r = r * rot(a[1]); j[2] = r * j[2] + j[1]
    r = r * rot(a[2]); j[3] = r * j[3] + j[2]
    r = r * rot(a[3]); j[4] = r * j[4] + j[3]
    r = r * rot(a[4]); j[5] = r * j[5] + j[4]
    for joints in [[6, 7, 8, 9], [10, 11, 12, 13]] {
        var rr = rot(a[2]); j[joints[0]] = rr * j[joints[0]] + j[2]
        for k in 1..<4 { rr = rr * rot(a[joints[k - 1]]); j[joints[k]] = rr * j[joints[k]] + j[joints[k - 1]] }
    }
    for joints in [[14, 15, 16, 17], [18, 19, 20, 21]] {
        var rr = rot(a[0]); j[joints[0]] = rr * j[joints[0]] + j[0]
        for k in 1..<4 { rr = rr * rot(a[joints[k - 1]]); j[joints[k]] = rr * j[joints[k]] + j[joints[k - 1]] }
    }
    return j
}
/// Absolute skeletons of one segmented repetition. kind: "" correct, "_inc" incorrect.
func load(_ root: String, _ movement: Int, _ s: Int, _ e: Int, _ suffix: String) -> [[SIMD3<Double>]]? {
    let name = String(format: "m%02d_s%02d_e%02d", movement, s, e)
    let pp = "\(root)/Kinect/Positions/\(name)_positions\(suffix).txt", ap = "\(root)/Kinect/Angles/\(name)_angles\(suffix).txt"
    guard FileManager.default.fileExists(atPath: pp), FileManager.default.fileExists(atPath: ap) else { return nil }
    return zip(read(pp), read(ap)).map { absolute($0, $1) }
}
