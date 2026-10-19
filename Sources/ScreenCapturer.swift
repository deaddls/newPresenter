import AppKit
import CoreMedia
import ScreenCaptureKit

/// Streams the live content of one display (without our own overlay windows).
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    let displayID: CGDirectDisplayID

    private let queue = DispatchQueue(label: "vgaglitch.capture", qos: .userInteractive)
    private let lock = NSLock()
    private var frame: CVPixelBuffer?
    private var activeStream: SCStream?   // guarded by lock
    private var generation = 0            // main thread only
    private var size = (0, 0)
    private var wantsRunning = false
    private var failures = 0              // consecutive restarts, for back-off

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    func latestFrame() -> CVPixelBuffer? {
        locked { frame }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func start(width: Int, height: Int) {
        failures = 0
        begin(width: width, height: height)
    }

    private func begin(width: Int, height: Int) {
        stop()
        wantsRunning = true
        size = (width, height)
        generation += 1
        let gen = generation
        let pid = ProcessInfo.processInfo.processIdentifier

        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let self else { return }
                guard let display = content.displays.first(where: { $0.displayID == self.displayID }) else {
                    NSLog("VGAGlitch: display \(self.displayID) not found for capture")
                    return
                }
                let mine = content.applications.filter { $0.processID == pid }
                guard !mine.isEmpty else {
                    // Capturing without excluding our overlay would feed it back into itself.
                    NSLog("VGAGlitch: own app not listed yet, retrying capture")
                    await MainActor.run { self.scheduleRestart(after: 0.5, gen: gen) }
                    return
                }
                // Keep our own menu bar icon (and anything else below the overlay) in the picture,
                // otherwise it would vanish from the menu bar during every glitch.
                let keep = content.windows.filter {
                    $0.owningApplication?.processID == pid && $0.windowLayer < Int(CGShieldingWindowLevel())
                }
                let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: keep)

                let cfg = SCStreamConfiguration()
                cfg.width = width
                cfg.height = height
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.colorSpaceName = CGColorSpace.sRGB
                cfg.showsCursor = false
                cfg.queueDepth = 6

                let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                // stop() or a newer start() may have happened while we were waiting
                guard await MainActor.run(body: { gen == self.generation }) else { return }
                self.locked { self.activeStream = stream }
                try await stream.startCapture()

                await MainActor.run {
                    if gen != self.generation { self.stopStream(stream) } else { self.failures = 0 }
                }
            } catch {
                NSLog("VGAGlitch: screen capture failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        wantsRunning = false
        generation += 1
        lock.lock()
        let stream = activeStream
        activeStream = nil
        frame = nil
        lock.unlock()
        if let stream { stopStream(stream) }
    }

    private func stopStream(_ stream: SCStream) {
        lock.lock()
        if activeStream === stream { activeStream = nil }
        lock.unlock()
        Task { try? await stream.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let infos = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = infos.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        lock.lock()
        if activeStream === stream { frame = buffer }
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("VGAGlitch: capture stopped: \(error.localizedDescription)")
        // The user stopped the capture from the menu bar: respect that.
        if (error as? SCStreamError)?.code == .userStopped { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.locked({ self.activeStream === stream }) else { return }
            self.scheduleRestart(after: 1, gen: self.generation)
        }
    }

    /// Main thread only. Retries a few times with growing pauses, then gives up
    /// (overlay effects keep working without a captured picture).
    private func scheduleRestart(after delay: Double, gen: Int) {
        guard failures < 6 else { return }
        failures += 1
        let wait = delay * Double(failures)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.wantsRunning, gen == self.generation else { return }
            self.begin(width: self.size.0, height: self.size.1)
        }
    }
}
