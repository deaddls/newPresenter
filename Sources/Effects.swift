import Foundation

enum EffectKind {
    case blue, black, white, osd
    case tear, jitter, shake, vroll, blocks, resync, offset, pixelClock
    case channel, tint, chroma, ghost, washout
    case sparkle, snow, interference, dropout
}

/// Deterministic pseudo random value in 0..<1 for a time bucket and a seed,
/// so a flickering effect keeps its state for the whole bucket.
func hash01(_ bucket: Double, _ seed: Float) -> Float {
    var x = UInt64(bitPattern: Int64(bucket)) &* 0x9E37_79B9_7F4A_7C15
    x ^= UInt64(seed.bitPattern) &* 0xBF58_476D_1CE4_E5B9
    x ^= x >> 31
    x &*= 0x94D0_49BB_1331_11EB
    x ^= x >> 29
    return Float(x >> 40) / Float(1 << 24)
}

func rr(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }

/// One effect with a fixed start, duration and its own random character.
struct Effect {
    let kind: EffectKind
    let start: Double
    let duration: Double
    let k: Float
    let r: [Float]
    let seed: Float

    init(_ kind: EffectKind, start: Double, duration: Double, intensity: Float) {
        self.kind = kind
        self.start = start
        self.duration = max(0.016, duration)
        self.k = intensity
        self.r = (0..<8).map { _ in Float.random(in: 0...1) }
        self.seed = Float.random(in: 0...10_000).rounded()
    }

    var end: Double { start + duration }

    private func gate(_ now: Double, rate: Double, density: Float, salt: Float) -> Float {
        hash01(floor(now * rate), seed + salt) < density ? 1 : 0
    }

    private func rnd(_ now: Double, rate: Double, salt: Float) -> Float {
        hash01(floor(now * rate), seed + salt)
    }

