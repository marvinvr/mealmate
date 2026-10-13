#!/usr/bin/env swift
// MealMate app icons with dishes: the default (Salad) and the five food alternates.
//
// Usage:  swift Design/make-icon-variants.swift [resources-dir] [--sheet <dir>]
// Default resources dir: MealMate/Resources. Run from the repo root.
//
// Every icon is 1024x1024 in three appearances, like Design/make-icon.swift (which still draws
// the two subscription icons, Copper Pot and Midnight Kitchen):
//   <Name>.png         light, opaque, no alpha channel
//   <Name>-dark.png    dark: a deeper, opaque ground; the default's ground is transparent (the
//                      system supplies the backdrop)
//   <Name>-tinted.png  tinted: the dish as a grayscale mark on black, the system tints it
//
// Writes:
//   Assets.xcassets/AppIcon.appiconset               the default icon (Salad)
//   AppIcons.xcassets/AppIcon<Name>.appiconset       the food alternates (docs/supporter.md)
//   AppIcons.xcassets/IconPreview<Name>.imageset     384px picker previews (light + dark), incl. IconPreviewDefault
// With --sheet: variant-<n>-<name>.png and overview.png (every icon large, at home-screen size
// and on light / dark / tinted home screens) into <dir>, for reviewing changes.

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

enum Appearance: CaseIterable { case light, dark, tinted }

/// What the current render is for. The dish functions read it through `drawGround` and
/// `drawVessel`, so each dish is written once for all three appearances.
var appearance = Appearance.light
/// The default icon's dark appearance leaves the ground transparent, like the system expects.
var transparentDarkGround = false

// MARK: - Basics

struct RGB {
    let r, g, b, a: CGFloat
    init(_ hex: UInt32, alpha: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        a = alpha
    }
    private init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) { self.r = r; self.g = g; self.b = b; self.a = a }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func with(alpha: CGFloat) -> RGB { RGB(r: r, g: g, b: b, a: alpha) }
    func mixed(with o: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t, a: a + (o.a - a) * t)
    }
}

/// Deterministic pseudo random generator so the renders are reproducible.
struct SeededRandom {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + (hi - lo) * next() }
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
func pt(_ c: CGPoint, _ angle: CGFloat, _ d: CGFloat) -> CGPoint { CGPoint(x: c.x + cos(angle) * d, y: c.y + sin(angle) * d) }
func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

func gradient(_ colors: [RGB], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors.map(\.cg) as CFArray, locations: locations)!
}

func clipped(_ ctx: CGContext, _ path: CGPath, _ body: () -> Void) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    body()
    ctx.restoreGState()
}

/// Shadow that falls down (the context is flipped, shadow offsets are not).
func withShadow(_ ctx: CGContext, dy: CGFloat, blur: CGFloat, _ color: RGB, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: color.cg)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: RGB) {
    ctx.addPath(path)
    ctx.setFillColor(color.cg)
    ctx.fillPath()
}

func ellipsePath(_ c: CGPoint, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: circle(c, r), transform: nil) }

/// Radial fill of a path, light spot at `light` (relative offset of the bounding box center).
func shade(_ ctx: CGContext, _ path: CGPath, _ colors: [RGB], light: CGPoint = CGPoint(x: -0.3, y: -0.35), locations: [CGFloat]? = nil) {
    let b = path.boundingBox
    let r = max(b.width, b.height) / 2
    let c = CGPoint(x: b.midX, y: b.midY)
    let hl = CGPoint(x: c.x + light.x * r, y: c.y + light.y * r)
    clipped(ctx, path) {
        ctx.drawRadialGradient(gradient(colors, locations), startCenter: hl, startRadius: 0,
                               endCenter: c, endRadius: r * 1.25, options: [.drawsAfterEndLocation])
    }
}

/// Irregular closed blob through `n` jittered points, smoothed with quad curves.
func blobPath(_ c: CGPoint, _ r: CGFloat, jitter: CGFloat, points n: Int = 9, seed: UInt64, stretch: CGFloat = 1, angle: CGFloat = 0) -> CGPath {
    var rng = SeededRandom(seed)
    var pts: [CGPoint] = []
    let phase = rng.next() * .pi * 2
    for i in 0..<n {
        let a = phase + CGFloat(i) / CGFloat(n) * .pi * 2
        let d = r * (1 + (rng.next() - 0.5) * 2 * jitter)
        pts.append(CGPoint(x: cos(a) * d * stretch, y: sin(a) * d))
    }
    let path = CGMutablePath()
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    path.move(to: mid(pts[n - 1], pts[0]))
    for i in 0..<n { path.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i]) }
    path.closeSubpath()
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    return path.copy(using: &t)!
}

/// Pointed leaf along the x axis, rotated.
func leafPath(_ c: CGPoint, length: CGFloat, width: CGFloat, angle: CGFloat, belly: CGFloat = 0) -> CGPath {
    let half = length / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -half, y: 0))
    path.addCurve(to: CGPoint(x: half, y: 0), control1: CGPoint(x: -half * 0.5 + belly, y: -width), control2: CGPoint(x: half * 0.45, y: -width * 0.8))
    path.addCurve(to: CGPoint(x: -half, y: 0), control1: CGPoint(x: half * 0.45, y: width * 0.8), control2: CGPoint(x: -half * 0.5 + belly, y: width))
    path.closeSubpath()
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    return path.copy(using: &t)!
}

func roundedRect(_ c: CGPoint, w: CGFloat, h: CGFloat, r: CGFloat, angle: CGFloat) -> CGPath {
    let p = CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    return p.copy(using: &t)!
}

// MARK: - Ground

/// The field behind the dish. Dark: `dark`, or a deeper version of the light ground. Tinted (and
/// the default's dark): nothing, the context stays transparent.
func drawGround(_ ctx: CGContext, inner lightInner: RGB, outer lightOuter: RGB, dark: (RGB, RGB)? = nil,
                light: CGPoint = CGPoint(x: 0.38, y: 0.3), grain: CGFloat = 0.035) {
    if appearance == .tinted || (appearance == .dark && transparentDarkGround) { return }
    let black = RGB(0x000000)
    let inner = appearance == .dark ? (dark?.0 ?? lightInner.mixed(with: black, 0.6)) : lightInner
    let outer = appearance == .dark ? (dark?.1 ?? lightOuter.mixed(with: black, 0.7)) : lightOuter
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.setFillColor(outer.cg)
    ctx.fill(full)
    let c = CGPoint(x: size * light.x, y: size * light.y)
    ctx.drawRadialGradient(gradient([inner, outer]), startCenter: c, startRadius: 0, endCenter: c, endRadius: size * 1.0,
                           options: [.drawsAfterEndLocation])
    // Very fine paper grain so large fields don't look like flat vector.
    var rng = SeededRandom(99)
    for _ in 0..<9000 {
        let p = CGPoint(x: rng.next() * size, y: rng.next() * size)
        let white = rng.next() > 0.5
        ctx.setFillColor((white ? RGB(0xFFFFFF) : RGB(0x000000)).with(alpha: grain * rng.next()).cg)
        ctx.fillEllipse(in: circle(p, 0.8 + rng.next() * 1.4))
    }
}

// MARK: - Tableware

