import Foundation
import CoreMotion

/// Reads magnetic field (µT) and provides a simple baseline + delta for "metal detector"-style use.
/// Works on real devices; simulator often returns zeros.
final class MagneticFieldMonitor: ObservableObject {
    @Published var isAvailable = false

    @Published var x: Double = 0
    @Published var y: Double = 0
    @Published var z: Double = 0

    /// Magnitude in microtesla (µT)
    @Published var magnitude: Double = 0

    /// Delta from baseline magnitude (µT)
    @Published var deltaFromBaseline: Double = 0

    private let motion = CMMotionManager() // must be retained
    private let queue = OperationQueue()

    private var baseline: Double?
    private var baselineSamples: [Double] = []
    private let baselineTargetCount = 40

    func start() {
        // Prefer calibrated field via device motion (best for UX)
        if motion.isDeviceMotionAvailable {
            isAvailable = true
            motion.deviceMotionUpdateInterval = 1.0 / 20.0

            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motionData, _ in
                guard let self, let dm = motionData else { return }
                let f = dm.magneticField.field // µT
                self.update(x: f.x, y: f.y, z: f.z)
            }
            return
        }

        // Fallback to raw magnetometer
        if motion.isMagnetometerAvailable {
            isAvailable = true
            motion.magnetometerUpdateInterval = 1.0 / 20.0

            motion.startMagnetometerUpdates(to: queue) { [weak self] data, _ in
                guard let self, let m = data?.magneticField else { return }
                self.update(x: m.x, y: m.y, z: m.z)
            }
            return
        }

        isAvailable = false
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopMagnetometerUpdates()
    }

    func resetBaseline() {
        baseline = nil
        baselineSamples.removeAll(keepingCapacity: true)
    }

    private func update(x: Double, y: Double, z: Double) {
        let mag = sqrt(x*x + y*y + z*z)

        // Build baseline from first N samples after start/reset
        if baseline == nil {
            baselineSamples.append(mag)
            if baselineSamples.count >= baselineTargetCount {
                baseline = baselineSamples.reduce(0, +) / Double(baselineSamples.count)
            }
        }

        let base = baseline ?? mag
        let delta = mag - base

        DispatchQueue.main.async {
            self.x = x
            self.y = y
            self.z = z
            self.magnitude = mag
            self.deltaFromBaseline = delta
        }
    }
}
