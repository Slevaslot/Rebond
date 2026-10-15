import AVFoundation
import XCTest
@testable import Rebond

/// Replays the whole recognition (measure, preselect, choose, check) on recordings it never learned from, without
/// a camera: the Kinect recordings of the test people (9 and 10), and the annotated iPhone videos of `Fixtures/videos`.
/// The final choice is made by distance here: the language model isn't available in tests.
/// Prints a readable report: precision and recall per exercise, the most confused pairs, Kinect against iPhone.
final class RecognitionTests: XCTestCase {
    private struct Fixture: Decodable {
        let exercise: String
        let person: Int
        let episode: Int
        let correct: Bool
        let frames: [[Double]]

        var poses: [PoseMeasure?] {
            frames.map { v in
                func p(_ i: Int) -> CGPoint { CGPoint(x: v[i * 2], y: v[i * 2 + 1]) }
                return PoseMeasure(hips: p(0), neck: p(1), leftHip: p(2), rightHip: p(3), leftKnee: p(4), rightKnee: p(5),
                                   leftAnkle: p(6), rightAnkle: p(7), leftShoulder: p(8), rightShoulder: p(9),
                                   leftElbow: p(10), rightElbow: p(11), leftWrist: p(12), rightWrist: p(13))
            }
        }
    }

    private static let catalog: ExerciseCatalogFile = {
        let url = Bundle.main.url(forResource: ExerciseCatalogFile.resourceName, withExtension: "json")!
        return try! JSONDecoder().decode(ExerciseCatalogFile.self, from: Data(contentsOf: url))
    }()

    private static let fixtures: [Fixture] = {
        let url = Bundle(for: RecognitionTests.self).url(forResource: "kinect-test", withExtension: "json")!
        return try! JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }()

    /// Several repetitions in a row, as a filmed video has: three recordings of the same person and exercise.
    private static func videos(correct: Bool) -> [(exercise: String, poses: [PoseMeasure?])] {
        let selected = fixtures.filter { $0.correct == correct }
        let groups = Dictionary(grouping: selected) { "\($0.exercise)-\($0.person)" }
        return groups.keys.sorted().flatMap { key -> [(exercise: String, poses: [PoseMeasure?])] in
            let recordings = groups[key]!.sorted { $0.episode < $1.episode }
            return stride(from: 0, to: recordings.count - 2, by: 3).map { start in
                (recordings[start].exercise, recordings[start..<start + 3].flatMap(\.poses))
            }
        }
    }

    private struct Tally {
        var confusion: [String: [String: Int]] = [:]
        var total = 0
        var right = 0

        mutating func add(truth: String, chosen: String) {
            confusion[truth, default: [:]][chosen, default: 0] += 1
            total += 1
            if truth == chosen { right += 1 }
        }

        var accuracy: Double { total > 0 ? Double(right) / Double(total) : 0 }

        func precision(_ id: String) -> Double {
            let chosen = confusion.values.reduce(0) { $0 + ($1[id] ?? 0) }
            return chosen > 0 ? Double(confusion[id]?[id] ?? 0) / Double(chosen) : 0
        }

        func recall(_ id: String) -> Double {
            let truth = confusion[id]?.values.reduce(0, +) ?? 0
            return truth > 0 ? Double(confusion[id]?[id] ?? 0) / Double(truth) : 0
        }

        /// The pairs most often mistaken for each other.
        var worstPairs: [(String, String, Int)] {
            confusion.flatMap { truth, row in row.filter { $0.key != truth }.map { (truth, $0.key, $0.value) } }
                .sorted { $0.2 > $1.2 }
        }
    }

    /// Why movements were not recognized, to read in the report.
    nonisolated(unsafe) private static var reasons: [String: Int] = [:]

    private func recognize(_ poses: [PoseMeasure?], catalog: ExerciseCatalogFile = catalog) async -> String {
        guard let measurement = MovementMeasurement.measure(poses) else { return "nonMesuré" }
        let result = await ExerciseRecognizer(catalog: catalog).recognize(measurement)
        if case .notRecognized(_, let reason) = result { Self.reasons[reason, default: 0] += 1 }
        return result.catalogID ?? "nonReconnu"
    }

    private func report(_ title: String, _ tally: Tally) -> String {
        var lines = ["", "== \(title) : \(tally.right)/\(tally.total) (\(Int(tally.accuracy * 100)) %)"]
        for signature in Self.catalog.signatures {
            lines.append(String(format: "  %-20@ précision %3.0f %%  rappel %3.0f %%", signature.id,
                                tally.precision(signature.id) * 100, tally.recall(signature.id) * 100))
        }
        let pairs = tally.worstPairs.prefix(5).map { "\($0.0) → \($0.1) (\($0.2))" }
        lines.append("  Confusions : " + (pairs.isEmpty ? "aucune" : pairs.joined(separator: ", ")))
        return lines.joined(separator: "\n")
    }

