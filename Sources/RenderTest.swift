import AppKit
import ImageIO
import Metal
import UniformTypeIdentifiers

/// Offline preview: renders every effect and episode onto a fake slide and
/// writes PNGs, so the look can be checked without capturing the real screen.
/// Usage: VGAGlitch --render-test <output-dir>
enum RenderTest {
    static func run(outputDirectory: String) -> Bool {
        guard let ctx = MetalContext.shared else {
            print("no Metal device")
            return false
        }
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let w = 1280, h = 800
        guard let slide = makeSlide(width: w, height: h), let source = texture(from: slide, ctx: ctx) else { return false }
        save(slide, to: dir.appendingPathComponent("00-original.png"))

        let kinds: [(String, EffectKind)] = [
            ("blue", .blue), ("tear", .tear), ("jitter", .jitter), ("vroll", .vroll),
            ("blocks", .blocks), ("resync", .resync), ("channel", .channel), ("tint", .tint), ("chroma", .chroma),
            ("ghost", .ghost), ("washout", .washout), ("sparkle", .sparkle), ("snow", .snow),
            ("interference", .interference), ("dropout", .dropout), ("shake", .shake),
            ("offset", .offset), ("pixelClock", .pixelClock),
        ]
        for (name, kind) in kinds {
            // Pick a moment where the (often flickering) effect is actually on.
            var best = GlitchParams()
            for attempt in 0..<20 {
                let e = Effect(kind, start: 0, duration: 1, intensity: 1)
                var p = GlitchParams()
                let now = 0.3 + Double(attempt) * 0.02
                e.apply(to: &p, now: now)
                p.time = Float(now)
                best = p
                if differsFromNeutral(p) { break }
            }
            best.visible = 1
            guard let img = render(ctx, source: source, params: best, width: w, height: h, pxScale: 1) else { return false }
            save(img, to: dir.appendingPathComponent("effect-\(name).png"))
        }

        // One contact sheet per episode: 24 frames over its whole duration.
        let cols = 6, rows = 4, tw = 320, th = 200
        for episode in Episode.allCases {
            let effects = episode.build(at: 0, k: 1, hasFrame: true)
            let end = effects.map(\.end).max() ?? 1
            guard let sheet = CGContext(data: nil, width: cols * tw, height: rows * th, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            sheet.setFillColor(gray: 0.5, alpha: 1)
            sheet.fill(CGRect(x: 0, y: 0, width: cols * tw, height: rows * th))
            for i in 0..<(cols * rows) {
                let now = end * Double(i) / Double(cols * rows - 1) * 0.999
                var p = GlitchParams()
                p.time = Float(now)
                var any = false
                for e in effects where e.start <= now && now < e.end {
                    e.apply(to: &p, now: now)
                    any = true
                }
                p.visible = any ? 1 : 0
                guard let frame = render(ctx, source: source, params: p, width: tw * 2, height: th * 2, pxScale: 1) else { return false }
                let x = (i % cols) * tw, y = (rows - 1 - i / cols) * th
                // transparent = real screen shows through
                sheet.draw(slide, in: CGRect(x: x + 1, y: y + 1, width: tw - 2, height: th - 2))
                sheet.draw(frame, in: CGRect(x: x + 1, y: y + 1, width: tw - 2, height: th - 2))
            }
            if let img = sheet.makeImage() {
                save(img, to: dir.appendingPathComponent("episode-\(episode.rawValue).png"))
            }
        }
        // projector blue with the "no signal" box on top
        var bp = GlitchParams()
        bp.visible = 1
        bp.blue = 1
        if let blue = render(ctx, source: source, params: bp, width: w, height: h, pxScale: 1),
           let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            let view = OSDView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            c.draw(blue, in: CGRect(x: 0, y: 0, width: w, height: h))
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let osd = rep.cgImage { c.draw(osd, in: CGRect(x: 0, y: 0, width: w, height: h)) }
            }
            if let img = c.makeImage() { save(img, to: dir.appendingPathComponent("osd.png")) }
        }
        print("wrote previews to \(dir.path)")
        return true
    }

    private static func differsFromNeutral(_ p: GlitchParams) -> Bool {
        let n = GlitchParams()
        return withUnsafeBytes(of: p) { a in
            withUnsafeBytes(of: n) { b in
                // skip the leading `time` field
                !a.dropFirst(4).elementsEqual(b.dropFirst(4))
            }
        }
    }

    private static func render(_ ctx: MetalContext, source: MTLTexture, params: GlitchParams,
                               width: Int, height: Int, pxScale: Float) -> CGImage? {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget]
        td.storageMode = .managed
        guard let target = ctx.device.makeTexture(descriptor: td), let cb = ctx.queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store

        var p = params
        p.width = Float(width)
        p.height = Float(height)
        p.pxScale = pxScale * Float(width) / 1280
        p.lines = min(1080, max(480, p.height / p.pxScale))
        p.hasFrame = 1
        ctx.encode(cb, pass: pass, texture: source, params: p)
        if let blit = cb.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        cb.commit()
        cb.waitUntilCompleted()

        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        target.getBytes(&data, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return data.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?
                .makeImage()
        }
    }

    private static func texture(from image: CGImage, ctx: MetalContext) -> MTLTexture? {
        let w = image.width, h = image.height
        guard let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        cg.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        guard let tex = ctx.device.makeTexture(descriptor: td), let data = cg.data else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        return tex
    }

    /// A plausible presentation slide: title bar, bullets, a bar chart.
    private static func makeSlide(width: Int, height: Int) -> CGImage? {
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let W = CGFloat(width), H = CGFloat(height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()
        NSColor(calibratedRed: 0.08, green: 0.2, blue: 0.45, alpha: 1).setFill()
        NSRect(x: 0, y: H - 130, width: W, height: 130).fill()
        "Quartalsergebnisse Q3".draw(at: NSPoint(x: 60, y: H - 95), withAttributes: [
            .font: NSFont.systemFont(ofSize: 52, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let bullets = ["• Umsatz +18 % gegenüber Vorjahr", "• Neue Märkte: Österreich, Schweiz",
                       "• Kundenzufriedenheit 4,7 / 5", "• Nächste Schritte: Roadmap 2027"]
        for (i, b) in bullets.enumerated() {
            b.draw(at: NSPoint(x: 70, y: H - 220 - CGFloat(i) * 62), withAttributes: [
                .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
            ])
        }
        let colors: [NSColor] = [.systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple]
        let values: [CGFloat] = [0.45, 0.6, 0.52, 0.8, 0.95]
        for (i, v) in values.enumerated() {
            colors[i].setFill()
            NSRect(x: 760 + CGFloat(i) * 92, y: 80, width: 64, height: 480 * v).fill()
        }
        NSColor.black.setFill()
        NSRect(x: 740, y: 78, width: 480, height: 3).fill()
        "Beispiel GmbH · Vertraulich".draw(at: NSPoint(x: 60, y: 30), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.gray,
        ])
        NSGraphicsContext.restoreGraphicsState()
        return cg.makeImage()
    }

    private static func save(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
