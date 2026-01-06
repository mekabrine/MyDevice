import Foundation
import CoreMotion

@MainActor
final class MagneticFieldMonitor: ObservableObject {
    struct Reading {
        let x: Double
        let y: Double
        let z: Double
        let magnitude: Double   // microteslas (µT)
    }

    @Published private(set) var reading: Reading?
    @Published private(set) var baseline: Double?      // µT
    @Published private(set) var deltaFromBaseline: Double = 0

    private let motion = CMMotionManager()

    func start(updateHz: Double = 20) {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / updateHz

        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let f = dm.magneticField.field  // microteslas

            let mag = (f.x * f.x + f.y * f.y + f.z * f.z).squareRoot()
            let r = Reading(x: f.x, y: f.y, z: f.z, magnitude: mag)
            self.reading = r

            if let b = self.baseline {
                self.deltaFromBaseline = mag - b
            } else {
                self.deltaFromBaseline = 0
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    func calibrateBaseline() {
        baseline = reading?.magnitude
        deltaFromBaseline = 0
    }

    var isAvailable: Bool { motion.isDeviceMotionAvailable }
}