/// Ceramic plate or bowl from above. Returns the radius of the inside (the well).
@discardableResult
func drawVessel(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, rim: RGB, rimShade: RGB, inside: RGB, insideShade: RGB,
                well: CGFloat = 0.84, shadow: RGB, lipShadow: CGFloat = 0.18) -> CGFloat {
    // White ceramic would glare in the dark and tinted icons: dark stoneware there.
    var (rim, rimShade, inside, insideShade, shadow) = (rim, rimShade, inside, insideShade, shadow)
    if appearance != .light {
        (rim, rimShade, inside, insideShade) = (RGB(0x4A4541), RGB(0x302C29), RGB(0x3C3834), RGB(0x2A2724))
        shadow = RGB(0x000000, alpha: 0.5)
    }
    withShadow(ctx, dy: r * 0.06, blur: r * 0.16, shadow) {
        fill(ctx, ellipsePath(c, r), rim)
    }
    shade(ctx, ellipsePath(c, r), [rim, rim, rimShade], light: CGPoint(x: -0.35, y: -0.45), locations: [0, 0.45, 1])
    let ri = r * well
    // Inside: the far (top) wall catches shadow, the near wall light.
    clipped(ctx, ellipsePath(c, ri)) {
        ctx.drawLinearGradient(gradient([insideShade, inside, inside]), start: CGPoint(x: c.x, y: c.y - ri),
                               end: CGPoint(x: c.x, y: c.y + ri), options: [])
    }
    // Lip shadow inside the rim, light from the top.
    clipped(ctx, ellipsePath(c, ri)) {
        ctx.setShadow(offset: CGSize(width: 0, height: -ri * 0.03), blur: ri * 0.07, color: RGB(0x000000, alpha: lipShadow).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(ri * 0.1)
        ctx.strokeEllipse(in: circle(c, ri + ri * 0.05))
    }
    return ri
}

// MARK: - Ingredients

func drawBasil(_ ctx: CGContext, _ c: CGPoint, length: CGFloat, angle: CGFloat, dark: RGB = RGB(0x2F7A2E), light: RGB = RGB(0x6DBA4A), shadow: Bool = true) {
    let path = leafPath(c, length: length, width: length * 0.36, angle: angle, belly: -length * 0.08)
    let body = {
        shade(ctx, path, [light, RGB(0x4C9A3A).mixed(with: dark, 0.2), dark], light: CGPoint(x: -0.2, y: -0.3))
    }
    if shadow {
        withShadow(ctx, dy: length * 0.05, blur: length * 0.1, RGB(0x000000, alpha: 0.28)) { fill(ctx, path, dark) }
    }
    body()
    // Midrib and a few veins.
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.setStrokeColor(RGB(0xBDE39A, alpha: 0.55).cg)
    ctx.setLineWidth(max(1.2, length * 0.018))
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: -length * 0.48, y: 0))
    ctx.addQuadCurve(to: CGPoint(x: length * 0.42, y: 0), control: CGPoint(x: 0, y: -length * 0.03))
    ctx.strokePath()
    ctx.setLineWidth(max(1, length * 0.011))
    for i in 0..<3 {
        let x = -length * 0.25 + CGFloat(i) * length * 0.22
        for s: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: x, y: -length * 0.01))
            ctx.addQuadCurve(to: CGPoint(x: x + length * 0.14, y: s * length * 0.12), control: CGPoint(x: x + length * 0.04, y: s * length * 0.09))
        }
    }
    ctx.strokePath()
    // Gloss.
    ctx.restoreGState()
    clipped(ctx, path) {
        let hl = pt(c, angle - .pi * 0.75, length * 0.12)
        ctx.drawRadialGradient(gradient([RGB(0xFFFFFF, alpha: 0.28), RGB(0xFFFFFF, alpha: 0)]), startCenter: hl, startRadius: 0,
                               endCenter: hl, endRadius: length * 0.3, options: [])
    }
}

/// Small chopped herb flecks (parsley / coriander / scallion greens).
func drawFlecks(_ ctx: CGContext, center: CGPoint, radius: CGFloat, count: Int, size s: CGFloat, colors: [RGB], seed: UInt64, avoid: [(CGPoint, CGFloat)] = []) {
    var rng = SeededRandom(seed)
    var placed = 0
    var tries = 0
    while placed < count && tries < count * 20 {
        tries += 1
        let p = pt(center, rng.next() * .pi * 2, sqrt(rng.next()) * radius)
        if avoid.contains(where: { hypot($0.0.x - p.x, $0.0.y - p.y) < $0.1 }) { continue }
        let len = s * rng.range(0.6, 1.3)
        let color = colors[Int(rng.next() * CGFloat(colors.count)) % colors.count]
        fill(ctx, blobPath(p, len, jitter: 0.35, points: 6, seed: UInt64(tries) &+ seed, stretch: rng.range(0.7, 1.4), angle: rng.next() * .pi), color)
        placed += 1
    }
}

func drawSesame(_ ctx: CGContext, center: CGPoint, radius: CGFloat, count: Int, seedSize s: CGFloat, color: RGB, seed: UInt64) {
    var rng = SeededRandom(seed)
    for _ in 0..<count {
        let p = pt(center, rng.next() * .pi * 2, sqrt(rng.next()) * radius)
        let path = leafPath(p, length: s * 2, width: s * 0.75, angle: rng.next() * .pi)
        fill(ctx, path, color)
    }
}

func drawCherryTomato(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
    withShadow(ctx, dy: r * 0.12, blur: r * 0.25, RGB(0x3A0A00, alpha: 0.35)) { fill(ctx, ellipsePath(c, r), RGB(0xD7301F)) }
    shade(ctx, ellipsePath(c, r), [RGB(0xFF7A55), RGB(0xE43A22), RGB(0xA31A10)], locations: [0, 0.45, 1])
    let hl = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.38)
    ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.55).cg)
    ctx.fillEllipse(in: CGRect(x: hl.x - r * 0.16, y: hl.y - r * 0.1, width: r * 0.32, height: r * 0.2))
}

/// Halved cherry tomato, cut side up.
func drawTomatoHalf(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, angle: CGFloat) {
    let outer = blobPath(c, r, jitter: 0.03, points: 10, seed: UInt64(c.x * 3 + c.y), stretch: 1.08, angle: angle)
    withShadow(ctx, dy: r * 0.12, blur: r * 0.25, RGB(0x3A0A00, alpha: 0.32)) { fill(ctx, outer, RGB(0xC9271A)) }
    shade(ctx, outer, [RGB(0xF24A2E), RGB(0xD12B1A), RGB(0xA81C12)])
    // Flesh walls and seed chambers.
    let inner = blobPath(c, r * 0.8, jitter: 0.03, points: 10, seed: 7, stretch: 1.08, angle: angle)
    fill(ctx, inner, RGB(0xF0563A))
    for i in 0..<3 {
        let a = angle + CGFloat(i) * .pi * 2 / 3 + .pi / 6
        let cc = pt(c, a, r * 0.38)
        let chamber = blobPath(cc, r * 0.27, jitter: 0.08, points: 7, seed: UInt64(i + 3), stretch: 1.25, angle: a)
        fill(ctx, chamber, RGB(0xF7A04A))
        var rng = SeededRandom(UInt64(i) + 40)
        for _ in 0..<4 {
            let sp = pt(cc, rng.next() * .pi * 2, rng.next() * r * 0.15)
            fill(ctx, leafPath(sp, length: r * 0.14, width: r * 0.05, angle: rng.next() * .pi), RGB(0xFBE3A0))
        }
    }
    fill(ctx, ellipsePath(c, r * 0.12), RGB(0xF8826A))
    clipped(ctx, outer) {
        let hl = pt(c, deg(-130), r * 0.4)
        ctx.drawRadialGradient(gradient([RGB(0xFFFFFF, alpha: 0.35), RGB(0xFFFFFF, alpha: 0)]), startCenter: hl, startRadius: 0,
                               endCenter: hl, endRadius: r * 0.7, options: [])
    }
}

/// Fried egg, sunny side up. `jitterSeed` varies the white.
func drawFriedEgg(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, seed: UInt64, angle: CGFloat = 0, onDark: Bool = false) {
    let white = blobPath(c, r, jitter: 0.12, points: 9, seed: seed, stretch: 1.12, angle: angle)
    withShadow(ctx, dy: r * 0.04, blur: r * 0.12, RGB(0x000000, alpha: onDark ? 0.4 : 0.25)) { fill(ctx, white, RGB(0xFBF6EC)) }
    shade(ctx, white, [RGB(0xFFFFFF), RGB(0xFBF5E8), RGB(0xEADFC8)], light: CGPoint(x: -0.2, y: -0.3))
    let yc = CGPoint(x: c.x + r * 0.08, y: c.y - r * 0.05)
    let yr = r * 0.42
    withShadow(ctx, dy: yr * 0.12, blur: yr * 0.3, RGB(0x8A4A00, alpha: 0.35)) { fill(ctx, ellipsePath(yc, yr), RGB(0xF4A21C)) }
    shade(ctx, ellipsePath(yc, yr), [RGB(0xFFD86A), RGB(0xF9AE24), RGB(0xE08A0E)], locations: [0, 0.5, 1])
    ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.7).cg)
    ctx.fillEllipse(in: CGRect(x: yc.x - yr * 0.48, y: yc.y - yr * 0.55, width: yr * 0.38, height: yr * 0.24))
}

// MARK: - 1. Grain bowl

func wedgePath(_ c: CGPoint, _ r: CGFloat, from a0: CGFloat, to a1: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: c)
    p.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: false)
    p.closeSubpath()
    return p
}