    func apply(to p: inout GlitchParams, now: Double) {
        let el = now - start
        let ph = Float(max(0, min(1, el / duration)))

        switch kind {
        case .blue:
            // the signal often stutters in and out before it is really gone
            var on: Float = 1
            if r[0] < 0.45, ph < 0.12 || ph > 0.9 { on = gate(now, rate: 35, density: 0.55, salt: 1) }
            p.blue = max(p.blue, on)
            p.blueTone = r[1]

        case .black:
            let on: Float = r[0] < 0.3 ? gate(now, rate: 40, density: 0.7, salt: 1) : 1
            p.black = max(p.black, on)

        case .white:
            p.white = max(p.white, k * 0.85 * (1 - ph))

        case .osd:
            p.osd = 1

        case .tear:
            let b = floor(now * (6 + Double(r[0]) * 20))
            var y = r[1] + Float(el) * (r[2] - 0.5) * 1.2
            if hash01(b, seed) > 0.6 { y += hash01(b, seed + 1) }
            p.tearOn = 1
            p.tearY = y - floor(y)
            let shift = (hash01(b, seed + 2) - 0.5) * 0.35 * k
            if abs(shift) > abs(p.tearShift) { p.tearShift = shift }
            p.tearSlope = r[3] < 0.5 ? 0 : (r[3] - 0.75) * 0.4 * k
            p.lineJitter += 0.004 * k

        case .jitter:
            p.lineJitter += (0.002 + 0.012 * r[0]) * k
            p.pixelPhase += (1 + 3 * r[1]) * k
            p.shakeX += (hash01(floor(now * 60), seed) - 0.5) * 6 * k * r[2]

        case .shake:
            let f = floor(now * Double(20 + r[0] * 40))
            p.shakeX += (hash01(f, seed) - 0.5) * 2 * (3 + 12 * r[1]) * k
            p.shakeY += (hash01(f, seed + 1) - 0.5) * 2 * (2 + 8 * r[2]) * k

        case .vroll:
            if r[0] < 0.6 {
                // lost vertical hold: picture rolls, then locks again with a snap
                let dir: Float = r[2] < 0.7 ? 1 : -1
                let speed = (0.5 + 2.5 * r[1]) * dir
                p.vroll += speed * Float(duration) / .pi * (1 - cos(.pi * ph))
            } else {
                let b = floor(now * Double(6 + 14 * r[1]))
                p.vroll += hash01(b, seed) < 0.25 ? 0 : (hash01(b, seed + 1) - 0.5) * 0.8 * k
            }
            p.vrollBar = max(p.vrollBar, 0.03 + 0.07 * r[3])

        case .blocks:
            p.blockShift = max(p.blockShift, (0.02 + 0.18 * r[0]) * k)
            p.blockRate = 8 + 25 * r[1]
            p.chroma = max(p.chroma, 2 * k)

        case .resync:
            // projector auto-adjust: picture misplaced, then snaps into place in steps
            let steps = 2 + Int(r[0] * 3)
            let pos = ph * Float(steps + 1)
            let idx = min(Float(steps), floor(pos))
            let f = 1 - idx / Float(steps)
            p.offsetX += (r[1] - 0.5) * 0.18 * f
            p.offsetY += (r[2] - 0.5) * 0.08 * f
            p.scaleX *= 1 + (r[3] - 0.5) * 0.25 * f
            p.scaleY *= 1 + (r[4] - 0.5) * 0.12 * f
            if idx > 0, pos - idx < 0.12 { p.black = max(p.black, 1) }

        case .offset:
            // picture sits in the wrong place for a while, with the odd twitch
            let b = floor(now * 12)
            let twitch: Float = hash01(b, seed) > 0.9 ? (hash01(b, seed + 1) - 0.5) * 0.02 : 0
            p.offsetX += (r[0] - 0.5) * 0.1 * k + twitch
            p.offsetY += (r[1] - 0.5) * 0.03 * k
            p.scaleX *= 1 + (r[2] - 0.5) * 0.06 * k

        case .pixelClock:
            p.clockAmt = max(p.clockAmt, (0.5 + 0.5 * r[0]) * k)
            p.clockBands = 3 + 10 * r[1]

        case .channel:
            // loose pin: one colour line drops out, often flickering
            let rate = 5 + Double(r[3]) * 22
            let density: Float = r[1] > 0.45 ? 1 : 0.35 + 0.5 * r[2]
            guard gate(now, rate: rate, density: density, salt: 7) > 0 else { break }
            let residual = r[4] * 0.2
            switch r[0] {
            case ..<0.28: p.chanR = min(p.chanR, residual)
            case ..<0.62: p.chanG = min(p.chanG, residual)
            case ..<0.85: p.chanB = min(p.chanB, residual)
            default:
                let keep = Int(r[5] * 2.999)
                if keep != 0 { p.chanR = min(p.chanR, residual) }
                if keep != 1 { p.chanG = min(p.chanG, residual) }
                if keep != 2 { p.chanB = min(p.chanB, residual) }
            }

        case .tint:
            let w = 0.55 + 0.25 * r[1]
            switch Int(r[0] * 2.999) {
            case 0: p.chanR *= w
            case 1: p.chanG *= w
            default: p.chanB *= w
            }
            p.brightness += (r[2] - 0.5) * 0.06

        case .chroma:
            p.chroma = max(p.chroma, (1.5 + 5 * r[0]) * k)

        case .ghost:
            let wave = 0.75 + 0.25 * sin(Float(el) * (2 + 4 * r[4]))
            p.ghost = max(p.ghost, (0.45 + 0.55 * r[0]) * k * wave)
            p.ghostOffset = 4 + 20 * r[1]
            p.smear = max(p.smear, (0.25 + 0.6 * r[2]) * k)
            p.smearLen = 6 + 30 * r[3]

        case .washout:
            let g = 0.5 + 0.5 * rnd(now, rate: 15, salt: 8)
            if r[1] > 0.6 {
                p.contrast *= 1 + (0.5 + 0.8 * r[0]) * k * g
            } else {
                p.contrast *= 1 - (0.25 + 0.35 * r[0]) * k * g
                p.brightness += (0.05 + 0.2 * r[2]) * k * g
            }
            p.saturation *= max(0, 1 - (0.2 + 0.5 * r[3]) * k)

        case .sparkle:
            let g = gate(now, rate: 25, density: 0.5 + 0.5 * r[3], salt: 4)
            p.sparkle += (0.4 + 0.8 * r[0]) * k * g
            p.streaks += (0.3 + 0.9 * r[1]) * k * gate(now, rate: 18, density: 0.4 + 0.6 * r[4], salt: 5)
            p.streakRate = 15 + 45 * r[2]

        case .snow:
            p.snow = max(p.snow, (0.15 + 0.5 * r[0]) * k * gate(now, rate: 30, density: 0.75, salt: 6))

        case .interference:
            p.humBar = max(p.humBar, (0.08 + 0.25 * r[0]) * k)
            p.humSpeed = (0.1 + 0.7 * r[1]) * (r[5] < 0.5 ? -1 : 1)
            p.interference = max(p.interference, (0.2 + 0.7 * r[2]) * k)
            p.scanlines = max(p.scanlines, 0.4 * r[6] * k)

        case .dropout:
            let b = floor(now * Double(12 + 20 * r[0]))
            p.dropout = max(p.dropout, k * (hash01(b, seed) < 0.75 ? 1 : 0))
            p.dropoutY = hash01(b, seed + 1)
            p.dropoutH = 0.01 + 0.14 * hash01(b, seed + 2)
            p.dropoutWhite = hash01(b, seed + 3) > 0.6 ? 1 : 0
        }
    }
}

