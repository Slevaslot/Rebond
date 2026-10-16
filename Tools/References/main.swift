import AVFoundation
import Foundation
import Vision

// Filmed movements on the Mac, through the app's own code:
//   references poses <video> <out.json> [--mirrored] [--session] [--from s] [--to s]
//       Vision on every 15th of a second. Default: everyone, the one who moves the most is kept (as when learning).
//       --session: the largest body of each image, as during a session (a screen recording of the session).
//   references learn <poses.json>                  what Rebond learns from it
//   references count <poses.json> <movement.json>  counts a session's poses with a learned movement
//                                                  (movement.json from the iPhone, or poses of the film)
//   references both <film poses.json> <session poses.json>

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("references poses|learn|count|both …") }

func option(_ name: String) -> Double? {
    arguments.firstIndex(of: name).flatMap { Double(arguments[$0 + 1]) }
}

func extractPoses(video: URL, mirrored: Bool, session: Bool, from: Double, to: Double?) async throws -> PoseRecording {
    let asset = AVURLAsset(url: video)
    let duration = min(try await asset.load(.duration).seconds, to ?? .infinity)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1280, height: 1280)
    let tolerance = CMTime(seconds: 1.0 / 30, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance
    let analyzer = PoseAnalyzer(orientation: mirrored ? .upMirrored : .up)
    var frames: [(time: Double, people: [PoseFrame], size: CGSize)] = []
    let times = stride(from: from, to: duration, by: 1.0 / 15).map { CMTime(seconds: $0, preferredTimescale: 600) }
    for await result in generator.images(for: times) {
        guard let image = try? result.image else { continue }
        let size = CGSize(width: image.width, height: image.height)
        let people = session ? [analyzer.analyze(image)] : analyzer.analyzeEveryone(image)
        frames.append((result.requestedTime.seconds - from, people, size))
    }
    frames.sort { $0.time < $1.time }
    let size = frames.first?.size ?? .zero
    if session {
        return PoseRecording(size: size, frames: frames.map { frame in
            let points = frame.people.first?.skeleton?.points ?? [:]
            return PoseRecording.Frame(t: (frame.time * 1000).rounded() / 1000, p: Dictionary(uniqueKeysWithValues: points.map {
                ($0.key.rawValue.rawValue, [($0.value.x * 10_000).rounded() / 10_000, ($0.value.y * 10_000).rounded() / 10_000])
            }))
        })
    }
    var people: [PersonTrack] = []
    for frame in frames { PersonTrack.follow(frame.people, at: frame.time, imageSize: frame.size, in: &people) }
    guard let patient = people.max(by: { ReferenceAnalyzer.motion(of: $0.samples) < ReferenceAnalyzer.motion(of: $1.samples) })
    else { fail("Aucun corps") }
    return PoseRecording(samples: patient.samples)
}

func load(_ path: String) -> PoseRecording {
    guard let data = FileManager.default.contents(atPath: path),
          let recording = try? JSONDecoder().decode(PoseRecording.self, from: data) else { fail("Lecture impossible : \(path)") }
    return recording
}

func f(_ value: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", value) }

func learn(_ recording: PoseRecording) -> ReferenceAnalysis {
    do {
        let analysis = try ReferenceAnalyzer.analyze(recording.samples)
        print("Répétitions : \(analysis.repCount), cible \(f(analysis.target)), durée min \(f(analysis.minDuration))")
        print("Repos (t) : \(analysis.bestStart) → pic \(analysis.bestPeak) → fin \(analysis.bestEnd)")
        let names = ["coudeG", "coudeD", "épauleG", "épauleD", "genouG", "genouD", "hancheG", "hancheD", "hanchesY", "hanchesX",
                     "buste", "poignetG", "poignetD", "couY", "chevilleG", "chevilleD"]
        let axis = analysis.axis.enumerated().filter { abs($0.element) > 0.1 }.map { "\(names[$0.offset]) \(f($0.element))" }
        print("Axe : \(axis.joined(separator: ", "))")
        print("Départ : \(analysis.restReason) (confiance \(f(analysis.restConfidence))), alterné : \(analysis.alternatesSides), \(analysis.kind)\(analysis.holdSeconds.map { " \($0) s" } ?? "")")
        print("Répétitions (s) : \(analysis.repetitions.map { "\(f($0.lowerBound, 1))–\(f($0.upperBound, 1))" }.joined(separator: ", "))")
        print("Non suivies : \(analysis.featureMask.enumerated().filter { !$0.element }.map { names[$0.offset] }.joined(separator: ", "))")
        print("Repos : \(analysis.rest.enumerated().map { "\(names[$0.offset]) \(f($0.element))" }.joined(separator: ", "))")
        return analysis
    } catch {
        fail("Apprentissage impossible : \(error)")
    }
}

func count(_ recording: PoseRecording, with movement: ReferenceMovement) {
    var counter = ReferenceCounter(movement: movement)
    var reps = 0
    for sample in recording.samples {
        let update = counter.process(sample.measure, at: sample.time)
        var line = "\(f(sample.time, 2))s  \(String(repeating: "█", count: Int((update.progress * 20).rounded())).padding(toLength: 20, withPad: "·", startingAt: 0)) \(f(update.progress))"
        if let posture = update.posture { line += "  [\(posture)]" }
        switch update.event {
        case .repCompleted(let rep): reps += 1; line += "  ✅ \(reps) (amplitude \(f(rep.amplitude)), ressemblance \(rep.resemblance.map { f($0) } ?? "–"))"
        case .repIncomplete(let a): line += "  ◐ incomplète \(f(a))"
        case .calibrated: line += "  ⚑ calibré"
        case .bottomReached: line += "  ▲ objectif"
        case .correction(let c): line += "  ⚠︎ \(c)"
        case nil: break
        }
        if sample.measure == nil { line += "  (pas de corps)" }
        print(line)
    }
    print("Total : \(reps) répétitions")
}

func makeMovement(from analysis: ReferenceAnalysis) -> ReferenceMovement {
    ReferenceMovement(id: UUID(), name: "Film", analysis: analysis, frameCount: 0, peakFrame: 0)
}

switch command {
case "poses":
    let recording = try await extractPoses(video: URL(fileURLWithPath: arguments[1]), mirrored: arguments.contains("--mirrored"),
                                           session: arguments.contains("--session"), from: option("--from") ?? 0, to: option("--to"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(recording).write(to: URL(fileURLWithPath: arguments[2]))
    print("\(recording.frames.count) images, \(recording.frames.filter { !$0.p.isEmpty }.count) avec un corps")
case "learn":
    _ = learn(load(arguments[1]))
case "count":
    let data = FileManager.default.contents(atPath: arguments[2])!
    let movement: ReferenceMovement
    if let decoded = try? JSONDecoder().decode(ReferenceMovement.self, from: data) {
        movement = decoded
    } else {
        movement = makeMovement(from: learn(load(arguments[2])))
    }
    count(load(arguments[1]), with: movement)
case "both":
    count(load(arguments[2]), with: makeMovement(from: learn(load(arguments[1]))))
default:
    fail("Commande inconnue")
}
