import Foundation

/// Metal source, compiled at runtime (the Command Line Tools ship no `metal` compiler).
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Params {
    float time, seed, width, height;
    float hasFrame, lines, pxScale, visible;
    float shakeX, shakeY, scaleX, scaleY;
    float offsetX, offsetY, vroll, vrollBar;
    float hsyncAmp, hsyncFreq, hsyncSpeed, lineJitter;
    float tearY, tearShift, tearSlope, pixelPhase;
    float blockShift, blockRate, wobbleAmp, wobbleFreq;
    float chanR, chanG, chanB, chroma;
    float ghost, ghostOffset, smear, smearLen;
    float brightness, contrast, saturation, gamma;
    float tintR, tintG, tintB, tintAmount;
    float snow, streaks, streakRate, sparkle;
    float humBar, humSpeed, interference, scanlines;
    float blue, black, white, blueTone;
    float dropout, dropoutY, dropoutH, dropoutWhite;
    float osd, tearOn, clockAmt, clockBands;
};

struct VOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VOut glitch_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

// pcg3d: integer hash, stable for large inputs.
static float hash3(float a, float b, float c) {
    uint3 v = uint3(int3(int(a), int(b), int(c)));
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return float(v.x) * (1.0 / 4294967296.0);
}

// Straight-alpha "over" compositing of colour c with opacity a onto (col, alpha).
static void over(thread float3 &col, thread float &alpha, float3 c, float a) {
    a = clamp(a, 0.0, 1.0);
    float oa = a + alpha * (1.0 - a);
    col = oa > 0.0001 ? (c * a + col * alpha * (1.0 - a)) / oa : float3(0.0);
    alpha = oa;
}

