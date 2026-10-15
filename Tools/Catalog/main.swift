import Foundation
import simd

// Builds the exercise catalog from the UI-PRMD Kinect recordings, measured as the app measures a filmed movement,
// and evaluates the preselection on people kept apart.
// usage: catalog <uiprmd root> <output catalog.json> <output report.md> [fixtures.json]
// People: 1–6 learn the signatures, 7–8 tune, 9–10 test. Never split by recording.

let args = CommandLine.arguments
let root = args[1], catalogPath = args[2], reportPath = args[3]
let fixturesPath = args.count > 4 ? args[4] : nil

let exercises: [(id: String, name: String)] = [
    ("squat", "Squat"), ("hurdle-step", "Montée de genou (enjambement)"), ("forward-lunge", "Fente avant"),
    ("side-lunge", "Fente latérale"), ("sit-to-stand", "Assis-debout"), ("leg-raise", "Élévation de la jambe tendue"),
    ("shoulder-abduction", "Élévation latérale d'un bras"), ("shoulder-extension", "Extension de l'épaule"),
    ("shoulder-rotation", "Rotation de l'épaule"), ("scaption", "Élévation du bras en diagonale"),
]
let train = Set(1...6), validation = Set(7...8), test = Set(9...10)

// MARK: Conversion: Kinect 3D → what Vision sees from a phone in front, 15 frames per second.

func mid(_ p: SIMD3<Double>, _ q: SIMD3<Double>) -> SIMD3<Double> { (p + q) / 2 }
let distance = 250.0
func project(_ skeleton: [[SIMD3<Double>]]) -> [PoseMeasure] {
    let standing = skeleton.max { mid($0[14], $0[18]).y < mid($1[14], $1[18]).y }!
    let restHips = mid(skeleton[0][14], skeleton[0][18])
    let camera = SIMD3(restHips.x, mid(standing[14], standing[18]).y, restHips.z + distance)
    func p(_ v: SIMD3<Double>) -> CGPoint {
        let depth = camera.z - v.z
        return CGPoint(x: (v.x - camera.x) / depth + 1, y: (v.y - camera.y) / depth + 1)
    }
    // 30 Hz recordings, the app analyzes 15 frames per second.
    return stride(from: 0, to: skeleton.count, by: 2).map { k in
        let j = skeleton[k]
        return PoseMeasure(
            hips: p(mid(j[14], j[18])), neck: p(mid(j[7], j[11])),
            leftHip: p(j[14]), rightHip: p(j[18]), leftKnee: p(j[15]), rightKnee: p(j[19]),
            leftAnkle: p(j[16]), rightAnkle: p(j[20]),
            leftShoulder: p(j[7]), rightShoulder: p(j[11]), leftElbow: p(j[8]), rightElbow: p(j[12]),
            leftWrist: p(j[9]), rightWrist: p(j[13])
        )
    }
}

struct Recording {
    let exercise: Int
    let person: Int
    let episode: Int
    let correct: Bool
    let frames: [PoseMeasure]
    let measurement: MovementMeasurement
}

var recordings: [Recording] = []
for m in 1...10 { for s in 1...10 { for e in 1...10 { for correct in [true, false] {
    let base = "\(root)/\(correct ? "correct" : "incorrect")"
    guard let skeleton = load(base, m, s, e, correct ? "" : "_inc"), skeleton.count > 10 else { continue }
    let frames = project(skeleton)
    guard let measurement = MovementMeasurement.measure(frames) else { continue }
    recordings.append(Recording(exercise: m, person: s, episode: e, correct: correct, frames: frames, measurement: measurement))
}}}}
print("recordings:", recordings.count)

// MARK: Signatures, from the training people's correct recordings.

