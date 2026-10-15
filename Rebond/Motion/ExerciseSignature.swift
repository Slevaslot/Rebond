import Foundation

/// A spread of values seen in the recordings: 5th percentile, median, 95th percentile.
nonisolated struct Band: Codable, Sendable, Equatable {
    var p5: Double
    var p50: Double
    var p95: Double

    init(p5: Double, p50: Double, p95: Double) {
        self.p5 = p5
        self.p50 = p50
        self.p95 = p95
    }

    init(_ values: [Double]) {
        p5 = MovementMeasurement.percentile(values, 0.05)
        p50 = MovementMeasurement.percentile(values, 0.5)
        p95 = MovementMeasurement.percentile(values, 0.95)
    }

    /// Inside the band, widened by `margin` of its width on each side (and at least `minimum`).
    func contains(_ value: Double, margin: Double = 0.25, minimum: Double = 0) -> Bool {
        let widen = max((p95 - p5) * margin, minimum)
        return value >= p5 - widen && value <= p95 + widen
    }
}

/// What an exercise of the catalog looks like, measured on the recordings of the people it was learned from.
nonisolated struct ExerciseSignature: Codable, Sendable, Identifiable {
    /// The catalog exercise (`CatalogExercise.id`), or a movement without camera follow-up.
    let id: String
    /// French name, as shown in the app.
    let name: String
    /// Low and high values of each channel (`MovementMeasurement.Channel`), across the recordings.
    let low: [Band]
    let high: [Band]
    /// The channels that change the most, the most frequent first.
    let mainChannels: [MovementMeasurement.Channel]
    let plane: MovementMeasurement.Plane
    let position: MovementMeasurement.Position
    /// Usual side: one side, or both together.
    let usesBothSides: Bool
    /// Seconds per repetition.
    let repDuration: Band
    /// Mean measurement vector, and how much it varies, on the common scale.
    let centroid: [Double]
    let spread: [Double]
    /// Recordings it was learned from.
    let samples: Int

    func range(_ channel: MovementMeasurement.Channel) -> Band {
        let i = channel.rawValue
        return Band(p5: max(0, high[i].p5 - low[i].p95), p50: high[i].p50 - low[i].p50, p95: high[i].p95 - low[i].p5)
    }

    /// One line, for the language model and the report: « genou 95°→170°, hanches …, plan sagittal, debout ».
    var summary: String {
        let parts = mainChannels.map { channel -> String in
            let i = channel.rawValue
            let format = channel.isAngle ? "%.0f°→%.0f°" : "%.1f→%.1f"
            return channel.label + " " + String(format: format, low[i].p50, high[i].p50)
        }
        let planeName = plane == .frontal ? "plan frontal" : plane == .sagittal ? "plan sagittal" : "plan indéterminé"
        let positionName = position == .seated ? "assis" : position == .mixed ? "debout, avec descente" : "debout"
        return (parts + [planeName, positionName, usesBothSides ? "les deux côtés" : "un côté",
                         String(format: "%.1f s par répétition", repDuration.p50)]).joined(separator: ", ")
    }
}

/// One measured recording kept as an example, for the nearest-neighbor preselection.
nonisolated struct SignatureExample: Codable, Sendable {
    let exercise: String
    let vector: [Double]
}

/// The catalog file: every exercise of the Kinect recordings, its signature and examples. Versioned, readable JSON.
nonisolated struct ExerciseCatalogFile: Codable, Sendable {
    var version: Int
    /// Where the signatures come from, and how the people were split.
    var source: String
    var signatures: [ExerciseSignature]
    var examples: [SignatureExample]
    /// Spread of each measure across all exercises, to compare measures on one scale.
    var pooledSpread: [Double]
    /// Exercises whose signatures are close: the expected confusions.
    var closePairs: [ClosePair]
    /// Distance under which a movement can be one of the catalog's; above, it is not recognized.
    var maximumDistance: Double

    nonisolated struct ClosePair: Codable, Sendable {
        let first: String
        let second: String
        let distance: Double
    }

    static let resourceName = "ExerciseCatalog"

    /// The catalog shipped with the app.
    static let bundled: ExerciseCatalogFile? = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExerciseCatalogFile.self, from: data)
    }()
}

/// Narrows the catalog down to a few candidates for a measured movement, nearest first.
nonisolated struct Preselection: Sendable {
    nonisolated struct Candidate: Sendable, Equatable {
        let id: String
        /// Distance on the common scale: 0 for the exercise's average recording.
        let distance: Double
    }

    let catalog: ExerciseCatalogFile

    /// Distance of a measurement to an exercise's average recording, each measure divided by its spread.
    func distance(_ vector: [Double], to signature: ExerciseSignature) -> Double {
        var total = 0.0
        for i in vector.indices {
            let spread = max(signature.spread[i], catalog.pooledSpread[i] * 0.5, 0.02)
            let d = (vector[i] - signature.centroid[i]) / spread
            total += d * d
        }
        return sqrt(total / Double(vector.count))
    }

    /// The nearest signatures.
    func byCentroid(_ measurement: MovementMeasurement, count: Int = 5) -> [Candidate] {
        let vector = measurement.vector
        return catalog.signatures
            .map { Candidate(id: $0.id, distance: distance(vector, to: $0)) }
            .sorted { $0.distance < $1.distance || ($0.distance == $1.distance && $0.id < $1.id) }
            .prefix(count).map { $0 }
    }

    /// The exercises of the nearest recorded examples (k nearest), ranked by their nearest example.
    func byNeighbors(_ measurement: MovementMeasurement, count: Int = 5, k: Int = 7) -> [Candidate] {
        let vector = measurement.vector
        func d(_ example: SignatureExample) -> Double {
            var total = 0.0
            for i in vector.indices {
                let spread = max(catalog.pooledSpread[i], 0.02)
                let x = (vector[i] - example.vector[i]) / spread
                total += x * x
            }
            return sqrt(total / Double(vector.count))
        }
        let measured: [(String, Double)] = catalog.examples.map { ($0.exercise, d($0)) }
        let nearest = measured.sorted { (x: (String, Double), y: (String, Double)) -> Bool in
            x.1 != y.1 ? x.1 < y.1 : x.0 < y.0
        }
        // Votes of the k nearest, ties broken by the nearest example.
        var votes: [String: Int] = [:]
        for (exercise, _) in nearest.prefix(k) { votes[exercise, default: 0] += 1 }
        var best: [String: Double] = [:]
        for (exercise, distance) in nearest where best[exercise] == nil { best[exercise] = distance }
        func before(_ x: Candidate, _ y: Candidate) -> Bool {
            let a = votes[x.id] ?? 0, b = votes[y.id] ?? 0
            if a != b { return a > b }
            if x.distance != y.distance { return x.distance < y.distance }
            return x.id < y.id
        }
        let candidates: [Candidate] = best.map { Candidate(id: $0.key, distance: $0.value) }
        return Array(candidates.sorted(by: before).prefix(count))
    }
}
