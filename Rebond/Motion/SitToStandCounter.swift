import CoreGraphics
import Foundation

/// Counts sit-to-stands, seen from the front: the patient starts seated on a chair, stands up, then sits back down.
///
/// The hips' rise above their seated height is measured in torso lengths, the torso being measured seated
/// (the phone at hip height in front: standing up, the hips rise by about 0.8–0.9 torso lengths on screen).
/// Only the hips and the neck are needed: the chair, a table or the patient's own hands may hide the legs.
/// When the knees are seen, they also tell a seated patient from a standing one at calibration.
nonisolated struct SitToStandCounter: MovementCounter {
    private struct Seat {
        let hipsHeight: Double
        let torsoLength: Double
        /// Neck sideways from the hips, in torso lengths: few people sit perfectly straight.
        let lean: Double
    }

    /// How far the hips must rise for a complete repetition, in seated torso lengths.
    let targetRise: Double

    /// Measures (about 0.5 s) needed while seated and still to learn the seated position.
    private let stillSamples = 8
    /// Maximum hips movement while "still", in torso lengths.
    private let stillTolerance = 0.08
    /// Seen from the front, seated thighs point at the camera: the knees are about level with the hips.
    /// Standing, they are 0.7–0.9 torso lengths below. Beyond this gap the patient isn't seated.
    private let maxSeatedKneeDrop = 0.5
    /// Leaning forward to stand up makes the torso look shorter, seen from the front: some lean is needed,
    /// too much loads the back. UI-PRMD sit-to-stands: correct ones keep at least 64% of the upright length
    /// (most above 75%), incorrect ones with the chest thrown forward drop to 20–60%.
    private let minTorsoRatio = 0.6
    /// Torso leaning to one side, compared with the seated position, in torso lengths: the weight goes on one leg.
    /// UI-PRMD: correct sit-to-stands stay under 0.10, incorrect ones lean up to 0.6.
    private let maxSideLean = 0.15
    /// Below this fraction of the seated torso length, Vision has lost the body: the frame is ignored.
    private let collapsedTorsoRatio = 0.3
    private let lostTimeout = 1.5
    private let smoothingWindow = 3

    private var seat: Seat?
    /// The longest torso seen, upright: leaning forward only makes it look shorter.
    private var uprightTorso = 0.0
    private var cycle: RepCycle
    private var recentRises: [Double] = []
    private var recentMeasures: [PoseMeasure] = []
    private var lastMeasureTime = 0.0
    private var progress = 0.0

    init(targetRise: Double) {
        self.targetRise = targetRise
        cycle = RepCycle(
            start: 0.15,
            target: targetRise,
            back: 0.1,
            reversalMargin: 0.15,
            noise: 0.3,
            // Sitting down slowly, without dropping onto the chair, is part of the exercise.
            minDuration: 2,
            shortfall: .standUpFully
        )
    }

    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure else {
            if time - lastMeasureTime > lostTimeout { cycle.abandon() }
            return CounterUpdate(progress: progress, event: nil)
        }
        if let seat, measure.torsoLength / seat.torsoLength < collapsedTorsoRatio {
            return CounterUpdate(progress: progress, event: nil, posture: cycle.posture)
        }
        lastMeasureTime = time

        recentMeasures.append(measure)
        if recentMeasures.count > stillSamples { recentMeasures.removeFirst() }

        guard let seat else {
            if let seated = seatedPosition() {
                seat = seated
                uprightTorso = seated.torsoLength
                return CounterUpdate(progress: 0, event: .calibrated)
            }
            return CounterUpdate(progress: 0, event: nil)
        }

        uprightTorso = max(uprightTorso, RepCounter.median(recentMeasures.suffix(smoothingWindow).map(\.torsoLength)))
        recentRises.append((measure.hips.y - seat.hipsHeight) / seat.torsoLength)
        if recentRises.count > smoothingWindow { recentRises.removeFirst() }
        let rise = RepCounter.median(recentRises)
        progress = max(0, rise / targetRise)

        // Seated again and still, maybe a little further back on the chair: follow the new seat.
        if cycle.phase == .rest, let seated = seatedPosition(), abs(seated.hipsHeight - seat.hipsHeight) < stillTolerance * seat.torsoLength {
            self.seat = seated
        }

        let fault: Correction? = if measure.torsoLength / uprightTorso < minTorsoRatio {
            .keepBackStraight
        } else if abs(measure.sideLean - seat.lean) > maxSideLean {
            .useBothLegs
        } else {
            nil
        }
        let (event, posture) = cycle.advance(rise, fault: fault, at: time)
        return CounterUpdate(progress: progress, event: event, posture: posture)
    }

    /// The seated position, when the patient has been still for a moment with the knees (if seen) level with the hips.
    private func seatedPosition() -> Seat? {
        guard recentMeasures.count == stillSamples else { return nil }
        let torsoLength = RepCounter.median(recentMeasures.map(\.torsoLength))
        let hips = recentMeasures.map { Double($0.hips.y) }
        guard torsoLength > 0, hips.max()! - hips.min()! < stillTolerance * torsoLength else { return nil }

        let last = recentMeasures.last!
        let knees = [last.leftKnee, last.rightKnee].compactMap { $0 }
        if knees.contains(where: { (last.hips.y - $0.y) / torsoLength > maxSeatedKneeDrop }) { return nil }
        return Seat(hipsHeight: RepCounter.median(hips), torsoLength: torsoLength, lean: RepCounter.median(recentMeasures.map(\.sideLean)))
    }
}