let learning = recordings.filter { train.contains($0.person) && $0.correct }
let channelCount = MovementMeasurement.Channel.allCases.count
let dims = channelCount + 1
func std(_ v: [Double]) -> Double {
    let mean = v.reduce(0, +) / Double(v.count)
    return sqrt(v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, v.count - 1)))
}
var signatures: [ExerciseSignature] = []
var withinSpread = Array(repeating: [Double](), count: dims)
for (index, exercise) in exercises.enumerated() {
    let own = learning.filter { $0.exercise == index + 1 }.map(\.measurement)
    let vectors = own.map(\.vector)
    let centroid = (0..<dims).map { d in vectors.map { $0[d] }.reduce(0, +) / Double(vectors.count) }
    let spread = (0..<dims).map { d in std(vectors.map { $0[d] }) }
    for d in 0..<dims { withinSpread[d].append(spread[d]) }
    var mainCount: [MovementMeasurement.Channel: Int] = [:]
    for m in own { for c in m.mainChannels { mainCount[c, default: 0] += 1 } }
    let mains = mainCount.filter { $0.value * 3 >= own.count }.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.rawValue < $1.key.rawValue) }.map(\.key)
    func majority<T: Hashable>(_ values: [T]) -> T {
        Dictionary(grouping: values, by: { $0 }).max { $0.value.count < $1.value.count }!.key
    }
    signatures.append(ExerciseSignature(
        id: exercise.id, name: exercise.name,
        low: (0..<channelCount).map { c in Band(own.map { $0.low[c] }) },
        high: (0..<channelCount).map { c in Band(own.map { $0.high[c] }) },
        mainChannels: Array(mains.prefix(3)),
        plane: majority(own.map(\.plane)), position: majority(own.map(\.position)),
        usesBothSides: own.filter { $0.side == .both }.count * 2 > own.count,
        repDuration: Band(own.map(\.repDuration).filter { $0 > 0 }),
        centroid: centroid, spread: spread, samples: own.count
    ))
}
let pooled = withinSpread.map { MovementMeasurement.median($0) }
let examples = learning.map { SignatureExample(exercise: exercises[$0.exercise - 1].id, vector: $0.measurement.vector) }
var catalog = ExerciseCatalogFile(
    version: 1,
    source: "UI-PRMD Kinect (University of Idaho), 10 mouvements, vue de face simulée à 2,5 m, 15 images/s. Signatures : personnes 1–6 (mouvements corrects) ; réglage : 7–8 ; test : 9–10.",
    signatures: signatures, examples: examples, pooledSpread: pooled, closePairs: [], maximumDistance: 0)

// MARK: Close pairs: signatures near each other, on the common scale.

let preselection = Preselection(catalog: catalog)
var pairs: [ExerciseCatalogFile.ClosePair] = []
for i in signatures.indices { for j in signatures.indices where j > i {
    pairs.append(.init(first: signatures[i].id, second: signatures[j].id,
                       distance: preselection.distance(signatures[i].centroid, to: signatures[j])))
}}
pairs.sort { $0.distance < $1.distance }

// MARK: Evaluation, by people.

func evaluate(_ set: Set<Int>, correct: Bool, method: (MovementMeasurement) -> [Preselection.Candidate]) -> (top1: Double, top5: Double, confusion: [[Int]]) {
    var confusion = Array(repeating: Array(repeating: 0, count: 10), count: 10)
    var top1 = 0, top5 = 0, total = 0
    for r in recordings where set.contains(r.person) && r.correct == correct {
        let candidates = method(r.measurement)
        let truth = exercises[r.exercise - 1].id
        total += 1
        if candidates.first?.id == truth { top1 += 1 }
        if candidates.contains(where: { $0.id == truth }) { top5 += 1 }
        if let first = candidates.first, let j = exercises.firstIndex(where: { $0.id == first.id }) { confusion[r.exercise - 1][j] += 1 }
    }
    return (Double(top1) / Double(total), Double(top5) / Double(total), confusion)
}
let methods: [(String, (MovementMeasurement) -> [Preselection.Candidate])] = [
    ("signatures", { preselection.byCentroid($0) }),
    ("voisins", { preselection.byNeighbors($0) }),
]

// Out of the catalog: each exercise removed in turn, its recordings must be far from the others.
var inside: [Double] = [], outside: [Double] = []
for (index, exercise) in exercises.enumerated() {
    var reduced = catalog
    reduced.signatures.removeAll { $0.id == exercise.id }
    let p = Preselection(catalog: reduced)
    for r in recordings where validation.contains(r.person) && r.correct {
        let nearest = p.byCentroid(r.measurement, count: 1).first!.distance
        if r.exercise == index + 1 { outside.append(nearest) } else { inside.append(nearest) }
    }
}
// Threshold: keeps 95 % of the known movements.
catalog.maximumDistance = MovementMeasurement.percentile(inside, 0.95)
let rejected = Double(outside.filter { $0 > catalog.maximumDistance }.count) / Double(outside.count)
catalog.closePairs = Array(pairs.prefix(8))

