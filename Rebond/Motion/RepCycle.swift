import Foundation

/// The repetition state machine shared by the counters that follow one value going from rest to a target
/// and back (arm angle, rise of the hips, height of the ankle).
///
/// A repetition starts when the value passes `start`, goes far enough at `counted` (70% of `target`,
/// `.bottomReached`), and is counted once back under `back`. Coming back before that makes it incomplete;
/// a fault seen on `faultFrames` frames in a row cancels it until the patient is back at rest.
/// The hysteresis between `start` and `back` keeps detection noise from counting twice.
nonisolated struct RepCycle: Sendable {
    enum Phase: Sendable {
        case rest
        case going
        case targetReached
        /// Came back before reaching the target.
        case returnedEarly
        /// A fault cancelled the repetition: waiting for the patient to come back to rest.
        case cancelled
    }

    /// The value at which a repetition starts.
    let start: Double
    /// The exercise's target, 100% of the amplitude. A repetition counts from `counted`.
    let target: Double
    /// Back at rest under this value.
    let back: Double
    /// How far the value must come back from its peak to count as the way back.
    let reversalMargin: Double
    /// Below this peak, an attempt is too small to be worth a correction.
    let noise: Double
    /// Seconds from the start of the repetition to the return: faster is flagged "too fast".
    let minDuration: Double
    /// Said when the patient comes back before the target.
    let shortfall: Correction
    /// A fault must last this many frames (0.2 s) to count: Vision is sometimes wrong on a single frame.
    var faultFrames = 3

    private(set) var phase = Phase.rest
    /// Highest value of the current repetition.
    private(set) var peak = 0.0
    private var repStart = 0.0
    private var faultStreak: (fault: Correction, frames: Int)?

    /// The value from which a repetition counts: "Bien", 70% of the target. Elderly patients rarely reach
    /// the full target; the amplitude reached (up to beyond 100%) tells the physio how far they went.
    var counted: Double { target * AmplitudeTier.goodThreshold }

    var isInRepetition: Bool {
        phase == .going || phase == .targetReached || phase == .returnedEarly
    }

    /// Fault seen right now during a repetition, to highlight on the body.
    var posture: Correction? {
        isInRepetition ? faultStreak?.fault : nil
    }

    /// The body was lost during the repetition: forget it.
    mutating func abandon() {
        if isInRepetition { phase = .rest }
    }

    /// Feeds the smoothed value and the fault seen on this frame (only looked at during a repetition).
    /// Returns the event and the fault to highlight.
    mutating func advance(_ value: Double, fault: Correction?, at time: Double) -> (event: RepEvent?, posture: Correction?) {
        if isInRepetition {
            peak = max(peak, value)
            if let fault {
                let frames = faultStreak?.fault == fault ? faultStreak!.frames + 1 : 1
                faultStreak = (fault, frames)
                if frames >= faultFrames {
                    phase = .cancelled
                    return (.correction(fault), fault)
                }
            } else {
                faultStreak = nil
            }
        }
        let event = step(value, at: time)
        return (event, posture)
    }

    private mutating func step(_ value: Double, at time: Double) -> RepEvent? {
        switch phase {
        case .cancelled:
            if value <= back { phase = .rest }
        case .rest:
            if value >= start {
                phase = .going
                peak = value
                repStart = time
                faultStreak = nil
            }
        case .going:
            if value >= counted {
                phase = .targetReached
                return .bottomReached
            } else if value < peak - reversalMargin {
                guard peak >= noise else {
                    phase = .rest
                    return nil
                }
                phase = .returnedEarly
                return .correction(shortfall)
            }
        case .targetReached:
            if value <= back {
                phase = .rest
                return .repCompleted(RepResult(amplitude: peak / target, tooFast: time - repStart < minDuration))
            }
        case .returnedEarly:
            if value >= counted {
                phase = .targetReached
            } else if value <= back {
                phase = .rest
                return .repIncomplete(amplitude: peak / target)
            }
        }
        return nil
    }
}

nonisolated extension PoseMeasure {
    /// Neck sideways from the hips, in torso lengths: the torso leaning to one side, seen from the front.
    /// About 0 standing straight; compare with the patient's own resting value.
    var sideLean: Double {
        torsoLength > 0 ? (neck.x - hips.x) / torsoLength : 0
    }
}
