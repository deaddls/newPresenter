import Foundation

/// Uniforms for the glitch shader. Must stay in sync with `struct Params` in
/// `Shader.swift`: only `Float` fields, so Swift and Metal agree on the layout.
struct GlitchParams {
    var time: Float = 0
    var seed: Float = 0
    var width: Float = 1          // drawable size in pixels
    var height: Float = 1

    var hasFrame: Float = 0       // 1 = a captured screen frame is bound
    var lines: Float = 768        // virtual scanline count for row based effects
    var pxScale: Float = 1        // backing scale, converts point sizes to pixels
    var visible: Float = 0        // 0 = draw nothing (fully transparent)

    var shakeX: Float = 0         // points
    var shakeY: Float = 0
    var scaleX: Float = 1
    var scaleY: Float = 1

    var offsetX: Float = 0        // fraction of the screen
    var offsetY: Float = 0
    var vroll: Float = 0          // vertical roll offset in screen heights
    var vrollBar: Float = 0       // height of the blanking bar while rolling

    var hsyncAmp: Float = 0
    var hsyncFreq: Float = 0
    var hsyncSpeed: Float = 0
    var lineJitter: Float = 0

    var tearY: Float = 0
    var tearShift: Float = 0
    var tearSlope: Float = 0
    var pixelPhase: Float = 0     // points

    var blockShift: Float = 0
    var blockRate: Float = 0
    var wobbleAmp: Float = 0
    var wobbleFreq: Float = 0

    var chanR: Float = 1
    var chanG: Float = 1
    var chanB: Float = 1
    var chroma: Float = 0         // points

    var ghost: Float = 0
    var ghostOffset: Float = 0    // points
    var smear: Float = 0
    var smearLen: Float = 0       // points

    var brightness: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var gamma: Float = 1

    var tintR: Float = 0
    var tintG: Float = 0
    var tintB: Float = 0
    var tintAmount: Float = 0

    var snow: Float = 0
    var streaks: Float = 0
    var streakRate: Float = 30
    var sparkle: Float = 0

    var humBar: Float = 0
    var humSpeed: Float = 0
    var interference: Float = 0
    var scanlines: Float = 0

    var blue: Float = 0
    var black: Float = 0
    var white: Float = 0
    var blueTone: Float = 0

    var dropout: Float = 0
    var dropoutY: Float = 0
    var dropoutH: Float = 0
    var dropoutWhite: Float = 0

    var osd: Float = 0            // not used by the shader, drives the "no signal" box
    var tearOn: Float = 0
    var clockAmt: Float = 0       // wrong pixel clock/phase: shimmering soft vertical bands
    var clockBands: Float = 0
}
