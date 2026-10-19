import Foundation

/// Decides when which episode happens on one screen and turns the active
/// effects into shader parameters for a given moment.
final class GlitchScheduler {
    private enum Mood { case calm, normal, storm }

    private(set) var running = false
    private var effects: [Effect] = []
    private var nextEpisode = 0.0
    private var mood = Mood.normal
    private var moodUntil = 0.0
    private var epoch = 0.0
    private var lastEpisode: Episode?

    /// Set by the renderer: whether a captured frame is available to distort.
    var hasFrame = false

    func start(now: Double) {
        running = true
        effects.removeAll()
        epoch = now
        mood = chance(0.5) ? .storm : .normal
        moodUntil = now + rr(6, 15)
        nextEpisode = now + rr(0.5, 1.5)
    }

    func stop() {
        running = false
        effects.removeAll()
    }

    /// Fires a big glitch right now (short key press while running).
    func burst(now: Double) {
        guard running else { return }
        let choices: [Episode] = hasFrame ? [.cableWiggle, .signalLoss, .tear, .colorPin, .roll] : [.signalLoss, .blueFlash, .whiteNoise]
        effects.removeAll()
        schedule(choices.randomElement()!, at: now, k: Settings.intensityFactor)
    }

    func params(now: Double) -> GlitchParams {
        if running {
            if now >= moodUntil { advanceMood(now) }
            if now >= nextEpisode {
                schedule(pickEpisode(), at: now, k: Float.random(in: 0.55...1) * Settings.intensityFactor)
            }
        }
        effects.removeAll { $0.end <= now }

        var p = GlitchParams()
        p.time = Float(now - epoch)
        var any = false
        for e in effects where e.start <= now {
            e.apply(to: &p, now: now)
            any = true
        }
        p.visible = any ? 1 : 0
        return p
    }

    private func schedule(_ episode: Episode, at now: Double, k: Float) {
        let new = episode.build(at: now, k: k, hasFrame: hasFrame)
        effects += new
        lastEpisode = episode
        let end = new.map(\.end).max() ?? now
        nextEpisode = end + gap()
    }

    private func pickEpisode() -> Episode {
        let level = Settings.intensity
        let candidates = Episode.allCases.filter { hasFrame || !$0.needsFrame }
        let weights = candidates.map { $0.weight(level: level) * ($0 == lastEpisode ? 0.3 : 1) }
        var pick = Double.random(in: 0..<weights.reduce(0, +))
        for (ep, w) in zip(candidates, weights) {
            if pick < w { return ep }
            pick -= w
        }
        return candidates.last!
    }

    /// Pause until the next episode; log-uniform so short and long gaps both feel natural.
    private func gap() -> Double {
        let (lo, hi): (Double, Double)
        switch mood {
        case .calm: (lo, hi) = (3, 12)
        case .normal: (lo, hi) = (0.6, 5)
        case .storm: (lo, hi) = (0.08, 1.2)
        }
        return exp(rr(log(lo), log(hi))) * Settings.gapFactor
    }

    private func advanceMood(_ now: Double) {
        let x = Double.random(in: 0..<1)
        mood = x < 0.5 ? .normal : (x < 0.8 ? .calm : .storm)
        switch mood {
        case .calm: moodUntil = now + rr(10, 30)
        case .normal: moodUntil = now + rr(10, 40)
        case .storm: moodUntil = now + rr(3, 10)
        }
    }
}

enum Settings {
    private static let d = UserDefaults.standard

    private static func int(_ key: String, _ def: Int, max: Int) -> Int {
        let v = d.object(forKey: key) as? Int ?? def
        return Swift.max(0, Swift.min(max, v))
    }

    /// 0 = leicht, 1 = mittel, 2 = heftig
    static var intensity: Int {
        get { int("intensity", 1, max: 2) }
        set { d.set(newValue, forKey: "intensity") }
    }
    static var intensityFactor: Float { [0.65, 1.0, 1.3][intensity] }
    static var gapFactor: Double { [2.2, 1.0, 0.45][intensity] }

    /// 0 = Deutsch, 1 = English, 2 = aus
    static var osdLanguage: Int {
        get { int("osdLanguage", 0, max: 2) }
        set { d.set(newValue, forKey: "osdLanguage") }
    }

    static var shortPressStops: Bool {
        get { d.bool(forKey: "shortPressStops") }
        set { d.set(newValue, forKey: "shortPressStops") }
    }

    static var hideIcon: Bool {
        get { d.bool(forKey: "hideIcon") }
        set { d.set(newValue, forKey: "hideIcon") }
    }

#if VGAGLITCH2
    /// false = nur Beamer, true = Laptop-Bildschirm und Beamer
    static var allScreens: Bool {
        get { d.bool(forKey: "allScreens") }
        set { d.set(newValue, forKey: "allScreens") }
    }

    /// The "Bargeld abschaffen?" poll pops up at random while running.
    static var pollEnabled: Bool {
        get { d.object(forKey: "pollEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "pollEnabled") }
    }
#else
    static let allScreens = false
#endif
}