// MARK: Report

func pct(_ x: Double) -> String { String(format: "%.0f %%", x * 100) }
var report = "# Catalogue d'exercices – rapport\n\n" + catalog.source + "\n\nEnregistrements mesurés : \(recordings.count).\n\n"
report += "## Signatures\n\n| Exercice | Mesures principales | Plan | Position | Côtés | s/rép. |\n|---|---|---|---|---|---|\n"
for s in signatures {
    report += "| \(s.name) | \(s.mainChannels.map(\.label).joined(separator: ", ")) | \(s.plane.rawValue) | \(s.position.rawValue) | \(s.usesBothSides ? "deux" : "un") | \(String(format: "%.1f", s.repDuration.p50)) |\n"
}
report += "\n## Paires proches (futures confusions)\n\n| Exercice | Exercice | Distance |\n|---|---|---|\n"
for p in pairs.prefix(8) { report += "| \(p.first) | \(p.second) | \(String(format: "%.2f", p.distance)) |\n" }
for (name, method) in methods {
    report += "\n## Présélection par \(name)\n\n| Jeu | Correct top 1 | Correct top 5 | Incorrect top 1 | Incorrect top 5 |\n|---|---|---|---|---|\n"
    for (label, set) in [("validation (7–8)", validation), ("test (9–10)", test)] {
        let c = evaluate(set, correct: true, method: method), i = evaluate(set, correct: false, method: method)
        report += "| \(label) | \(pct(c.top1)) | \(pct(c.top5)) | \(pct(i.top1)) | \(pct(i.top5)) |\n"
    }
    let c = evaluate(test, correct: true, method: method)
    report += "\nMatrice de confusion (test, corrects ; ligne = vrai, colonne = choisi) :\n\n| | " + (1...10).map { "m\($0)" }.joined(separator: " | ") + " |\n|" + String(repeating: "---|", count: 11) + "\n"
    for (k, row) in c.confusion.enumerated() { report += "| m\(k + 1) | " + row.map(String.init).joined(separator: " | ") + " |\n" }
}
report += "\n## Hors catalogue\n\nSeuil de distance (95 % des mouvements connus en dessous) : \(String(format: "%.2f", catalog.maximumDistance)). Exercice retiré du catalogue rejeté : \(pct(rejected)).\n"

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try! encoder.encode(catalog).write(to: URL(fileURLWithPath: catalogPath))
try! report.write(toFile: reportPath, atomically: true, encoding: .utf8)
print(report)

// MARK: Fixtures: the test people's recordings, for the app's tests (no camera).

if let fixturesPath {
    struct Fixture: Codable {
        let exercise: String
        let person: Int
        let episode: Int
        let correct: Bool
        /// Per frame: hips, neck, then left/right hip, knee, ankle, shoulder, elbow, wrist (x, y).
        let frames: [[Double]]
    }
    func flatten(_ m: PoseMeasure) -> [Double] {
        let points: [CGPoint] = [m.hips, m.neck, m.leftHip!, m.rightHip!, m.leftKnee!, m.rightKnee!, m.leftAnkle!,
                                 m.rightAnkle!, m.leftShoulder!, m.rightShoulder!, m.leftElbow!, m.rightElbow!,
                                 m.leftWrist!, m.rightWrist!]
        var values: [Double] = []
        for point in points {
            values.append((Double(point.x) * 1000).rounded() / 1000)
            values.append((Double(point.y) * 1000).rounded() / 1000)
        }
        return values
    }
    let fixtures = recordings.filter { test.contains($0.person) }.map { r in
        Fixture(exercise: exercises[r.exercise - 1].id, person: r.person, episode: r.episode, correct: r.correct,
                frames: r.frames.map(flatten))
    }
    try! JSONEncoder().encode(fixtures).write(to: URL(fileURLWithPath: fixturesPath))
    print("fixtures:", fixtures.count)
}