func drawGrainBowl(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0xF6C453), outer: RGB(0xE38F25), dark: (RGB(0x5E3F12), RGB(0x2E1D07)))
    let c = CGPoint(x: 512, y: 520)
    let ri = drawVessel(ctx, c, 440, rim: RGB(0xFFFFFF), rimShade: RGB(0xEDE6DA), inside: RGB(0xFBF8F2), insideShade: RGB(0xE4DCCD),
                        well: 0.9, shadow: RGB(0x7A3E00, alpha: 0.38))
    let gap = deg(3)
    clipped(ctx, ellipsePath(c, ri)) {
        // Rice shows between the toppings.
        fill(ctx, ellipsePath(c, ri), RGB(0xF1ECDF))
        var rng = SeededRandom(5)
        for _ in 0..<1100 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * ri)
            fill(ctx, leafPath(p, length: 16, width: 6, angle: rng.next() * .pi), (rng.next() > 0.5 ? RGB(0xFFFFFF) : RGB(0xE2D9C4)))
        }

        // Five wedges, clockwise from the top left.
        let w = deg(72)
        let start = deg(-162)
        func wedge(_ i: Int) -> (CGPath, CGFloat) {
            let a0 = start + CGFloat(i) * w + gap, a1 = start + CGFloat(i + 1) * w - gap
            return (wedgePath(c, ri * 0.96, from: a0, to: a1), (a0 + a1) / 2)
        }
        func scatter(_ i: Int, count: Int, seed: UInt64, inner: CGFloat = 0.3, _ body: (CGPoint, inout SeededRandom) -> Void) {
            // Centres stay inside the wedge, the pieces themselves spill over a little: no hard edges.
            var r = SeededRandom(seed)
            let a0 = start + CGFloat(i) * w + gap * 2, a1 = a0 + w - gap * 4
            for _ in 0..<count {
                let d = ri * sqrt(r.range(inner * inner, 0.88))
                let p = pt(c, r.range(a0 + 30 / d, a1 - 30 / d), d)
                body(p, &r)
            }
        }

        // 0: salmon cubes (top left).
        scatter(0, count: 46, seed: 12) { p, r in
            let a = r.next() * .pi
            let k = roundedRect(p, w: 66, h: 60, r: 13, angle: a)
            withShadow(ctx, dy: 5, blur: 10, RGB(0x5A1A00, alpha: 0.35)) { fill(ctx, k, RGB(0xF27A52)) }
            shade(ctx, k, [RGB(0xFFA27C), RGB(0xF27A52), RGB(0xD9573A)])
            clipped(ctx, k) {
                ctx.setStrokeColor(RGB(0xFFE1D0, alpha: 0.7).cg)
                ctx.setLineWidth(4)
                for j in 0..<3 {
                    let o = CGFloat(j - 1) * 19
                    ctx.move(to: pt(pt(p, a, o), a + .pi / 2, -45))
                    ctx.addQuadCurve(to: pt(pt(p, a, o), a + .pi / 2, 45), control: pt(pt(p, a, o + 9), a + .pi / 2, 0))
                }
                ctx.strokePath()
            }
        }
        // 1: avocado fan (top right).
        do {
            let (_, mid) = wedge(1)
            do {
                for i in 0..<7 {
                    let along = mid + .pi / 2
                    let sc = pt(pt(c, mid, ri * 0.62), along, CGFloat(i - 3) * 38)
                    let a = mid + deg(CGFloat(i - 3) * 4)
                    let slice = CGMutablePath()
                    let len: CGFloat = CGFloat(300 - abs(i - 3) * 30), sw: CGFloat = 50
                    slice.move(to: CGPoint(x: -len / 2, y: 0))
                    slice.addQuadCurve(to: CGPoint(x: len / 2, y: 0), control: CGPoint(x: 0, y: -sw * 1.6))
                    slice.addQuadCurve(to: CGPoint(x: -len / 2, y: 0), control: CGPoint(x: 0, y: sw * 0.2))
                    var t = CGAffineTransform(translationX: sc.x, y: sc.y).rotated(by: a)
                    let sp = slice.copy(using: &t)!
                    withShadow(ctx, dy: 4, blur: 9, RGB(0x1E3A00, alpha: 0.4)) { fill(ctx, sp, RGB(0x3E6B1F)) }
                    clipped(ctx, sp) {
                        ctx.drawLinearGradient(gradient([RGB(0x2B5212), RGB(0x6E9E2A), RGB(0xC9DD72), RGB(0xEDEEA8)], [0, 0.1, 0.45, 1]),
                                               start: pt(sc, a - .pi / 2, sw * 0.85), end: pt(sc, a + .pi / 2, sw * 0.1), options: [])
                    }
                }
            }
        }
        // 2: edamame (bottom right).
        scatter(2, count: 120, seed: 10) { p, r in
            let bean = blobPath(p, 24, jitter: 0.05, points: 8, seed: UInt64(p.x * 7 + p.y), stretch: 1.3, angle: r.next() * .pi)
            withShadow(ctx, dy: 3, blur: 6, RGB(0x1E4A00, alpha: 0.4)) { fill(ctx, bean, RGB(0x7CC243)) }
            shade(ctx, bean, [RGB(0xB5E07A), RGB(0x6FB43C), RGB(0x468A22)])
        }
        // 3: red cabbage (bottom).
        scatter(3, count: 240, seed: 8) { p, r in
            let a = r.next() * .pi
            let len = r.range(60, 110)
            ctx.setLineCap(.round)
            ctx.setLineWidth(r.range(8, 12))
            ctx.setStrokeColor((r.next() > 0.7 ? RGB(0xD7A3DC) : RGB(0x7A2A84)).cg)
            ctx.move(to: pt(p, a, -len / 2))
            ctx.addQuadCurve(to: pt(p, a, len / 2), control: pt(p, a + .pi / 2, r.range(-16, 16)))
            ctx.strokePath()
        }
        // 4: carrot ribbons + corn (left).
        scatter(4, count: 190, seed: 9) { p, r in
            let k = roundedRect(p, w: 28, h: 24, r: 9, angle: r.next() * .pi)
            withShadow(ctx, dy: 2, blur: 4, RGB(0x7A5000, alpha: 0.4)) { fill(ctx, k, RGB(0xF7C531)) }
            shade(ctx, k, [RGB(0xFFE88A), RGB(0xF4BC24)])
        }
        // Inside shadow from the far wall.
        ctx.drawLinearGradient(gradient([RGB(0x4A3010, alpha: 0.25), RGB(0x4A3010, alpha: 0)]), start: CGPoint(x: c.x, y: c.y - ri),
                               end: CGPoint(x: c.x, y: c.y - ri * 0.55), options: [])
    }
    // Centre: a heap of rice with sesame and scallions, and a lime wedge.
    let heap = blobPath(c, 118, jitter: 0.12, points: 14, seed: 44)
    withShadow(ctx, dy: 8, blur: 18, RGB(0x4A3010, alpha: 0.35)) { fill(ctx, heap, RGB(0xF4EFE3)) }
    clipped(ctx, heap) {
        var rng = SeededRandom(6)
        for _ in 0..<160 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * 125)
            fill(ctx, leafPath(p, length: 17, width: 6.5, angle: rng.next() * .pi), (rng.next() > 0.5 ? RGB(0xFFFFFF) : RGB(0xE5DCC8)))
        }
        let hl = CGPoint(x: c.x - 40, y: c.y - 45)
        ctx.drawRadialGradient(gradient([RGB(0x5A4020, alpha: 0), RGB(0x5A4020, alpha: 0.22)], [0.4, 1]), startCenter: hl, startRadius: 0,
                               endCenter: c, endRadius: 135, options: [])
    }
    drawSesame(ctx, center: c, radius: ri * 0.85, count: 90, seedSize: 6, color: RGB(0xFBF3DD), seed: 3)
    drawSesame(ctx, center: c, radius: ri * 0.85, count: 40, seedSize: 6, color: RGB(0x2A2420), seed: 4)
    var r6 = SeededRandom(21)
    for _ in 0..<22 {
        let p = pt(c, r6.next() * .pi * 2, sqrt(r6.next()) * 105)
        let ring = blobPath(p, 12, jitter: 0.08, points: 7, seed: UInt64(p.x), stretch: 1.15, angle: r6.next() * 3)
        withShadow(ctx, dy: 2, blur: 4, RGB(0x000000, alpha: 0.25)) { fill(ctx, ring, RGB(0x5BA83A)) }
        fill(ctx, blobPath(p, 7, jitter: 0.1, points: 6, seed: UInt64(p.y), stretch: 1.15, angle: 0), RGB(0xDDF2B8))
    }
}

