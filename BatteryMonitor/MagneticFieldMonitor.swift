import CoreMotion
import Foundation

@MainActor
final class MagneticFieldMonitor: ObservableObject {
    static let shared = MagneticFieldMonitor()

    private let motion = CMMotionManager()
    private var baselineEMA: Double = 0
    private var baselineInitialized = false

    @Published private(set) var isAvailable: Bool = false

    @Published private(set) var x: Double = 0
    @Published private(set) var y: Double = 0
    @Published private(set) var z: Double = 0
    @Published private(set) var magnitude: Double = 0

    @Published private(set) var deltaFromBaseline: Double = 0
    @Published private(set) var lastUpdate: Date?

    private(set) var isRunning: Bool = false

    private init() {
        isAvailable = motion.isMagnetometerAvailable
    }

    func start(updateHz: Double = 10) {
        guard !isRunning else { return }
        isAvailable = motion.isMagnetometerAvailable
        guard isAvailable else { return }

        motion.magnetometerUpdateInterval = 1.0 / max(1.0, updateHz)

        // Use the magnetometer directly (raw field). Simulator often returns zeros.
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

            // Exponential moving average baseline (slowly adapts)
            let alpha = 0.03
            if !self.baselineInitialized {
                self.baselineEMA = mag
                self.baselineInitialized = true
            } else {
                self.baselineEMA = (1 - alpha) * self.baselineEMA + alpha * mag
            }

            self.deltaFromBaseline = mag - self.baselineEMA
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        motion.stopMagnetometerUpdates()
        isRunning = false
    }

    var magnitudeText: String {
        String(format: "%.1f", magnitude)
    }

    var deltaText: String {
        String(format: "%+.1f µT", deltaFromBaseline)
    }
}