/// Collects effects for one episode relative to its start time.
struct EpisodeBuilder {
    let t0: Double
    let k: Float
    var effects: [Effect] = []

    mutating func add(_ kind: EffectKind, _ offset: Double, _ duration: Double, _ kMul: Float = 1) {
        effects.append(Effect(kind, start: t0 + offset, duration: duration, intensity: min(1.5, k * kMul)))
    }
}

/// A realistic "something is wrong with the cable" moment, built from several effects.
enum Episode: String, CaseIterable {
    case signalLoss, blueFlash, tear, roll, colorPin, ghosting
    case whiteNoise, snowBurst, blackFlicker, interference, blocks, washout, cableWiggle
    case clockPhase, misaligned

    /// Episodes that only distort the captured picture are useless without one.
    var needsFrame: Bool {
        switch self {
        case .signalLoss, .blueFlash, .whiteNoise, .snowBurst, .blackFlicker: return false
        default: return true
        }
    }

    private var isHeavy: Bool {
        switch self {
        case .signalLoss, .roll, .cableWiggle, .snowBurst, .washout: return true
        default: return false
        }
    }

    func weight(level: Int) -> Double {
        let base: Double
        switch self {
        case .signalLoss: base = 7
        case .blueFlash: base = 9
        case .tear: base = 12
        case .roll: base = 5
        case .colorPin: base = 11
        case .ghosting: base = 6
        case .whiteNoise: base = 12
        case .snowBurst: base = 4
        case .blackFlicker: base = 8
        case .interference: base = 5
        case .blocks: base = 7
        case .washout: base = 3
        case .cableWiggle: base = 12
        case .clockPhase: base = 5
        case .misaligned: base = 4
        }
        guard isHeavy else { return base }
        return base * [0.4, 1.0, 1.5][max(0, min(2, level))]
    }