// MARK: - 2. Spaghetti

func drawSpaghetti(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0x3C6E9C), outer: RGB(0x1E3D63), dark: (RGB(0x1B3150), RGB(0x0A1424)))
    let c = CGPoint(x: 512, y: 512)
    let ri = drawVessel(ctx, c, 440, rim: RGB(0xFFFFFF), rimShade: RGB(0xE7E3DC), inside: RGB(0xFAF8F4), insideShade: RGB(0xE2DDD3),
                        well: 0.8, shadow: RGB(0x000A1A, alpha: 0.5), lipShadow: 0.08)
    _ = ri
    let nest: CGFloat = 355
    // Nest body and its shadow on the plate.
    let body = blobPath(c, nest, jitter: 0.04, points: 14, seed: 19)
    withShadow(ctx, dy: 14, blur: 30, RGB(0x4A3000, alpha: 0.4)) { fill(ctx, body, RGB(0xD9AE55)) }
    shade(ctx, body, [RGB(0xE9C46E), RGB(0xD9AA50), RGB(0xB8862E)], light: CGPoint(x: -0.2, y: -0.25))
    // Strands: long twirled arcs. Each one a soft dark edge, the strand, and a thin highlight on its upper side.
    ctx.setLineCap(.round)
    var r = SeededRandom(23)
    var strands: [(CGPath, CGFloat)] = []
    for _ in 0..<170 {
        let rad = nest * r.range(0.25, 0.98)
        let start = r.next() * .pi * 2
        let sweep = r.range(1.4, 3.4)
        let drift = r.range(-0.12, 0.12)
        let path = CGMutablePath()
        let steps = 60
        for k in 0...steps {
            let t = CGFloat(k) / CGFloat(steps)
            let a = start + sweep * t
            let d = min(nest * 0.98, rad * (1 + drift * t) + sin(t * 7 + start) * 5)
            let q = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        strands.append((path, rad / nest))
    }
    for (path, t) in strands {
        ctx.addPath(path)
        ctx.setStrokeColor(RGB(0xA9782A, alpha: 0.55).cg)
        ctx.setLineWidth(13)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(RGB(0xFBE3A0).mixed(with: RGB(0xE8BC5E), t * 0.7).cg)
        ctx.setLineWidth(9)
        ctx.strokePath()
        ctx.saveGState()
        ctx.translateBy(x: -1.5, y: -2)
        ctx.addPath(path)
        ctx.setStrokeColor(RGB(0xFFF8DC, alpha: 0.6).cg)
        ctx.setLineWidth(2.5)
        ctx.strokePath()
        ctx.restoreGState()
    }
    // Sauce: glossy tomato ragù heaped in the middle.
    let sc = CGPoint(x: c.x + 6, y: c.y - 4)
    let sauce = blobPath(sc, 200, jitter: 0.09, points: 15, seed: 31, stretch: 1.04)
    withShadow(ctx, dy: 10, blur: 22, RGB(0x4A0A00, alpha: 0.45)) { fill(ctx, sauce, RGB(0xC2311C)) }
    shade(ctx, sauce, [RGB(0xF0613A), RGB(0xD03A20), RGB(0xA4220F)], locations: [0, 0.5, 1])
    // Chunky texture.
    var r2 = SeededRandom(37)
    clipped(ctx, sauce) {
        for _ in 0..<40 {
            let p = pt(sc, r2.next() * .pi * 2, sqrt(r2.next()) * 190)
            fill(ctx, blobPath(p, r2.range(10, 22), jitter: 0.3, points: 6, seed: UInt64(p.x * p.y), stretch: 1.2, angle: r2.next() * 3),
                 (r2.next() > 0.5 ? RGB(0x9C1E0E) : RGB(0xE85A34)).with(alpha: 0.7))
        }
        for _ in 0..<10 {
            let p = pt(sc, deg(-130) + r2.range(-0.6, 0.6), r2.range(20, 110))
            ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.45).cg)
            ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: r2.range(8, 22), height: r2.range(5, 10)))
        }
    }
    // Parmesan.
    var r3 = SeededRandom(41)
    for _ in 0..<160 {
        let p = pt(sc, r3.next() * .pi * 2, sqrt(r3.next()) * 175)
        fill(ctx, blobPath(p, r3.range(1.6, 3.4), jitter: 0.35, points: 5, seed: UInt64(p.x * 3 + p.y), stretch: 1.2, angle: r3.next() * 3),
             RGB(0xFFF4D0, alpha: 0.9))
    }
    drawBasil(ctx, CGPoint(x: c.x + 45, y: c.y - 45), length: 210, angle: deg(-35))
    drawBasil(ctx, CGPoint(x: c.x - 65, y: c.y + 20), length: 180, angle: deg(200))
    drawBasil(ctx, CGPoint(x: c.x + 50, y: c.y + 70), length: 120, angle: deg(75))
}

// MARK: - 3. Shakshuka

func drawShakshuka(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0x8FB57A), outer: RGB(0x557F45), dark: (RGB(0x2E4527), RGB(0x121D0E)))
    let c = CGPoint(x: 470, y: 470)
    let r: CGFloat = 380
    // Handle, lower right.
    let ha = deg(45)
    let handle = roundedRect(pt(c, ha, r + 150), w: 330, h: 92, r: 40, angle: ha)
    withShadow(ctx, dy: 18, blur: 34, RGB(0x0F2408, alpha: 0.5)) { fill(ctx, handle, RGB(0x2B2826)) }
    clipped(ctx, handle) {
        ctx.drawLinearGradient(gradient([RGB(0x4A4542), RGB(0x2B2826), RGB(0x1A1817)]), start: pt(pt(c, ha, r + 150), ha + .pi / 2, -46),
                               end: pt(pt(c, ha, r + 150), ha + .pi / 2, 46), options: [])
    }
    fill(ctx, ellipsePath(pt(c, ha, r + 260), 18), RGB(0x6A8F55))
    // Pan.
    withShadow(ctx, dy: 22, blur: 50, RGB(0x0F2408, alpha: 0.55)) { fill(ctx, ellipsePath(c, r), RGB(0x2B2826)) }
    shade(ctx, ellipsePath(c, r), [RGB(0x5A5450), RGB(0x2E2A28), RGB(0x1C1A19)], light: CGPoint(x: -0.4, y: -0.5))
    let ri = r * 0.87
    fill(ctx, ellipsePath(c, ri), RGB(0x1A1817))
    // Sauce.
    let sr = ri * 0.95
    let sauce = ellipsePath(c, sr)
    shade(ctx, sauce, [RGB(0xE5522C), RGB(0xC8351B), RGB(0x8E1C0C)], light: CGPoint(x: -0.25, y: -0.3), locations: [0, 0.6, 1])
    clipped(ctx, sauce) {
        var rng = SeededRandom(51)
        for _ in 0..<120 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * sr)
            fill(ctx, blobPath(p, rng.range(10, 28), jitter: 0.35, points: 6, seed: UInt64(p.x * 3 + p.y), stretch: 1.3, angle: rng.next() * 3),
                 (rng.next() > 0.45 ? RGB(0x9A2010) : RGB(0xEE6A3C)).with(alpha: 0.55))
        }
        // Inner rim shadow from the pan wall.
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: RGB(0x000000, alpha: 0.6).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(40)
        ctx.strokeEllipse(in: circle(c, sr + 20))
    }
    // Eggs.
    let eggs: [(CGPoint, CGFloat, UInt64)] = [
        (CGPoint(x: c.x - 120, y: c.y - 95), 118, 3),
        (CGPoint(x: c.x + 135, y: c.y - 40), 112, 8),
        (CGPoint(x: c.x - 30, y: c.y + 150), 115, 13),
    ]
    for e in eggs { drawFriedEgg(ctx, e.0, e.1, seed: e.2, angle: CGFloat(e.2), onDark: true) }
    // Feta crumbles.
    var r2 = SeededRandom(61)
    var fetas: [CGPoint] = []
    while fetas.count < 9 {
        let p = pt(c, r2.next() * .pi * 2, sqrt(r2.next()) * sr * 0.88)
        if eggs.contains(where: { hypot($0.0.x - p.x, $0.0.y - p.y) < $0.1 * 1.2 }) { continue }
        fetas.append(p)
        let k = blobPath(p, r2.range(17, 26), jitter: 0.25, points: 6, seed: UInt64(p.x), stretch: 1.1, angle: r2.next() * 3)
        withShadow(ctx, dy: 4, blur: 8, RGB(0x3A0000, alpha: 0.4)) { fill(ctx, k, RGB(0xFBF8F0)) }
        shade(ctx, k, [RGB(0xFFFFFF), RGB(0xEFE8D8)])
    }
    // Parsley & chili flakes.
    drawFlecks(ctx, center: c, radius: sr * 0.92, count: 90, size: 9, colors: [RGB(0x2F7D2A), RGB(0x4FA23A), RGB(0x6CBE4A)], seed: 71)
    drawFlecks(ctx, center: c, radius: sr * 0.9, count: 30, size: 4, colors: [RGB(0x7A0E05)], seed: 73)
    // Pan rim highlight.
    ctx.setStrokeColor(RGB(0xFFFFFF, alpha: 0.18).cg)
    ctx.setLineWidth(5)
    ctx.addArc(center: c, radius: r - 6, startAngle: deg(190), endAngle: deg(260), clockwise: false)
    ctx.strokePath()
}