fragment float4 glitch_fragment(VOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant Params &p [[buffer(0)]]) {
    if (p.visible < 0.5) return float4(0.0);

    constexpr sampler smp(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 res = float2(p.width, p.height);
    float px = 1.0 / res.x;
    float2 uv0 = in.uv;
    float t = p.time;
    float frame = floor(t * 60.0);
    float row = floor(uv0.y * p.lines);
    float2 pt = floor(uv0 * res / p.pxScale);

    // ---- geometry: which part of the incoming signal lands on this pixel ----
    float2 uv = uv0;
    float bar = 0.0;
    float barLine = 0.0;
    if (p.vroll != 0.0) {
        float total = 1.0 + p.vrollBar;
        float yy = fract(uv.y + p.vroll) * total;
        bar = step(1.0, yy);
        barLine = bar * step(abs(yy - (1.0 + p.vrollBar * 0.5)), 0.0025);
        uv.y = yy;
    }
    uv = (uv - 0.5) / float2(p.scaleX, p.scaleY) + 0.5 + float2(p.offsetX, p.offsetY);
    uv += float2(p.shakeX, p.shakeY) * p.pxScale / res;
    float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);

    // per-line horizontal displacement (sync trouble); wraps around with a blanking gap
    float shift = 0.0;
    if (p.hsyncAmp > 0.0) {
        shift += p.hsyncAmp * (sin(uv0.y * p.hsyncFreq + t * p.hsyncSpeed) * 0.7
                             + sin(uv0.y * p.hsyncFreq * 2.71 - t * p.hsyncSpeed * 1.37) * 0.3);
    }
    if (p.wobbleAmp > 0.0) shift += p.wobbleAmp * sin(uv0.y * p.wobbleFreq * 6.2832 + t * 4.0);
    if (p.lineJitter > 0.0) {
        float a = hash3(row, frame, 11.0);
        float b = hash3(row, frame, 12.0);
        shift += p.lineJitter * (a - 0.5) * (0.25 + 3.0 * step(0.93, b));
    }
    if (p.pixelPhase > 0.0) shift += (hash3(row, frame, 13.0) - 0.5) * p.pixelPhase * p.pxScale * px;
    if (p.tearOn > 0.5 && uv0.y > p.tearY) shift += p.tearShift + p.tearSlope * (uv0.y - p.tearY);
    if (p.blockShift > 0.0) {
        float bucket = floor(t * p.blockRate);
        float bands = 6.0 + floor(hash3(bucket, 1.0, 21.0) * 34.0);
        float band = floor(uv0.y * bands);
        if (hash3(band, bucket, 22.0) > 0.55) shift += (hash3(band, bucket, 23.0) - 0.5) * p.blockShift;
    }
    float hblank = 0.0;
    if (shift != 0.0) {
        const float total = 1.035;
        float xx = uv.x + shift;
        xx -= floor(xx / total) * total;
        hblank = step(1.0, xx);
        uv.x = xx;
    }

    // ---- sample the captured frame ----
    float3 col = float3(0.0);
    float alpha = 0.0;
    if (p.hasFrame > 0.5) {
        float2 cx = float2(p.chroma * p.pxScale * px, 0.0);
        col.r = tex.sample(smp, uv + cx).r;
        col.g = tex.sample(smp, uv).g;
        col.b = tex.sample(smp, uv - cx).b;

        if (p.clockAmt > 0.0) {
            float amt = p.clockAmt * (0.5 + 0.5 * sin(uv0.x * 6.2832 * p.clockBands + t * 1.7));
            float o = (0.75 + amt) * p.pxScale * px;
            float3 nb = (tex.sample(smp, uv - float2(o, 0.0)).rgb + tex.sample(smp, uv + float2(o, 0.0)).rgb) * 0.5;
            col = mix(col, nb, amt * 0.85) + (hash3(row, floor(pt.x / 2.0), frame + 501.0) - 0.5) * amt * 0.14;
        }
        if (p.smear > 0.0) {
            float3 acc = float3(0.0);
            float ws = 0.0;
            float st = p.smearLen * p.pxScale * px / 6.0;
            for (int k = 1; k <= 6; k++) {
                float w = exp(-0.45 * float(k));
                acc += tex.sample(smp, uv - float2(st * float(k), 0.0)).rgb * w;
                ws += w;
            }
            col = mix(col, acc / ws, p.smear * 0.6);
        }
        if (p.ghost > 0.0) {
            float go = p.ghostOffset * p.pxScale * px;
            float3 g1 = tex.sample(smp, uv - float2(go, 0.0)).rgb;
            float3 g2 = tex.sample(smp, uv - float2(go * 2.3, 0.0)).rgb;
            float3 e1 = g1 - tex.sample(smp, uv - float2(go + 2.0 * p.pxScale * px, 0.0)).rgb;
            col = mix(col, g1, 0.22 * p.ghost);
            col = mix(col, g2, 0.09 * p.ghost);
            col += e1 * 0.25 * p.ghost;
        }
        col *= inside * (1.0 - bar) * (1.0 - hblank);
        col = mix(col, float3(0.4), barLine);

        col *= float3(p.chanR, p.chanG, p.chanB);
        float l = dot(col, float3(0.299, 0.587, 0.114));
        col = mix(float3(l), col, p.saturation);
        col = (col - 0.5) * p.contrast + 0.5 + p.brightness;
        col = pow(clamp(col, 0.0, 1.0), float3(p.gamma));
        if (p.tintAmount > 0.0) col = mix(col, l * float3(p.tintR, p.tintG, p.tintB) * 1.6, p.tintAmount);
        if (p.humBar > 0.0) col *= 1.0 - p.humBar * (0.5 + 0.5 * sin((uv0.y - t * p.humSpeed) * 6.2832 * 1.3));
        if (p.interference > 0.0) {
            col += p.interference * 0.065 * sin(pt.x * 0.9 + pt.y * 0.35 - t * 55.0)
                 * (0.6 + 0.4 * sin(uv0.y * 9.0 + t * 2.3));
        }
        if (p.scanlines > 0.0) col *= 1.0 - p.scanlines * 0.25 * (1.0 + sin(uv0.y * p.lines * 6.2832));
        alpha = 1.0;
    }

    // ---- noise: works with or without a captured frame ----
    if (p.snow > 0.0) {
        float n = hash3(pt.x, pt.y, frame + 101.0);
        over(col, alpha, float3(n), p.snow * (0.55 + 0.45 * n));
    }
    if (p.streaks > 0.0) {
        float bucket = floor(t * p.streakRate);
        float thr = 1.0 - p.streaks * 0.06;
        float rs = -1.0;
        if (hash3(row, bucket, 201.0) > thr) rs = row;
        else if (hash3(row - 1.0, bucket, 201.0) > thr && hash3(row - 1.0, bucket, 205.0) > 0.5) rs = row - 1.0;
        if (rs >= 0.0) {
            float x0 = hash3(rs, bucket, 202.0) * 1.1 - 0.1;
            float len = 0.03 + 0.7 * pow(hash3(rs, bucket, 203.0), 2.0);
            if (uv0.x > x0 && uv0.x < x0 + len) {
                float seg = hash3(floor(pt.x / 4.0), rs, bucket + 204.0);
                float edge = smoothstep(0.0, 0.02, uv0.x - x0) * smoothstep(0.0, 0.05, x0 + len - uv0.x);
                over(col, alpha, float3(1.0, 1.0, 0.97), edge * (0.55 + 0.45 * seg) * step(0.15, seg));
            }
        }
    }
    if (p.sparkle > 0.0) {
        float cellX = floor(pt.x / 3.0);
        float hs = hash3(cellX, row, frame + 301.0);
        float boost = 1.0;
        if (p.hasFrame > 0.5) {
            float3 a = tex.sample(smp, uv).rgb;
            float3 b = tex.sample(smp, uv - float2(2.0 * p.pxScale * px, 0.0)).rgb;
            boost = 0.3 + 6.0 * length(a - b);
        }
        if (hs < p.sparkle * 0.012 * boost) {
            float br = hash3(cellX, row, frame + 302.0);
            float3 tint = float3(hash3(cellX, row, 303.0), hash3(cellX, row, 304.0), 1.0);
            over(col, alpha, mix(float3(1.0), tint, 0.3 * br), 0.75 + 0.25 * br);
        }
    }
    if (p.dropout > 0.0 && uv0.y > p.dropoutY && uv0.y < p.dropoutY + p.dropoutH) {
        float n = hash3(floor(pt.x / 2.0), row, frame + 401.0);
        float3 dc = p.dropoutWhite > 0.5 ? float3(0.7 + 0.3 * n) : float3(0.0);
        over(col, alpha, dc, p.dropout);
    }

    // ---- full screen signal states ----
    if (p.white > 0.0) over(col, alpha, float3(1.0), p.white);
    if (p.black > 0.0) over(col, alpha, float3(0.0), p.black);
    if (p.blue > 0.0) {
        float3 bc = mix(float3(0.0, 0.0, 0.80), float3(0.03, 0.12, 0.72), p.blueTone);
        over(col, alpha, bc, p.blue);
    }

    col = clamp(col, 0.0, 1.0);
    return float4(col * alpha, alpha);
}
"""