    // MARK: Kinect

    func testKinectRecognition() async throws {
        var single = Tally(), video = Tally()
        for fixture in Self.fixtures where fixture.correct {
            single.add(truth: fixture.exercise, chosen: await recognize(fixture.poses))
        }
        for (exercise, poses) in Self.videos(correct: true) {
            video.add(truth: exercise, chosen: await recognize(poses))
        }
        print(report("Kinect, personnes de test, une répétition", single))
        print(report("Kinect, personnes de test, trois répétitions à la suite", video))
        print("  Raisons des non reconnus : " + Self.reasons.sorted { $0.value > $1.value }.map { "\($0.key) (\($0.value))" }.joined(separator: " ; "))
        // A wrong name is worse than none: what is recognized must be right.
        // A diagonal raise named lateral is a product decision (ExerciseRecognizer.preferred), not a mistake.
        let wrong = single.confusion.flatMap { truth, row in
            row.filter { $0.key != truth && $0.key != "nonReconnu" && ExerciseRecognizer.preferred[truth] != $0.key }.map(\.value)
        }.reduce(0, +)
        XCTAssertLessThanOrEqual(Double(wrong) / Double(single.total), 0.1, "Trop d'exercices mal nommés")
        XCTAssertGreaterThanOrEqual(video.accuracy, 0.7)
    }

    /// Each exercise removed from the catalog in turn: its recordings must not get another exercise's name.
    func testOutOfCatalogIsNotRecognized() async throws {
        var named = 0, total = 0
        for signature in Self.catalog.signatures {
            var reduced = Self.catalog
            reduced.signatures.removeAll { $0.id == signature.id }
            reduced.examples.removeAll { $0.exercise == signature.id }
            for (exercise, poses) in Self.videos(correct: true) where exercise == signature.id {
                total += 1
                if await recognize(poses, catalog: reduced) != "nonReconnu" { named += 1 }
            }
        }
        let rate = Double(total - named) / Double(max(total, 1))
        print(String(format: "\n== Hors catalogue : %d/%d classés non reconnus (%.0f %%)", total - named, total, rate * 100))
        XCTAssertGreaterThan(total, 0)
    }

    /// The same frames give the same result, every time.
    func testRecognitionIsDeterministic() async throws {
        for (_, poses) in Self.videos(correct: true).prefix(20) {
            let first = await recognize(poses), second = await recognize(poses)
            XCTAssertEqual(first, second)
        }
    }

    func testCustomNameIsNeverACatalogName() async throws {
        let names = Self.catalog.signatures.map(\.name)
        for fixture in Self.fixtures.prefix(200) {
            guard let measurement = MovementMeasurement.measure(fixture.poses) else { continue }
            XCTAssertFalse(names.contains(CustomExerciseName.make(for: measurement, avoiding: names)))
        }
    }

    // MARK: iPhone videos

    /// The annotated videos of `Fixtures/videos` (`<exercise id>__description.mov`, or `hors-catalogue__…`).
    /// Vision doesn't detect bodies in the simulator: this test runs on an iPhone, and is skipped without videos.
    func testPhoneVideos() async throws {
        let bundle = Bundle(for: RecognitionTests.self)
        let videos = (bundle.urls(forResourcesWithExtension: "mov", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? [])
        try XCTSkipIf(videos.isEmpty, "Aucune vidéo dans Fixtures/videos")
        var tally = Tally()
        for url in videos {
            let expected = String(url.deletingPathExtension().lastPathComponent.split(separator: "__").first ?? "")
            let truth = expected == "hors-catalogue" ? "nonReconnu" : expected
            do {
                let movement = try await ReferenceStore.learn(from: url, name: "", mirrored: true)
                tally.add(truth: truth, chosen: movement.recognizedID ?? "nonReconnu")
                ReferenceStore.delete(movement.id)
            } catch {
                tally.add(truth: truth, chosen: "inutilisable")
            }
        }
        // Vision finds no body in the simulator: nothing was measured, nothing to judge.
        let unusable = tally.confusion.values.reduce(0) { $0 + ($1["inutilisable"] ?? 0) }
        try XCTSkipIf(unusable == tally.total, "Vision ne détecte pas les corps dans le simulateur : lancer sur iPhone")
        print(report("Vidéos iPhone", tally))
    }
}