// MARK: - 4. Ramen

func drawRamen(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0xE85B3E), outer: RGB(0xB8301E), dark: (RGB(0x5E1E14), RGB(0x2C0B06)))
    let c = CGPoint(x: 512, y: 520)
    let r: CGFloat = 430
    withShadow(ctx, dy: 24, blur: 54, RGB(0x3A0500, alpha: 0.55)) { fill(ctx, ellipsePath(c, r), RGB(0x24201F)) }
    shade(ctx, ellipsePath(c, r), [RGB(0x4A4442), RGB(0x24201F), RGB(0x151312)], light: CGPoint(x: -0.4, y: -0.5))
    let ri = r * 0.9
    let broth = ellipsePath(c, ri)
    shade(ctx, broth, [RGB(0xF2BC63), RGB(0xD98E36), RGB(0xA9601C)], light: CGPoint(x: -0.1, y: -0.1), locations: [0, 0.55, 1])
    clipped(ctx, broth) {
        // Noodles peeking out, lower left.
        ctx.setLineCap(.round)
        var rng = SeededRandom(81)
        for pass in 0..<2 {
            var r2 = SeededRandom(83)
            for _ in 0..<38 {
                let y0 = c.y + r2.range(60, 330)
                let x0 = c.x - r2.range(140, 380)
                let path = CGMutablePath()
                for s in 0...40 {
                    let t = CGFloat(s) / 40
                    let x = x0 + t * 260
                    let y = y0 - t * 120 + sin(t * 18 + y0) * 9
                    if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.addPath(path)
                ctx.setLineWidth(pass == 0 ? 15 : 10)
                ctx.setStrokeColor(pass == 0 ? RGB(0xB98A3A, alpha: 0.7).cg : RGB(0xFBE3A0).cg)
                ctx.strokePath()
            }
        }
        // Oil droplets.
        for _ in 0..<45 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * ri)
            let d = rng.range(3, 10)
            ctx.setFillColor(RGB(0xFFE29A, alpha: 0.5).cg)
            ctx.fillEllipse(in: circle(p, d))
            ctx.setStrokeColor(RGB(0xB0661C, alpha: 0.4).cg)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: circle(p, d))
        }
        // Nori, tucked in at the back.
        let nori = roundedRect(CGPoint(x: c.x - 40, y: c.y - ri + 60), w: 240, h: 230, r: 6, angle: deg(-14))
        withShadow(ctx, dy: 8, blur: 16, RGB(0x000000, alpha: 0.4)) { fill(ctx, nori, RGB(0x1D2A1E)) }
        shade(ctx, nori, [RGB(0x3A4A35), RGB(0x1D2A1E), RGB(0x121A13)])
        // Inner wall shadow.
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: RGB(0x000000, alpha: 0.55).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(40)
        ctx.strokeEllipse(in: circle(c, ri + 20))
    }
    // Chashu, right: rolled pork belly, a torched edge and a spiral of fat.
    for (i, p) in [CGPoint(x: c.x + 175, y: c.y - 100), CGPoint(x: c.x + 205, y: c.y + 85)].enumerated() {
        let s = blobPath(p, 120, jitter: 0.05, points: 10, seed: UInt64(i + 5), stretch: 1.06, angle: CGFloat(i))
        withShadow(ctx, dy: 10, blur: 20, RGB(0x3A1500, alpha: 0.45)) { fill(ctx, s, RGB(0x6B3416)) }
        shade(ctx, s, [RGB(0xE9B892), RGB(0xD49670), RGB(0xB06B44)])
        clipped(ctx, s) {
            ctx.setStrokeColor(RGB(0xF7E2CC, alpha: 0.85).cg)
            ctx.setLineWidth(9)
            ctx.setLineCap(.round)
            let sp = CGMutablePath()
            for k in 0...120 {
                let t = CGFloat(k) / 120
                let a = t * .pi * 4.2 + CGFloat(i)
                let d = 10 + t * 85
                let q = CGPoint(x: p.x + cos(a) * d * 1.06, y: p.y + sin(a) * d)
                if k == 0 { sp.move(to: q) } else { sp.addLine(to: q) }
            }
            ctx.addPath(sp)
            ctx.strokePath()
            ctx.setStrokeColor(RGB(0x5A2810).cg)
            ctx.setLineWidth(22)
            ctx.addPath(s)
            ctx.strokePath()
            ctx.setStrokeColor(RGB(0x8A4520, alpha: 0.8).cg)
            ctx.setLineWidth(34)
            ctx.addPath(s)
            ctx.strokePath()
        }
    }
    // Narutomaki, top right of the nori.
    do {
        let p = CGPoint(x: c.x + 50, y: c.y - 200)
        let n = blobPath(p, 62, jitter: 0.0, points: 16, seed: 1)
        let ridge = CGMutablePath()
        for k in 0...96 {
            let a = CGFloat(k) / 96 * .pi * 2
            let d = 62 + (k % 2 == 0 ? 5 : -2)
            let q = CGPoint(x: p.x + cos(a) * CGFloat(d), y: p.y + sin(a) * CGFloat(d))
            if k == 0 { ridge.move(to: q) } else { ridge.addLine(to: q) }
        }
        ridge.closeSubpath()
        _ = n
        withShadow(ctx, dy: 8, blur: 16, RGB(0x3A1500, alpha: 0.45)) { fill(ctx, ridge, RGB(0xFFFFFF)) }
        shade(ctx, ridge, [RGB(0xFFFFFF), RGB(0xFBF4EE), RGB(0xE4D6CC)])
        ctx.setStrokeColor(RGB(0xE8577A).cg)
        ctx.setLineWidth(10)
        ctx.setLineCap(.round)
        let sp = CGMutablePath()
        for k in 0...100 {
            let t = CGFloat(k) / 100
            let a = t * .pi * 4
            let d = 6 + t * 40
            let q = CGPoint(x: p.x + cos(a) * d, y: p.y + sin(a) * d)
            if k == 0 { sp.move(to: q) } else { sp.addLine(to: q) }
        }
        ctx.addPath(sp)
        ctx.strokePath()
    }
    // Soft-boiled egg halves, left.
    for (i, p) in [CGPoint(x: c.x - 150, y: c.y - 30), CGPoint(x: c.x - 20, y: c.y + 130)].enumerated() {
        let a = deg(i == 0 ? -20 : 25)
        let w = CGMutablePath()
        w.addEllipse(in: CGRect(x: -100, y: -78, width: 200, height: 156))
        var t = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: a)
        let egg = w.copy(using: &t)!
        withShadow(ctx, dy: 10, blur: 20, RGB(0x3A1500, alpha: 0.45)) { fill(ctx, egg, RGB(0xE7C9A0)) }
        shade(ctx, egg, [RGB(0xFFFFFF), RGB(0xF7EEDC), RGB(0xD9BE96)])
        let y = CGMutablePath()
        y.addEllipse(in: CGRect(x: -48, y: -42, width: 96, height: 84))
        var ty = CGAffineTransform(translationX: p.x + 6, y: p.y + 2).rotated(by: a)
        let yolk = y.copy(using: &ty)!
        shade(ctx, yolk, [RGB(0xFFB23A), RGB(0xF28A12), RGB(0xD9700A)], light: CGPoint(x: 0, y: 0))
        ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.5).cg)
        ctx.fillEllipse(in: CGRect(x: p.x - 20, y: p.y - 22, width: 22, height: 12))
    }
    // Scallions, a loose pile in the middle.
    var r3 = SeededRandom(91)
    for _ in 0..<44 {
        let p = pt(CGPoint(x: c.x + 25, y: c.y - 20), r3.next() * .pi * 2, sqrt(r3.next()) * 85)
        let ring = blobPath(p, 11, jitter: 0.1, points: 7, seed: UInt64(p.x * 3 + p.y), stretch: 1.2, angle: r3.next() * 3)
        withShadow(ctx, dy: 2, blur: 4, RGB(0x000000, alpha: 0.3)) { fill(ctx, ring, (r3.next() > 0.4 ? RGB(0x4E9A2E) : RGB(0x7BBF4A))) }
        fill(ctx, blobPath(p, 6, jitter: 0.12, points: 6, seed: UInt64(p.y), stretch: 1.2, angle: 0), RGB(0xE3F4C0))
    }
    drawSesame(ctx, center: c, radius: ri * 0.7, count: 40, seedSize: 6, color: RGB(0xFFF4DA), seed: 93)
    // Rim highlight.
    ctx.setStrokeColor(RGB(0xFFFFFF, alpha: 0.2).cg)
    ctx.setLineWidth(5)
    ctx.addArc(center: c, radius: r - 8, startAngle: deg(190), endAngle: deg(255), clockwise: false)
    ctx.strokePath()
}

