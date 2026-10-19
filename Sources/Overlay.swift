import AppKit
import MetalKit

/// Borderless, click-through window above everything else, including full screen apps.
final class OverlayWindow: NSWindow {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Imitation of a projector's on-screen "no signal" message.
final class OSDView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let english = Settings.osdLanguage == 1
        let title = english ? "No Signal" : "Kein Signal"
        let subtitle = english ? "Input: VGA (Computer 1)" : "Eingang: VGA (Computer 1)"

        let w = min(560, bounds.width * 0.42)
        let h = w * 0.27
        let box = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        NSColor(calibratedRed: 0, green: 0, blue: 0.1, alpha: 0.55).setFill()
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.75).setStroke()
        path.lineWidth = 2
        path.stroke()

        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: h * 0.3, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: center,
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: h * 0.14, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.85),
            .paragraphStyle: center,
        ]
        title.draw(in: NSRect(x: box.minX, y: box.minY + h * 0.38, width: w, height: h * 0.45), withAttributes: titleAttrs)
        subtitle.draw(in: NSRect(x: box.minX, y: box.minY + h * 0.12, width: w, height: h * 0.25), withAttributes: subAttrs)
    }
}

/// Calls `tick` once per refresh of a screen; the overlay renders on this beat
/// instead of MTKView's own loop, so start and stop are fully under our control.
final class FrameTicker: NSObject {
    private let tick: () -> Void
    private let screen: NSScreen
    private var link: AnyObject?
    private var timer: Timer?

    init(screen: NSScreen, tick: @escaping () -> Void) {
        self.screen = screen
        self.tick = tick
    }

    var isRunning: Bool { link != nil || timer != nil }

    func start() {
        stop()
        // VGAGLITCH_TIMER=1 forces the timer, e.g. to test while the display sleeps
        let forceTimer = ProcessInfo.processInfo.environment["VGAGLITCH_TIMER"] != nil
        if #available(macOS 14.0, *), !forceTimer {
            let l = screen.displayLink(target: self, selector: #selector(fire))
            l.add(to: .main, forMode: .common)
            link = l
        } else {
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func stop() {
        if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
        link = nil
        timer?.invalidate()
        timer = nil
    }

    @objc private func fire() { tick() }
}

/// Everything needed to glitch one display: window, Metal view, capture and scheduler.
final class ScreenOverlay {
    let displayID: CGDirectDisplayID
    private(set) var screen: NSScreen
    let scheduler = GlitchScheduler()

    private let window: OverlayWindow
    private let mtkView: MTKView
    private let osdView: OSDView
    private let capturer: ScreenCapturer
    private let renderer: OverlayRenderer
    private var ticker: FrameTicker?

    init?(screen: NSScreen, displayID: CGDirectDisplayID) {
        guard let ctx = MetalContext.shared else { return nil }
        self.screen = screen
        self.displayID = displayID

        window = OverlayWindow(frame: screen.frame)
        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let container = NSView(frame: bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        mtkView = MTKView(frame: bounds, device: ctx.device)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = true          // driven by FrameTicker
        mtkView.layer?.isOpaque = false
        (mtkView.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)

        osdView = OSDView(frame: bounds)
        osdView.autoresizingMask = [.width, .height]
        osdView.wantsLayer = true
        osdView.isHidden = true

        container.addSubview(mtkView)
        container.addSubview(osdView)
        window.contentView = container

        capturer = ScreenCapturer(displayID: displayID)
        renderer = OverlayRenderer(ctx: ctx, scheduler: scheduler, capturer: capturer)
        renderer.pxScale = Float(screen.backingScaleFactor)
        renderer.debugName = screen.localizedName
        renderer.onOSD = { [weak osdView] show in
            osdView?.needsDisplay = true
            osdView?.isHidden = !show
        }
        mtkView.delegate = renderer
        ticker = FrameTicker(screen: screen) { [weak self] in self?.mtkView.draw() }
    }

    private var pixelSize: (Int, Int) {
        let s = screen.backingScaleFactor
        return (Int(screen.frame.width * s), Int(screen.frame.height * s))
    }

    func start() {
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        scheduler.start(now: CACurrentMediaTime())
        ticker?.start()
        if ProcessInfo.processInfo.environment["VGAGLITCH_DEBUG"] != nil {
            print("[\(screen.localizedName)] window visible \(window.isVisible) occlusion \(window.occlusionState.rawValue) level \(window.level.rawValue)")
        }
        // Without the permission every capture attempt would only raise another system prompt.
        if CGPreflightScreenCaptureAccess() {
            let (w, h) = pixelSize
            capturer.start(width: w, height: h)
        }
    }

    func stop() {
        scheduler.stop()
        osdView.isHidden = true
        ticker?.stop()
        // Present a transparent frame so a stale glitch never flashes up on the next start.
        renderer.forceClear = true
        mtkView.draw()
        window.orderOut(nil)
        capturer.stop()
    }

    func burst() {
        scheduler.burst(now: CACurrentMediaTime())
    }

    /// The display was resized or moved.
    func update(screen: NSScreen) {
        let changed = screen.frame != self.screen.frame || screen.backingScaleFactor != self.screen.backingScaleFactor
        self.screen = screen
        guard changed else { return }
        window.setFrame(screen.frame, display: true)
        renderer.pxScale = Float(screen.backingScaleFactor)
        let wasTicking = ticker?.isRunning ?? false
        ticker?.stop()
        ticker = FrameTicker(screen: screen) { [weak self] in self?.mtkView.draw() }
        if wasTicking { ticker?.start() }
        if scheduler.running && CGPreflightScreenCaptureAccess() {
            let (w, h) = pixelSize
            capturer.start(width: w, height: h)
        }
    }
}

/// Owns the overlays for all target screens and switches the glitching on and off.
final class GlitchController {
    private(set) var running = false
    private var overlays: [CGDirectDisplayID: ScreenOverlay] = [:]

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.syncScreens()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        syncScreens()
    }

    func stop() {
        guard running else { return }
        running = false
        overlays.values.forEach { $0.stop() }
        overlays.removeAll()
    }

    func burst() {
        overlays.values.forEach { $0.burst() }
    }

    /// Adds, updates or removes overlays to match the connected screens and the screen setting.
    func syncScreens() {
        guard running else { return }
        let wanted = targetScreens()
        for (id, overlay) in overlays where wanted[id] == nil {
            overlay.stop()
            overlays[id] = nil
        }
        for (id, screen) in wanted {
            if let overlay = overlays[id] {
                overlay.update(screen: screen)
            } else if let overlay = ScreenOverlay(screen: screen, displayID: id) {
                overlays[id] = overlay
                overlay.start()
            }
        }
    }

    /// Only projectors / external displays, never the built-in screen on its own.
    private func targetScreens() -> [CGDirectDisplayID: NSScreen] {
        var result: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  reachesExternalDisplay(id) else { continue }
            result[id] = screen
        }
        return result
    }

    /// With mirroring macOS lists one screen for the whole mirror set, usually the
    /// built-in one; it counts if an external display mirrors it.
    private func reachesExternalDisplay(_ id: CGDirectDisplayID) -> Bool {
        if CGDisplayIsBuiltin(id) == 0 { return true }
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).contains { CGDisplayMirrorsDisplay($0) == id && CGDisplayIsBuiltin($0) == 0 }
    }
}