    func build(at t0: Double, k: Float, hasFrame: Bool) -> [Effect] {
        var b = EpisodeBuilder(t0: t0, k: k)
        switch self {
        case .signalLoss:
            let pre = rr(0.03, 0.15)
            b.add(.black, 0, pre)
            let blue = rr(0.6, 2.8)
            b.add(.blue, pre, blue)
            if blue > 1.4 && chance(0.6) {
                let s = rr(0.5, 0.9)
                b.add(.osd, pre + s, blue - s)
            }
            if hasFrame {
                var t = pre + blue
                let blank = rr(0.04, 0.2)
                b.add(.black, t, blank)
                t += blank
                let rs = rr(0.35, 1.1)
                b.add(.resync, t, rs)
                if chance(0.35) { b.add(.vroll, t, rs * 0.6) }
                if chance(0.4) { b.add(.jitter, t, rs, 0.7) }
            }

        case .blueFlash:
            var t = 0.0
            for _ in 0..<Int.random(in: 1...3) {
                let d = rr(0.04, 0.28)
                b.add(.blue, t, d)
                t += d
                if hasFrame && chance(0.4) {
                    let g = rr(0.03, 0.15)
                    b.add(.tear, t, g)
                    b.add(.jitter, t, g)
                }
                t += rr(0.05, 0.35)
            }

        case .tear:
            let d = rr(0.15, 1.4)
            b.add(.tear, 0, d)
            b.add(.jitter, 0, d, 0.7)
            if chance(0.3) { b.add(.sparkle, 0, d, 0.5) }

        case .roll:
            var t = 0.0
            if chance(0.3) {
                t = rr(0.04, 0.12)
                b.add(.black, 0, t)
            }
            let d = rr(0.4, 2.2)
            b.add(.vroll, t, d)
            if chance(0.4) { b.add(.resync, t + d, rr(0.3, 0.7)) }

        case .colorPin:
            let d = chance(0.15) ? rr(5, 12) : rr(0.4, 5)
            b.add(.channel, 0, d)
            if chance(0.3) { b.add(.ghost, 0, d * 0.5, 0.6) }

        case .ghosting:
            let d = rr(1.5, 6)
            b.add(.ghost, 0, d)
            if chance(0.4) { b.add(.sparkle, 0, d, 0.4) }
            if chance(0.3) { b.add(.tint, 0, d) }

        case .whiteNoise:
            let d = rr(0.2, 2.5)
            b.add(.sparkle, 0, d)
            if hasFrame && chance(0.5) { b.add(.jitter, 0, d, 0.6) }
            if chance(0.25) { b.add(.dropout, rr(0, d * 0.5), min(d, rr(0.05, 0.3))) }

        case .snowBurst:
            let d = rr(0.05, 0.45)
            if chance(0.5) { b.add(.white, 0, 0.1) }
            b.add(.snow, 0, d)
            if chance(0.4) { b.add(.black, d, rr(0.04, 0.2)) }

        case .blackFlicker:
            var t = 0.0
            for _ in 0..<Int.random(in: 1...4) {
                let d = rr(0.03, 0.18)
                b.add(.black, t, d)
                t += d + rr(0.04, 0.3)
            }
            if hasFrame && chance(0.3) { b.add(.resync, t, rr(0.3, 0.6)) }

        case .interference:
            let d = rr(1, 4)
            b.add(.interference, 0, d)

        case .blocks:
            let d = rr(0.1, 0.7)
            b.add(.blocks, 0, d)
            if chance(0.4) { b.add(.dropout, 0, d) }

        case .washout:
            let d = rr(0.3, 2)
            b.add(.washout, 0, d)
            if chance(0.3) { b.add(.white, 0, 0.12) }

        case .clockPhase:
            let d = rr(2, 8)
            b.add(.pixelClock, 0, d)
            if chance(0.3) { b.add(.jitter, 0, d, 0.3) }

        case .misaligned:
            let pre = rr(0.04, 0.15)
            b.add(.black, 0, pre)
            let d = rr(1.5, 6)
            b.add(.offset, pre, d)
            if chance(0.4) { b.add(.pixelClock, pre, d, 0.6) }
            b.add(.black, pre + d, rr(0.05, 0.15))

        case .cableWiggle:
            // someone bumps the cable: a rapid mess of short glitches
            var pool: [(EffectKind, Int)] = [(.blue, 2), (.black, 3), (.white, 1), (.sparkle, 3), (.dropout, 2)]
            if hasFrame {
                pool += [(.channel, 4), (.tear, 4), (.jitter, 3), (.blocks, 2), (.shake, 2), (.vroll, 1)]
            }
            let total = pool.reduce(0) { $0 + $1.1 }
            let span = rr(0.8, 3.0)
            for _ in 0..<Int.random(in: 5...14) {
                var pick = Int.random(in: 0..<total)
                var kind = pool[0].0
                for (kk, w) in pool {
                    if pick < w { kind = kk; break }
                    pick -= w
                }
                let d = kind == .channel ? rr(0.08, 0.6) : rr(0.03, 0.3)
                b.add(kind, rr(0, span), d)
            }
        }
        return b.effects
    }
}