// MARK: - 5. Pizza

func drawPizza(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0x2F4A3E), outer: RGB(0x172A22), dark: (RGB(0x1C2E26), RGB(0x08120D)))
    let c = CGPoint(x: 512, y: 512)
    let r: CGFloat = 440
    let crust = blobPath(c, r, jitter: 0.012, points: 18, seed: 5)
    withShadow(ctx, dy: 20, blur: 44, RGB(0x000000, alpha: 0.55)) { fill(ctx, crust, RGB(0xC98B44)) }
    // Puffy cornicione: darker where it meets the sauce, bright on the crown, browned at the outer edge.
    clipped(ctx, crust) {
        ctx.drawRadialGradient(gradient([RGB(0xC98A46), RGB(0xE9B46C), RGB(0xF5CF8E), RGB(0xD99A54), RGB(0x9E5E26)], [0.74, 0.8, 0.88, 0.95, 1]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 1.01, options: [.drawsAfterEndLocation])
        let hl = CGPoint(x: c.x - r * 0.5, y: c.y - r * 0.55)
        ctx.drawRadialGradient(gradient([RGB(0xFFFFFF, alpha: 0.22), RGB(0xFFFFFF, alpha: 0)]), startCenter: hl, startRadius: 0,
                               endCenter: hl, endRadius: r * 0.9, options: [])
        let lo = CGPoint(x: c.x + r * 0.5, y: c.y + r * 0.6)
        ctx.drawRadialGradient(gradient([RGB(0x5A2A08, alpha: 0.22), RGB(0x5A2A08, alpha: 0)]), startCenter: lo, startRadius: 0,
                               endCenter: lo, endRadius: r * 0.9, options: [])
    }
    // Char blisters on the crust.
    var rng = SeededRandom(101)
    clipped(ctx, crust) {
        for _ in 0..<26 {
            let p = pt(c, rng.next() * .pi * 2, rng.range(r * 0.86, r * 0.99))
            let s = rng.range(10, 24)
            // Leopard spotting: a dark blister with a soft scorched halo.
            ctx.drawRadialGradient(gradient([RGB(0x6A3A14, alpha: 0.55), RGB(0x6A3A14, alpha: 0)]), startCenter: p, startRadius: 0,
                                   endCenter: p, endRadius: s * 1.8, options: [])
            fill(ctx, blobPath(p, s * 0.45, jitter: 0.3, points: 6, seed: UInt64(p.x * 5), stretch: 1.3, angle: rng.next() * 3), RGB(0x3A1E0C, alpha: rng.range(0.5, 0.85)))
        }
    }
    // Sauce.
    let sr = r * 0.8
    let sauce = blobPath(c, sr, jitter: 0.03, points: 16, seed: 6)
    withShadow(ctx, dy: -4, blur: 10, RGB(0x6A3A10, alpha: 0.6)) { fill(ctx, sauce, RGB(0xC7341C)) }
    shade(ctx, sauce, [RGB(0xE5502C), RGB(0xC7341C), RGB(0xA2240F)], locations: [0, 0.65, 1])
    // Mozzarella.
    let mozz: [(CGFloat, CGFloat, CGFloat)] = [(-40, 10, 78), (90, -150, 72), (210, 50, 74), (-210, -90, 72),
                                              (-120, 190, 70), (110, 200, 66), (-40, -240, 56)]
    for (i, m) in mozz.enumerated() {
        let p = CGPoint(x: c.x + m.0, y: c.y + m.1)
        let b = blobPath(p, m.2, jitter: 0.22, points: 9, seed: UInt64(i * 7 + 1), stretch: 1.1, angle: CGFloat(i))
        withShadow(ctx, dy: 3, blur: 6, RGB(0x5A1500, alpha: 0.3)) { fill(ctx, b, RGB(0xFBF1D9)) }
        shade(ctx, b, [RGB(0xFFFDF5), RGB(0xFBF1DA), RGB(0xEBCF9A)], light: CGPoint(x: -0.25, y: -0.3), locations: [0, 0.55, 1])
        // Browned spots.
        var r2 = SeededRandom(UInt64(i) + 200)
        clipped(ctx, b) {
            let q = pt(p, r2.next() * .pi * 2, m.2 * r2.range(0.45, 0.8))
            ctx.drawRadialGradient(gradient([RGB(0xE0A458, alpha: 0.45), RGB(0xE0A458, alpha: 0)]), startCenter: q, startRadius: 0,
                                   endCenter: q, endRadius: m.2 * 0.55, options: [])
        }
    }
    // Basil.
    drawBasil(ctx, CGPoint(x: c.x + 5, y: c.y - 70), length: 170, angle: deg(-30))
    drawBasil(ctx, CGPoint(x: c.x - 170, y: c.y + 60), length: 140, angle: deg(110))
    drawBasil(ctx, CGPoint(x: c.x + 150, y: c.y + 120), length: 150, angle: deg(20))
    drawBasil(ctx, CGPoint(x: c.x + 130, y: c.y - 230), length: 120, angle: deg(-110))
    drawBasil(ctx, CGPoint(x: c.x - 230, y: c.y - 170), length: 110, angle: deg(-160))
    // Olive oil sheen over the sauce.
    clipped(ctx, sauce) {
        var r3 = SeededRandom(111)
        for _ in 0..<14 {
            let q = pt(c, deg(-135) + r3.range(-0.9, 0.9), r3.range(60, sr * 0.9))
            ctx.setFillColor(RGB(0xFFD9A0, alpha: 0.35).cg)
            ctx.fillEllipse(in: CGRect(x: q.x, y: q.y, width: r3.range(10, 26), height: r3.range(5, 10)))
        }
    }
}

// MARK: - 6. Salad

