import Foundation

/// User-tunable mapping from dial rotation to on-screen scrolling.
///
/// Output scroll (pixels) = revolutions × pixelsPerRevolution × gain(speed), where
/// gain(v) = min(maxGain, 1 + accelStrength × max(0, v − accelThreshold)^accelExponent)
/// and v is the smoothed rotation speed in revolutions per second.
struct Calibration: Codable, Equatable {
    var countsPerRevolution: Double = 0          // 0 = not yet measured
    var pixelsPerRevolution: Double = 1000
    var accelThreshold: Double = 0.5
    var accelStrength: Double = 1.0
    var accelExponent: Double = 1.5
    var maxGain: Double = 8
    var smoothing: Double = 0.04                 // seconds (velocity EMA time constant)
    var reverseVertical = false
    var reverseHorizontal = false
    var forwardPointer = true

    /// Used until the user measures their dial.
    static let fallbackCountsPerRevolution = 1200.0

    var isCalibrated: Bool { countsPerRevolution > 0 }
    var effectiveCountsPerRevolution: Double {
        isCalibrated ? countsPerRevolution : Self.fallbackCountsPerRevolution
    }

    func gain(atRevsPerSecond v: Double) -> Double {
        let over = max(0, v - accelThreshold)
        return min(maxGain, 1 + accelStrength * pow(over, accelExponent))
    }

    func pixelsPerSecond(atRevsPerSecond v: Double) -> Double {
        v * pixelsPerRevolution * gain(atRevsPerSecond: v)
    }

    // MARK: Persistence

    private static let key = "calibration.v1"

    static func load() -> Calibration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cal = try? JSONDecoder().decode(Calibration.self, from: data) else { return Calibration() }
        return cal
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// Exponential moving average of signed counts per second. Integrates correctly
/// even when BLE delivers several reports back-to-back with near-identical timestamps.
struct VelocityEstimator {
    var timeConstant = 0.04
    private(set) var countsPerSecond = 0.0
    private(set) var lastTime: Double?

    static let idleGap = 0.12

    mutating func update(counts: Int, time: Double) -> Double {
        guard let last = lastTime, time - last < Self.idleGap else {
            // First report after a pause: assume it took the whole idle window (conservative = slow).
            lastTime = time
            countsPerSecond = Double(counts) / Self.idleGap
            return countsPerSecond
        }
        let dt = max(time - last, 0.0005)
        let alpha = 1 - exp(-dt / timeConstant)
        countsPerSecond += alpha * (Double(counts) / dt - countsPerSecond)
        lastTime = time
        return countsPerSecond
    }

    func current(at time: Double) -> Double {
        guard let last = lastTime, time - last < Self.idleGap else { return 0 }
        return countsPerSecond
    }
}
