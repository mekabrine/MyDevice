import CoreMotion
import Foundation

@MainActor
final class MagneticFieldMonitor: ObservableObject {
    static let shared = MagneticFieldMonitor()

    struct Reading: Equatable {
        let x: Double
        let y: Double
        let z: Double
        let magnitude: Double
    }

    private let motion = CMMotionManager()

    // Baseline (EMA) state
    private var baselineEMA: Double = 0
    private var baselineInitialized = false

    @Published private(set) var isAvailable: Bool = false

    @Published private(set) var x: Double = 0
    @Published private(set) var y: Double = 0
    @Published private(set) var z: Double = 0
    @Published private(set) var magnitude: Double = 0

    // Exposed baseline info
    @Published private(set) var baseline: Double? = nil
    @Published private(set) var deltaFromBaseline: Double = 0
    @Published private(set) var lastUpdate: Date?

    private(set) var isRunning: Bool = false

    private init() {
        isAvailable = motion.isMagnetometerAvailable
    }

    var reading: Reading? {
        guard lastUpdate != nil else { return nil }
        return Reading(x: x, y: y, z: z, magnitude: magnitude)
    }

    func calibrateBaseline() {
        // Sets baseline to the current magnitude immediately
        baselineEMA = magnitude
        baselineInitialized = true
        baseline = baselineEMA
        deltaFromBaseline = 0
    }

    func start(updateHz: Double = 10) {
        guard !isRunning else { return }
        isAvailable = motion.isMagnetometerAvailable
        guard isAvailable else { return }

        motion.magnetometerUpdateInterval = 1.0 / max(1.0, updateHz)

        // Note: Simulator commonly returns zeros. Test on a real device.
        motion.startMagnetometerUpdates(to: .main) { [weak self] data, error in
            guard let self else { return }
            guard error == nil, let d = data else { return }

            let fx = d.magneticField.x
            let fy = d.magneticField.y
            let fz = d.magneticField.z

            self.x = fx
            self.y = fy
            self.z = fz

            let mag = sqrt(fx * fx + fy * fy + fz * fz)
            self.magnitude = mag
            self.lastUpdate = Date()

            // Slow EMA baseline
            let alpha = 0.03
            if !self.baselineInitialized {
                self.baselineEMA = mag
                self.baselineInitialized = true
            } else {
                self.baselineEMA = (1 - alpha) * self.baselineEMA + alpha * mag
            }

            self.baseline = self.baselineEMA
            self.deltaFromBaseline = mag - self.baselineEMA
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        motion.stopMagnetometerUpdates()
        isRunning = false
    }

    var magnitudeText: String { String(format: "%.1f µT", magnitude) }
    var deltaText: String { String(format: "%+.1f µT", deltaFromBaseline) }
}