func drawSalad(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0xF49A7C), outer: RGB(0xD9694C))
    let c = CGPoint(x: 512, y: 520)
    let ri = drawVessel(ctx, c, 430, rim: RGB(0xFFFFFF), rimShade: RGB(0xEDE5DC), inside: RGB(0xFBF8F2), insideShade: RGB(0xE2D8CB),
                        well: 0.88, shadow: RGB(0x6A1A00, alpha: 0.38))
    clipped(ctx, ellipsePath(c, ri)) {
        // Leaves: layered, ruffled greens with a few radicchio leaves for colour.
        fill(ctx, ellipsePath(c, ri), RGB(0x3E7A2A))
        var rng = SeededRandom(121)
        let greens: [(RGB, RGB)] = [(RGB(0xA9D872), RGB(0x4A8E2E)), (RGB(0xCBE993), RGB(0x6AAA3E)), (RGB(0x7DB850), RGB(0x356E22)),
                                    (RGB(0xA9D872), RGB(0x4A8E2E)), (RGB(0xC2507A), RGB(0x7A1A3C))]
        for i in 0..<40 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * ri * 0.95)
            let len = rng.range(200, 300)
            let a = rng.next() * .pi * 2
            let g = i % 9 == 4 ? greens[4] : greens[i % 4]
            let leaf = blobPath(p, len / 2, jitter: 0.07, points: 26, seed: UInt64(i + 1), stretch: 1.35, angle: a)
            withShadow(ctx, dy: 6, blur: 16, RGB(0x0F2A00, alpha: 0.45)) { fill(ctx, leaf, g.1) }
            shade(ctx, leaf, [g.0, g.0.mixed(with: g.1, 0.45), g.1], light: CGPoint(x: -0.15, y: -0.25))
            ctx.saveGState()
            ctx.addPath(leaf)
            ctx.clip()
            ctx.setStrokeColor((i % 9 == 4 ? RGB(0xF6DDE6) : RGB(0xEAF7CC)).with(alpha: 0.65).cg)
            ctx.setLineCap(.round)
            ctx.setLineWidth(5)
            ctx.move(to: pt(p, a, -len * 0.55))
            ctx.addQuadCurve(to: pt(p, a, len * 0.4), control: pt(p, a + .pi / 2, 14))
            ctx.strokePath()
            ctx.setLineWidth(2.5)
            for k in 0..<4 {
                let base = pt(p, a, -len * 0.3 + CGFloat(k) * len * 0.17)
                for sgn: CGFloat in [-1, 1] {
                    ctx.move(to: base)
                    ctx.addQuadCurve(to: pt(pt(base, a, len * 0.12), a + .pi / 2, sgn * len * 0.22), control: pt(base, a + .pi / 2, sgn * len * 0.08))
                }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
        // Cucumber.
        for (i, p) in [CGPoint(x: c.x + 175, y: c.y + 130), CGPoint(x: c.x - 220, y: c.y - 20), CGPoint(x: c.x + 40, y: c.y - 235),
                       CGPoint(x: c.x - 70, y: c.y + 235)].enumerated() {
            let cr: CGFloat = 62
            withShadow(ctx, dy: 6, blur: 12, RGB(0x1A3A00, alpha: 0.35)) { fill(ctx, ellipsePath(p, cr), RGB(0x2E6A26)) }
            fill(ctx, ellipsePath(p, cr * 0.9), RGB(0xDDF0B8))
            fill(ctx, ellipsePath(p, cr * 0.55), RGB(0xC5E29C))
            var r2 = SeededRandom(UInt64(i) + 300)
            for k in 0..<7 {
                let sp = pt(p, CGFloat(k) / 7 * .pi * 2 + r2.next() * 0.2, cr * 0.32)
                fill(ctx, leafPath(sp, length: 13, width: 5, angle: CGFloat(k) / 7 * .pi * 2), RGB(0xF4F9E2))
            }
        }
    }
    // Feta.
    for (i, p) in [CGPoint(x: c.x + 10, y: c.y + 10), CGPoint(x: c.x + 230, y: c.y - 160), CGPoint(x: c.x - 250, y: c.y + 120),
                   CGPoint(x: c.x + 130, y: c.y + 250), CGPoint(x: c.x - 120, y: c.y - 250)].enumerated() {
        let rough = roundedRect(p, w: 66, h: 60, r: 9, angle: CGFloat(i) * 0.7)
        withShadow(ctx, dy: 6, blur: 12, RGB(0x1A2A00, alpha: 0.4)) { fill(ctx, rough, RGB(0xFBF8F0)) }
        shade(ctx, rough, [RGB(0xFFFFFF), RGB(0xF6F1E4), RGB(0xE2D9C3)])
    }
    // Olives.
    for (i, p) in [CGPoint(x: c.x + 220, y: c.y + 30), CGPoint(x: c.x - 40, y: c.y + 150), CGPoint(x: c.x - 180, y: c.y - 150),
                   CGPoint(x: c.x + 60, y: c.y - 130), CGPoint(x: c.x - 270, y: c.y - 10)].enumerated() {
        let o = blobPath(p, 32, jitter: 0.03, points: 9, seed: UInt64(i + 80), stretch: 1.3, angle: CGFloat(i) * 1.1)
        withShadow(ctx, dy: 5, blur: 10, RGB(0x000000, alpha: 0.4)) { fill(ctx, o, RGB(0x3B1E2C)) }
        shade(ctx, o, [RGB(0x8A5A72), RGB(0x4A2638), RGB(0x2A1220)], light: CGPoint(x: -0.35, y: -0.4))
        ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.55).cg)
        ctx.fillEllipse(in: CGRect(x: p.x - 18, y: p.y - 17, width: 12, height: 7))
    }
    // Tomatoes on top.
    for (i, p) in [CGPoint(x: c.x - 70, y: c.y - 60), CGPoint(x: c.x + 120, y: c.y - 120), CGPoint(x: c.x - 150, y: c.y + 140),
                   CGPoint(x: c.x + 60, y: c.y + 80), CGPoint(x: c.x - 230, y: c.y - 200), CGPoint(x: c.x + 250, y: c.y - 10)].enumerated() {
        drawTomatoHalf(ctx, p, i % 2 == 0 ? 74 : 66, angle: CGFloat(i) * 1.3)
    }
    drawFlecks(ctx, center: c, radius: ri * 0.8, count: 40, size: 3.5, colors: [RGB(0x2A2420)], seed: 141)
}

// MARK: - Rendering

struct Icon {
    /// Asset name suffix: "" for the default `AppIcon`, otherwise `AppIcon<suffix>` / `IconPreview<suffix>`.
    let suffix: String
    /// File name part and label in the contact sheet.
    let slug: String
    let label: String
    let draw: (CGContext) -> Void
}

let icons: [Icon] = [
    Icon(suffix: "", slug: "salad", label: "Salad (default)", draw: drawSalad),
    Icon(suffix: "GrainBowl", slug: "grain-bowl", label: "Grain Bowl", draw: drawGrainBowl),
    Icon(suffix: "Spaghetti", slug: "spaghetti", label: "Spaghetti", draw: drawSpaghetti),
    Icon(suffix: "Shakshuka", slug: "shakshuka", label: "Shakshuka", draw: drawShakshuka),
    Icon(suffix: "Ramen", slug: "ramen", label: "Ramen", draw: drawRamen),
    Icon(suffix: "Margherita", slug: "margherita", label: "Margherita", draw: drawPizza),
]

func render(_ icon: Icon, _ look: Appearance) -> CGImage {
    appearance = look
    transparentDarkGround = icon.suffix.isEmpty
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    icon.draw(ctx)
    switch look {
    case .light: return flattened(ctx.makeImage()!)
    case .dark: return transparentDarkGround ? ctx.makeImage()! : flattened(ctx.makeImage()!)
    case .tinted: return tintedMark(ctx)
    }
}

/// Opaque copy without an alpha channel (the App Store rejects icons with one).
func flattened(_ image: CGImage) -> CGImage {
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(RGB(0x000000).cg)
    ctx.fill(rect)
    ctx.draw(image, in: rect)
    return ctx.makeImage()!
}

/// Tinted appearance: the dish's luminance over black (premultiplied colour is the colour over
/// black), levels stretched per icon so red and green don't collapse into one grey once the system
/// tints it, with a gentle S-curve for separation.
func tintedMark(_ ctx: CGContext) -> CGImage {
    let count = ctx.width * ctx.height * 4
    let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: count)
    var lum = [Double](repeating: 0, count: count / 4)
    var histogram = [Int](repeating: 0, count: 256)
    var covered = 0
    for i in stride(from: 0, to: count, by: 4) {
        let l = (0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])) / 255
        lum[i / 4] = l
        if pixels[i + 3] > 128 { histogram[Int(l * 255)] += 1; covered += 1 }
    }
    func percentile(_ p: Double) -> Double {
        var sum = 0
        for (v, n) in histogram.enumerated() {
            sum += n
            if Double(sum) >= p * Double(covered) { return Double(v) / 255 }
        }
        return 1
    }
    let lo = percentile(0.04), hi = percentile(0.995)
    for i in stride(from: 0, to: count, by: 4) {
        let t = min(max((lum[i / 4] - lo) / max(hi - lo, 0.01), 0), 1)
        let curved = t * t * (3 - 2 * t) * 0.6 + t * 0.4
        let v = UInt8(min(255, (0.04 + curved * 0.96) * 255) * Double(pixels[i + 3]) / 255)
        pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
    }
    return flattened(ctx.makeImage()!)
}

