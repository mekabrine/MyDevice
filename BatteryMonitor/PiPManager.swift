import Foundation
import UIKit
import AVKit
import AVFoundation
import CoreGraphics

final class PiPManager: NSObject, ObservableObject {

    // MARK: - Public UI state

    @Published private(set) var pipStatusText: String = "Inactive"
    @Published private(set) var isPiPActive: Bool = false
    @Published private(set) var canStartPiP: Bool = false

    // MARK: - PiP Internals

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?

    private let renderQueue = DispatchQueue(label: "pip.render.queue")
    private let sampleQueue = DispatchQueue(label: "pip.sample.queue")

    private var pixelBufferPool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?

    private var frameTimer: DispatchSourceTimer?
    private var frameIndex: Int64 = 0
    private let fps: Int32 = 15

    // MARK: - Estimation (battery slope)

    private struct BatterySample {
        let t: TimeInterval
        let level: Double // 0.0...1.0
    }

    private var samples: [BatterySample] = []
    private let maxSamples = 240                 // ~16 minutes at 4s sample cadence
    private let sampleCadence: TimeInterval = 4  // seconds
    private var lastSampleTime: TimeInterval = 0

    // MARK: - Init

    override init() {
        super.init()

        UIDevice.current.isBatteryMonitoringEnabled = true

        setupDisplayLayer()
        setupPiPIfAvailable()
        startFramePump()
    }

    deinit {
        stopFramePump()
    }

    // MARK: - Public controls

    func startPiP() {
        DispatchQueue.main.async {
            guard let controller = self.pipController else { return }
            guard controller.isPictureInPicturePossible else { return }
            controller.startPictureInPicture()
        }
    }

    func stopPiP() {
        DispatchQueue.main.async {
            self.pipController?.stopPictureInPicture()
        }
    }

    // MARK: - Setup

    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.needsDisplayOnBoundsChange = true

        // Use a PiP-friendly render size (portrait-ish).
        let width = 540
        let height = 960

