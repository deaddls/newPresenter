import AppKit
import CoreVideo
import Metal
import MetalKit

/// Device, queue and pipeline shared by all screens.
final class MetalContext {
    static let shared: MetalContext? = MetalContext()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let blank: MTLTexture

    private init?() {
        // Prefer the integrated GPU so dual-GPU MacBooks don't wake the discrete one.
        let device = MTLCopyAllDevices().first { $0.isLowPower && !$0.isRemovable } ?? MTLCreateSystemDefaultDevice()
        guard let device, let queue = device.makeCommandQueue() else {
            NSLog("VGAGlitch: no Metal device")
            return nil
        }
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "glitch_vertex")
            desc.fragmentFunction = lib.makeFunction(name: "glitch_fragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("VGAGlitch: shader error: \(error)")
            return nil
        }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let blank = device.makeTexture(descriptor: td) else { return nil }
        var black: UInt32 = 0xFF00_0000
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
        self.device = device
        self.queue = queue
        self.blank = blank
    }

    /// Encodes one glitch pass into `pass`.
    func encode(_ cb: MTLCommandBuffer, pass: MTLRenderPassDescriptor, texture: MTLTexture?, params: GlitchParams) {
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        if params.visible > 0.5 {
            var p = params
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentTexture(texture ?? blank, index: 0)
            enc.setFragmentBytes(&p, length: MemoryLayout<GlitchParams>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        enc.endEncoding()
    }
}

/// Draws the glitch for one screen every display frame.
final class OverlayRenderer: NSObject, MTKViewDelegate {
    private let ctx: MetalContext
    private let scheduler: GlitchScheduler
    private let capturer: ScreenCapturer
    private var cache: CVMetalTextureCache?
    private var lastVisible = false
    private var osdShown = false

    var pxScale: Float = 2
    var debugName = ""
    private static let debug = ProcessInfo.processInfo.environment["VGAGLITCH_DEBUG"] != nil
    private var statsSince = CACurrentMediaTime()
    private var statsTicks = 0, statsDrawn = 0, statsWithFrame = 0
    var onOSD: ((Bool) -> Void)?
    /// Draw one fully transparent frame next time, regardless of the scheduler.
    var forceClear = false

    init(ctx: MetalContext, scheduler: GlitchScheduler, capturer: ScreenCapturer) {
        self.ctx = ctx
        self.scheduler = scheduler
        self.capturer = capturer
        super.init()
        CVMetalTextureCacheCreate(nil, nil, ctx.device, nil, &cache)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// VGAGLITCH_DEBUG=1: once per second, how many frames ticked / were glitched / had a capture.
    private func logStats(visible: Bool, hasFrame: Bool) {
        statsTicks += 1
        if visible { statsDrawn += 1 }
        if hasFrame { statsWithFrame += 1 }
        let now = CACurrentMediaTime()
        guard now - statsSince >= 1 else { return }
        print("[\(debugName)] ticks \(statsTicks) glitched \(statsDrawn) captured \(statsWithFrame)")
        statsSince = now
        statsTicks = 0; statsDrawn = 0; statsWithFrame = 0
    }

    func draw(in view: MTKView) {
        let frame = capturer.latestFrame()
        scheduler.hasFrame = frame != nil
        var p = scheduler.params(now: CACurrentMediaTime())
        if Self.debug { logStats(visible: p.visible > 0.5, hasFrame: frame != nil) }
        if forceClear {
            forceClear = false
            p.visible = 0
            lastVisible = true
        }

        let osd = p.osd > 0.5 && p.visible > 0.5 && Settings.osdLanguage != 2
        if osd != osdShown {
            osdShown = osd
            onOSD?(osd)
        }

        // Nothing changed since the last transparent frame: leave the layer alone.
        let visible = p.visible > 0.5
        if !visible && !lastVisible { return }
        if !visible, let cache { CVMetalTextureCacheFlush(cache, 0) }
        lastVisible = visible

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cb = ctx.queue.makeCommandBuffer() else { return }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        var texture: MTLTexture?
        var cvTexture: CVMetalTexture?
        if visible, let frame, let cache {
            let w = CVPixelBufferGetWidth(frame)
            let h = CVPixelBufferGetHeight(frame)
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, frame, nil, .bgra8Unorm, w, h, 0, &cvTexture)
            if let cvTexture { texture = CVMetalTextureGetTexture(cvTexture) }
        }
        let size = view.drawableSize
        p.width = Float(size.width)
        p.height = Float(size.height)
        p.pxScale = pxScale
        p.lines = min(1080, max(480, p.height / pxScale))
        p.hasFrame = texture != nil ? 1 : 0

        ctx.encode(cb, pass: pass, texture: texture, params: p)
        cb.present(drawable)
        // The CVMetalTexture must outlive the GPU work that samples it.
        if let cvTexture { cb.addCompletedHandler { _ in _ = cvTexture } }
        cb.commit()
    }
}