/// Downscaled square preview for the in-app picker. Transparent (dark) renders sit on a dark
/// home-screen-like backdrop, like the system shows them.
func preview(_ image: CGImage, pixels: Int = 384) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    if image.alphaInfo == .premultipliedLast {
        ctx.drawLinearGradient(gradient([RGB(0x2C2C2E), RGB(0x1C1C1E)]), start: CGPoint(x: 0, y: rect.maxY), end: .zero, options: [])
    }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: rect)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func writeJSON(_ json: String, to dir: URL) throws {
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func appIconContents(_ name: String) -> String {
    func entry(_ file: String, _ luminosity: String?) -> String {
        let appearances = luminosity.map {
            "\n      \"appearances\": [\n        {\n          \"appearance\": \"luminosity\",\n          \"value\": \"\($0)\"\n        }\n      ],"
        } ?? ""
        return "    {\(appearances)\n      \"filename\": \"\(file)\",\n      \"idiom\": \"universal\",\n      \"platform\": \"ios\",\n      \"size\": \"1024x1024\"\n    }"
    }
    let images = [entry("\(name).png", nil), entry("\(name)-dark.png", "dark"), entry("\(name)-tinted.png", "tinted")]
    return "{\n  \"images\": [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\": {\n    \"author\": \"xcode\",\n    \"version\": 1\n  }\n}"
}

func imageSetContents(_ name: String) -> String {
    """
    {
      "images": [
        {
          "filename": "\(name).png",
          "idiom": "universal"
        },
        {
          "appearances": [
            {
              "appearance": "luminosity",
              "value": "dark"
            }
          ],
          "filename": "\(name)-dark.png",
          "idiom": "universal"
        }
      ],
      "info": {
        "author": "xcode",
        "version": 1
      }
    }
    """
}

var arguments = Array(CommandLine.arguments.dropFirst())
var sheetDir: URL?
if let flag = arguments.firstIndex(of: "--sheet"), flag + 1 < arguments.count {
    sheetDir = URL(fileURLWithPath: arguments[flag + 1])
    arguments.removeSubrange(flag...(flag + 1))
}
let resources = URL(fileURLWithPath: arguments.first ?? "MealMate/Resources")
let fm = FileManager.default
let alternatesCatalog = resources.appendingPathComponent("AppIcons.xcassets")

var rendered: [(icon: Icon, images: [Appearance: CGImage])] = []
for icon in icons {
    var images: [Appearance: CGImage] = [:]
    for look in Appearance.allCases { images[look] = render(icon, look) }
    rendered.append((icon, images))

    let iconName = "AppIcon" + icon.suffix
    let iconDir = icon.suffix.isEmpty
        ? resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
        : alternatesCatalog.appendingPathComponent("\(iconName).appiconset")
    try fm.createDirectory(at: iconDir, withIntermediateDirectories: true)
    if !icon.suffix.isEmpty { try writeJSON(appIconContents(iconName), to: iconDir) }
    try writePNG(images[.light]!, to: iconDir.appendingPathComponent("\(iconName).png"))
    try writePNG(images[.dark]!, to: iconDir.appendingPathComponent("\(iconName)-dark.png"))
    try writePNG(images[.tinted]!, to: iconDir.appendingPathComponent("\(iconName)-tinted.png"))

    let previewName = "IconPreview" + (icon.suffix.isEmpty ? "Default" : icon.suffix)
    let previewDir = alternatesCatalog.appendingPathComponent("\(previewName).imageset")
    try fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
    try writeJSON(imageSetContents(previewName), to: previewDir)
    try writePNG(preview(images[.light]!), to: previewDir.appendingPathComponent("\(previewName).png"))
    try writePNG(preview(images[.dark]!), to: previewDir.appendingPathComponent("\(previewName)-dark.png"))
    print("wrote \(iconName) + \(previewName)")
}

// MARK: - Contact sheet

guard let sheetDir else { exit(0) }
try fm.createDirectory(at: sheetDir, withIntermediateDirectories: true)
for (index, entry) in rendered.enumerated() {
    try writePNG(entry.images[.light]!, to: sheetDir.appendingPathComponent("variant-\(index + 1)-\(entry.icon.slug).png"))
}

/// iOS-style mask (continuous corners approximated by a rounded rect at 22.4%).
func iconMask(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237, cornerHeight: rect.width * 0.2237, transform: nil)
}

/// An icon as the home screen shows it. Transparent renders get the system's dark backdrop;
/// `tint` multiplies a tinted render like the tinted home screen does.
func drawIcon(_ ctx: CGContext, _ image: CGImage, in rect: CGRect, tint: RGB? = nil) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.02), blur: rect.width * 0.06, color: RGB(0x000000, alpha: 0.25).cg)
    ctx.addPath(iconMask(rect))
    ctx.setFillColor(RGB(0x1C1C1E).cg)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(iconMask(rect))
    ctx.clip()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    if let tint {
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(tint.cg)
        ctx.fill(CGRect(origin: .zero, size: rect.size))
    }
    ctx.restoreGState()
}

func label(_ text: String, at p: CGPoint, size s: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s, weight: weight), .foregroundColor: color]
    NSAttributedString(string: text, attributes: attrs).draw(at: p)
}

let cols = 3
let cell = CGSize(width: 540, height: 480)
let margin: CGFloat = 60
let rows = Int(ceil(Double(rendered.count) / Double(cols)))
let strips: [(String, (RGB, RGB), Appearance, RGB?)] = [
    ("Light", (RGB(0xD9DEE6), RGB(0xB8C2D0)), .light, nil),
    ("Dark", (RGB(0x23262E), RGB(0x101216)), .dark, nil),
    ("Tinted", (RGB(0x2A2420), RGB(0x14100E)), .tinted, RGB(0xF2B36B)),
]
let sheetW = margin * 2 + cell.width * CGFloat(cols)
let sheetH = margin * 2 + cell.height * CGFloat(rows) + CGFloat(strips.count) * 240
let sheet = CGContext(data: nil, width: Int(sheetW), height: Int(sheetH), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
sheet.translateBy(x: 0, y: sheetH)
sheet.scaleBy(x: 1, y: -1)
sheet.interpolationQuality = .high
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: true)
sheet.setFillColor(RGB(0xF4F3F0).cg)
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

for (i, entry) in rendered.enumerated() {
    let o = CGPoint(x: margin + CGFloat(i % cols) * cell.width, y: margin + CGFloat(i / cols) * cell.height)
    label("\(i + 1) · \(entry.icon.label)", at: o, size: 34, color: .black)
    let image = entry.images[.light]!
    drawIcon(sheet, image, in: CGRect(x: o.x, y: o.y + 56, width: 360, height: 360))
    drawIcon(sheet, image, in: CGRect(x: o.x + 380, y: o.y + 56, width: 120, height: 120))
    drawIcon(sheet, image, in: CGRect(x: o.x + 380, y: o.y + 200, width: 60, height: 60))
}

let stripTop = margin + cell.height * CGFloat(rows)
for (k, strip) in strips.enumerated() {
    let r = CGRect(x: margin, y: stripTop + CGFloat(k) * 240, width: sheetW - margin * 2, height: 220)
    sheet.saveGState()
    sheet.addPath(CGPath(roundedRect: r, cornerWidth: 28, cornerHeight: 28, transform: nil))
    sheet.clip()
    sheet.drawLinearGradient(gradient([strip.1.0, strip.1.1]), start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
    sheet.restoreGState()
    let gap = (r.width - CGFloat(rendered.count) * 120) / CGFloat(rendered.count + 1)
    let textColor: NSColor = strip.2 == .light ? .black : .white
    for (i, entry) in rendered.enumerated() {
        let x = r.minX + gap + CGFloat(i) * (120 + gap)
        drawIcon(sheet, entry.images[strip.2]!, in: CGRect(x: x, y: r.minY + 30, width: 120, height: 120), tint: strip.3)
        label("\(i + 1)", at: CGPoint(x: x + 54, y: r.minY + 160), size: 22, color: textColor, weight: .medium)
    }
    label(strip.0, at: CGPoint(x: r.minX + 16, y: r.minY + 10), size: 18, color: textColor.withAlphaComponent(0.6), weight: .medium)
}

try writePNG(sheet.makeImage()!, to: sheetDir.appendingPathComponent("overview.png"))
print("wrote \(sheetDir.appendingPathComponent("overview.png").path)")