        var fmt: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width),
            height: Int32(height),
            extensions: nil,
            formatDescriptionOut: &fmt
        )
        if status == noErr, let fmt {
            self.formatDescription = fmt
        }

        // PixelBuffer pool for BGRA frames
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelAttributes as CFDictionary,
            &pool
        )
        self.pixelBufferPool = pool
    }

    private func setupPiPIfAvailable() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            DispatchQueue.main.async {
                self.canStartPiP = false
                self.pipStatusText = "PiP Not Supported"
            }
            return
        }

        // iOS 15+ sample-buffer PiP content source.
        if #available(iOS 15.0, *) {
            let contentSource = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = self
            self.pipController = controller

            DispatchQueue.main.async {
                self.canStartPiP = controller.isPictureInPicturePossible
                self.pipStatusText = controller.isPictureInPicturePossible ? "Inactive" : "Unavailable"
            }
        } else {
            DispatchQueue.main.async {
                self.canStartPiP = false
                self.pipStatusText = "Requires iOS 15+"
            }
        }
    }

    // MARK: - Frame pump

    private func startFramePump() {
        stopFramePump()

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(fps), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.pumpOneFrame()
        }
        timer.resume()
        frameTimer = timer
    }

    private func stopFramePump() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func pumpOneFrame() {
        guard let pool = pixelBufferPool,
              let fmt = formatDescription else {
            return
        }

        // Update battery samples at a slower cadence than video frames.
        let now = Date().timeIntervalSince1970
        if now - lastSampleTime >= sampleCadence {
            lastSampleTime = now
            recordBatterySample(at: now)
        }

        guard let pixelBuffer = makePixelBuffer(from: pool) else { return }

        // Draw overlay into pixel buffer
        renderQueue.sync {
            drawOverlay(into: pixelBuffer)
        }

        // Create CMSampleBuffer
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: fps),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: fps),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: fmt,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        frameIndex += 1

        guard createStatus == noErr, let sbuf = sampleBuffer else { return }

        // Enqueue to display layer
        displayLayer.enqueue(sbuf)
    }

    private func makePixelBuffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        return (status == kCVReturnSuccess) ? pb : nil
    }

    // MARK: - Overlay rendering

    private func drawOverlay(into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let ctx = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue // BGRA
        ) else {
            return
        }

        // Background
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Content
        let lines = buildOverlayLines()

        // Typography
        let titleFont = UIFont.systemFont(ofSize: 44, weight: .bold)
        let bodyFont = UIFont.monospacedSystemFont(ofSize: 28, weight: .semibold)
        let footFont = UIFont.systemFont(ofSize: 22, weight: .regular)

        // Margins
        var y: CGFloat = 48
        let x: CGFloat = 36

        // Title
        draw(text: "Battery Monitor", in: ctx, at: CGPoint(x: x, y: y), font: titleFont, color: .white)
        y += 72

        // Body lines
        for (idx, line) in lines.enumerated() {
            let font = (idx < 6) ? bodyFont : footFont
            let color: UIColor = (idx == 0) ? .white : .systemGray2
            draw(text: line, in: ctx, at: CGPoint(x: x, y: y), font: font, color: color)
            y += (idx < 6) ? 44 : 34
        }
    }

    private func draw(text: String, in ctx: CGContext, at point: CGPoint, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)

        // CoreGraphics text drawing
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(ctx.height))
        ctx.scaleBy(x: 1, y: -1)

        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: point.x, y: CGFloat(ctx.height) - point.y - font.lineHeight)
        CTLineDraw(line, ctx)

        ctx.restoreGState()
    }

    // MARK: - Overlay text

    private func buildOverlayLines() -> [String] {
        let level = max(0.0, min(1.0, Double(UIDevice.current.batteryLevel)))
        let percent = Int((level * 100.0).rounded())

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off"
        let thermal = thermalStateString(ProcessInfo.processInfo.thermalState)

        let estimate = computeEstimate()

        let statusLine = isPiPActive ? "Status: Active" : "Status: Inactive"
        let batteryLine = "Battery: \(percent)%"
        let lowPowerLine = "Low Power Mode: \(lowPower)"
        let thermalLine = "Thermal: \(thermal)"

        let directionLine = "Trend: \(estimate.trend)"
        let remainingLine = "Est. Remaining: \(estimate.remaining)"
        let samplesLine = "Samples: \(estimate.sampleInfo)"

        let note1 = "Estimates improve the longer the app is monitoring."
        let note2 = "Keep monitoring running for better accuracy."

        return [
            statusLine,
            batteryLine,
            lowPowerLine,
            thermalLine,
            directionLine,
            remainingLine,
            samplesLine,
            note1,
            note2
        ]
    }

    private func thermalStateString(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Battery estimation

    private func recordBatterySample(at t: TimeInterval) {
        let raw = Double(UIDevice.current.batteryLevel)
        guard raw >= 0 else { return } // batteryLevel can be -1 if unavailable

        let clamped = max(0.0, min(1.0, raw))
        samples.append(.init(t: t, level: clamped))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    private func computeEstimate() -> (trend: String, remaining: String, sampleInfo: String) {
        // Need enough spread/time to be meaningful
        guard samples.count >= 4 else {
            return ("Calculating…", "Calculating…", "\(samples.count) (collecting)")
        }

        // Linear regression on (t, level)
        let xs = samples.map { $0.t }
        let ys = samples.map { $0.level }

        let n = Double(samples.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var num = 0.0
        var den = 0.0
        for i in 0..<samples.count {
            let dx = xs[i] - meanX
            num += dx * (ys[i] - meanY)
            den += dx * dx
        }

        guard den > 0 else {
            return ("Calculating…", "Calculating…", "\(samples.count) (low variance)")
        }

        let slopePerSec = num / den  // level change per second (0..1 per sec)
        let slopePerHour = slopePerSec * 3600.0

        // If slope is tiny, treat as unknown (or device not changing battery)
        if abs(slopePerHour) < 0.2 {
            let span = max(1, Int(xs.last! - xs.first!))
            return ("Stable", "N/A", "\(samples.count) over \(span)s")
        }

        let current = ys.last ?? 0.0
        let isCharging = slopePerHour > 0

        let target: Double = isCharging ? 1.0 : 0.0
        let remainingLevel = target - current
        let seconds = remainingLevel / slopePerSec

        if seconds.isNaN || !seconds.isFinite || seconds <= 0 {
            let span = max(1, Int(xs.last! - xs.first!))
            return (isCharging ? "Charging" : "Discharging", "Calculating…", "\(samples.count) over \(span)s")
        }

        let remainingStr = formatDuration(seconds)
        let trendStr = isCharging ? String(format: "Charging (%.1f%%/hr)", slopePerHour * 100.0)
                                  : String(format: "Discharging (%.1f%%/hr)", slopePerHour * 100.0)

        let span = max(1, Int(xs.last! - xs.first!))
        return (trendStr, remainingStr, "\(samples.count) over \(span)s")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60

        if h <= 0 {
            return "\(m)m"
        }
        return "\(h)h \(m)m"
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.pipStatusText = "Starting…"
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = true
            self.pipStatusText = "Active"
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.pipStatusText = "Stopping…"
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.pipStatusText = "Inactive"
        }
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.pipStatusText = "Failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

@available(iOS 15.0, *)
extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                setPlaying playing: Bool) {
        // Live overlay: ignore play/pause. We keep pushing frames.
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Live content; treat as effectively unbounded.
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // No-op
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        // Required signature (Xcode 16 / iOS 18 SDK uses `completion:`).
        completionHandler()
    }
}