#if VGAGLITCH2
import AppKit

/// Borderless panel above the glitch overlay. It takes clicks without
/// activating the app, so the presentation keeps keyboard focus.
final class PollPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hansjörg Stützle above a "Bargeld abschaffen?" poll card. Laid out in fixed
/// points (`base`) and scaled to whatever size the panel has.
final class PollView: NSView {
    enum Answer { case none, thanks, wrong }

    static let base = NSSize(width: 452, height: 486)
    private static let pad: CGFloat = 16
    private static let card = NSRect(x: pad, y: pad, width: 420, height: 230)
    private static let photoRect = NSRect(x: pad + 30, y: pad + 200, width: 360, height: 360 * 617 / 877)
    private static let noButton = NSRect(x: pad + 18, y: pad + 88, width: 384, height: 56)
    private static let yesButton = NSRect(x: pad + 18, y: pad + 18, width: 384, height: 56)
    private static let green = NSColor(srgbRed: 0.12, green: 0.62, blue: 0.27, alpha: 1)
    private static let red = NSColor(srgbRed: 0.85, green: 0.13, blue: 0.13, alpha: 1)
    private static let photo = Bundle.main.url(forResource: "stuetzle", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var answer = Answer.none {
        didSet { needsDisplay = true }
    }
    var onAnswer: ((Bool) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let s = bounds.width / Self.base.width
        NSGraphicsContext.current?.cgContext.scaleBy(x: s, y: s)

        // The card covers the straight bottom edge of the cutout.
        Self.photo?.draw(in: Self.photoRect)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: Self.card, xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.restoreGraphicsState()

        let card = Self.card
        drawCentered("● LIVE-UMFRAGE", in: NSRect(x: card.minX, y: card.minY + 196, width: card.width, height: 24),
                     font: .systemFont(ofSize: 13, weight: .bold), color: NSColor(white: 0.45, alpha: 1))
        let (title, color): (String, NSColor) = switch answer {
        case .none: ("BARGELD ABSCHAFFEN?", .black)
        case .thanks: ("DANKE! 💶", Self.green)
        case .wrong: ("FALSCHE ANTWORT!", Self.red)
        }
        drawCentered(title, in: NSRect(x: card.minX, y: card.minY + 150, width: card.width, height: 46),
                     font: .systemFont(ofSize: 29, weight: .heavy), color: color)

        drawButton(Self.noButton, "NEIN, BARGELD DAUERHAFT ERHALTEN!", Self.green)
        drawButton(Self.yesButton, "JA, NUR NOCH KARTE !!!", Self.red)
    }

    private func drawButton(_ rect: NSRect, _ label: String, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        drawCentered(label, in: rect, font: .systemFont(ofSize: 17, weight: .bold), color: .white)
    }

    private func drawCentered(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let s = bounds.width / Self.base.width
        let p = convert(event.locationInWindow, from: nil)
        let q = NSPoint(x: p.x / s, y: p.y / s)
        if Self.noButton.contains(q) {
            onAnswer?(true)
        } else if Self.yesButton.contains(q) {
            onAnswer?(false)
        }
    }

    func shake() {
        wantsLayer = true
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -14, 14, -10, 10, -5, 5, 0]
        a.duration = 0.45
        layer?.add(a, forKey: "shake")
    }
}

/// One poll panel on one screen: fades in at the top right, hides again on its own.
final class PollPopup {
    private let panel = PollPanel()
    private let view = PollView()
    private var hideWork: DispatchWorkItem?
    private var resetWork: DispatchWorkItem?

    init() {
        panel.contentView = view
        view.onAnswer = { [weak self] keepCash in self?.answered(keepCash) }
    }

    func show(on screen: NSScreen, for duration: Double) {
        let w = min(460, max(300, screen.frame.width * 0.26))
        let size = NSSize(width: w, height: w * PollView.base.height / PollView.base.width)
        let margin = w * 0.05
        let target = NSRect(x: screen.frame.maxX - size.width - margin,
                            y: screen.visibleFrame.maxY - size.height - margin,
                            width: size.width, height: size.height)
        view.answer = .none
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(target.offsetBy(dx: margin, dy: 0), display: false)
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
        hide(after: duration)
    }

    func hide(animated: Bool = true) {
        hideWork?.cancel()
        resetWork?.cancel()
        guard panel.isVisible else { return }
        guard animated else {
            panel.orderOut(nil)
            return
        }
        let margin = panel.frame.width * 0.05
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panel.frame.offsetBy(dx: margin, dy: 0), display: true)
        }, completionHandler: { [panel] in
            // A show() during the fade-out brings it back to full alpha; keep it then.
            if panel.alphaValue < 0.01 { panel.orderOut(nil) }
        })
    }

    private func hide(after delay: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func answered(_ keepCash: Bool) {
        resetWork?.cancel()
        if keepCash {
            view.answer = .thanks
            hide(after: 1.3)
        } else {
            view.answer = .wrong
            view.shake()
            let work = DispatchWorkItem { [weak self] in self?.view.answer = .none }
            resetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        }
    }

    /// Offline rendering for --render-test.
    static func snapshot(width: CGFloat) -> CGImage? {
        let view = PollView(frame: NSRect(x: 0, y: 0, width: width, height: width * PollView.base.height / PollView.base.width))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }
}

/// Pops the poll up now and then on the glitched screens while the app runs.
final class PollController {
    private var popups: [CGDirectDisplayID: PollPopup] = [:]
    private var timer: Timer?
    private let screens: () -> [CGDirectDisplayID: NSScreen]

    init(screens: @escaping () -> [CGDirectDisplayID: NSScreen]) {
        self.screens = screens
    }

    func start() {
        schedule(after: Double.random(in: 10...30) * Settings.gapFactor)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        popups.values.forEach { $0.hide(animated: false) }
        popups.removeAll()
    }

    func show() {
        let duration = Double.random(in: 8...14)
        for (id, screen) in screens() {
            let popup = popups[id] ?? PollPopup()
            popups[id] = popup
            popup.show(on: screen, for: duration)
        }
    }

    private func schedule(after delay: Double) {
        timer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if Settings.pollEnabled { self.show() }
            self.schedule(after: Double.random(in: 25...90) * Settings.gapFactor)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
#endif
