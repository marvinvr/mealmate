#!/usr/bin/env swift
// MealMate subscription app icons with dishes: Enamel Cocotte, Candlelight and Sunday Brunch.
//
// Usage:  swift Design/make-icon-subscriber.swift [resources-dir] [--sheet <dir>]
// Faster: swiftc -O Design/make-icon-subscriber.swift -o /tmp/sub-icons && /tmp/sub-icons
// Default resources dir: MealMate/Resources. Run from the repo root.
//
// They are the only subscription icons (picked from ten design proposals; they replaced Copper
// Pot and Midnight Kitchen). The default and the food icons come from
// Design/make-icon-variants.swift, whose helpers are copied here (same light, shadows and ground
// grain).
//
// Every icon is 1024x1024 in three appearances:
//   <Name>.png         light, opaque, no alpha channel
//   <Name>-dark.png    dark: a deeper, opaque ground
//   <Name>-tinted.png  tinted: the dish as a grayscale mark on black, the system tints it
//
// Writes:
//   AppIcons.xcassets/AppIcon<Name>.appiconset       alternate icons (subscription perk, docs/supporter.md)
//   AppIcons.xcassets/IconPreview<Name>.imageset     384px picker previews (light + dark)
// With --sheet: variant-<n>-<name>.png and overview.png (every icon large, at home-screen size
// and on light / dark / tinted home screens) into <dir>, for reviewing changes.

import AppKit
import CoreGraphics
import simd

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


// MARK: - Extra helpers for the subscription icons

/// Conic (angular) gradient around `center`, built from thin wedges (from Design/make-icon.swift).
/// `angle` is where the first colour sits; colours advance clockwise on screen.
func drawConic(_ ctx: CGContext, _ colors: [RGB], _ locations: [CGFloat]? = nil, center: CGPoint, radius: CGFloat, angle: CGFloat) {
    let stops = locations ?? colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
    func color(at t: CGFloat) -> RGB {
        for i in 1..<stops.count where t <= stops[i] {
            let span = stops[i] - stops[i - 1]
            return colors[i - 1].mixed(with: colors[i], span > 0 ? (t - stops[i - 1]) / span : 0)
        }
        return colors[colors.count - 1]
    }
    let slices = 1440
    let step = 2 * CGFloat.pi / CGFloat(slices)
    for i in 0..<slices {
        let a0 = angle + CGFloat(i) * step
        ctx.setFillColor(color(at: (CGFloat(i) + 0.5) / CGFloat(slices)).cg)
        ctx.move(to: center)
        ctx.addArc(center: center, radius: radius * 1.05, startAngle: a0, endAngle: a0 + step * 1.6, clockwise: false)
        ctx.closePath()
        ctx.fillPath()
    }
}

/// Smooth value noise in [0, 1] (from Design/make-icon.swift).
struct Noise {
    let seed: UInt32
    private func hash(_ x: Int32, _ y: Int32) -> Float {
        var h = UInt32(bitPattern: x) &* 374761393 &+ UInt32(bitPattern: y) &* 668265263 &+ seed &* 2246822519
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65535
    }
    func value(_ x: Float, _ y: Float) -> Float {
        let xi = Int32(floor(x)), yi = Int32(floor(y))
        let xf = x - floor(x), yf = y - floor(y)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v
    }
    func fbm(_ x: Float, _ y: Float, octaves: Int = 4) -> Float {
        var sum: Float = 0, amp: Float = 0.5, f: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            sum += value(x * f, y * f) * amp
            norm += amp
            amp *= 0.5
            f *= 2
        }
        return sum / norm
    }
}

/// Procedural texture: `pixel(x, y)` returns straight (non-premultiplied) r, g, b, a in 0...1, with
/// x/y in icon points, y down. Draw it with `drawTexture` so it lands the right way up.
func textureImage(width: Int = Int(size), height: Int = Int(size), _ pixel: (Float, Float) -> (Float, Float, Float, Float)) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for py in 0..<height {
        for px in 0..<width {
            let (r, g, b, a) = pixel(Float(px), Float(py))
            let i = (py * width + px) * 4
            let aa = max(0, min(1, a))
            pixels[i] = UInt8(max(0, min(1, r)) * aa * 255)
            pixels[i + 1] = UInt8(max(0, min(1, g)) * aa * 255)
            pixels[i + 2] = UInt8(max(0, min(1, b)) * aa * 255)
            pixels[i + 3] = UInt8(aa * 255)
        }
    }
    let data = CFDataCreate(nil, pixels, pixels.count)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: sRGB,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// Draws a texture made by `textureImage` into the flipped icon context, top row at `rect.minY`.
func drawTexture(_ ctx: CGContext, _ image: CGImage, in rect: CGRect = CGRect(x: 0, y: 0, width: size, height: size)) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

/// Soft radial glow (light pool, candle halo, ember glow).
func glow(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: RGB, _ alpha: CGFloat) {
    ctx.drawRadialGradient(gradient([color.with(alpha: alpha), color.with(alpha: alpha * 0.35), color.with(alpha: 0)], [0, 0.4, 1]),
                           startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}

/// Darkens towards the corners. 0 = none.
func vignette(_ ctx: CGContext, _ amount: CGFloat, center: CGPoint = CGPoint(x: size / 2, y: size / 2)) {
    guard amount > 0 else { return }
    ctx.drawRadialGradient(gradient([RGB(0x000000, alpha: 0), RGB(0x000000, alpha: amount)], [0.45, 1]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.78, options: [.drawsAfterEndLocation])
}

/// Elliptical specular glint, rotated.
func glint(_ ctx: CGContext, _ c: CGPoint, w: CGFloat, h: CGFloat, angle: CGFloat, alpha: CGFloat = 0.8) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.scaleBy(x: 1, y: h / w)
    ctx.drawRadialGradient(gradient([RGB(0xFFFFFF, alpha: alpha), RGB(0xFFFFFF, alpha: 0)]), startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: w / 2, options: [])
    ctx.restoreGState()
}

/// Ring (annulus) path.
func ringPath(_ c: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addEllipse(in: circle(c, outer))
    p.addEllipse(in: circle(c, inner))
    return p
}

func clippedEO(_ ctx: CGContext, _ path: CGPath, _ body: () -> Void) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)
    body()
    ctx.restoreGState()
}

/// Light/dark pick for colours inside a dish function: dark appearance gets `dark`.
func look(_ light: RGB, _ dark: RGB) -> RGB { appearance == .dark ? dark : light }


// MARK: - Shaded cookware (Enamel Cocotte)
//
// The vessels are shaded per pixel from a radial profile (rim, wall, floor) so metal and enamel catch
// the light like real turned surfaces: Lambert from the family's upper-left light, a soft reflected
// "window" and a specular glint. The food on top uses the same vector helpers as the food icons.

typealias AVec = SIMD3<Float>

/// Key light from the upper left (y runs down), like the rest of the family.
let aLight = simd_normalize(AVec(-0.42, -0.5, 0.76))
let aHalf = simd_normalize(aLight + AVec(0, 0, 1))
/// A soft window above and to the upper left that polished surfaces reflect.
let aWindow = simd_normalize(AVec(-0.48, -0.6, 0.64))

func aV(_ hex: UInt32) -> AVec {
    AVec(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
}

func aSmooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

func aRamp(_ stops: [(Float, AVec)], _ t: Float) -> AVec {
    if t <= stops[0].0 { return stops[0].1 }
    for i in 1..<stops.count where t <= stops[i].0 {
        let k = (t - stops[i - 1].0) / (stops[i].0 - stops[i - 1].0)
        return stops[i - 1].1 + (stops[i].1 - stops[i - 1].1) * k
    }
    return stops[stops.count - 1].1
}

func aHash(_ x: Int32, _ y: Int32, _ seed: UInt32) -> Float {
    var h = UInt32(bitPattern: x) &* 374761393 &+ UInt32(bitPattern: y) &* 668265263 &+ seed &* 2246822519
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Float(h & 0xFFFF) / 65535
}

/// Offset of (x, y) from the nearest hammer blow, in cells (Voronoi over a jittered grid).
func aDimple(_ x: Float, _ y: Float, _ s: Float) -> SIMD2<Float> {
    let gx = x / s, gy = y / s
    let ix = Int32(floor(gx)), iy = Int32(floor(gy))
    var best: Float = 1e9
    var offset = SIMD2<Float>(0, 0)
    for j in Int32(-1)...1 {
        for i in Int32(-1)...1 {
            let cx = ix + i, cy = iy + j
            let px = Float(cx) + 0.12 + 0.76 * aHash(cx, cy, 1)
            let py = Float(cy) + 0.12 + 0.76 * aHash(cx, cy, 2)
            let o = SIMD2<Float>(gx - px, gy - py)
            let dd = simd_dot(o, o)
            if dd < best { best = dd; offset = o }
        }
    }
    return offset
}

/// What a vessel's material sees at one pixel.
struct AShade {
    var n: AVec
    /// Distance from the centre / radius.
    var d: Float
    var zone: Int
    var x: Float, y: Float
    var lambert: Float { max(0, simd_dot(n, aLight)) }
    func spec(_ power: Float) -> Float { pow(max(0, simd_dot(n, aHalf)), power) }
    /// How directly the surface mirrors the window, -1...1.
    var window: Float {
        let r = AVec(2 * n.z * n.x, 2 * n.z * n.y, 2 * n.z * n.z - 1)
        return simd_dot(r, aWindow)
    }
    /// Fine per-pixel grain, -0.5...0.5.
    func grain(_ seed: UInt32) -> Float { aHash(Int32(x), Int32(y), seed) - 0.5 }
}

/// A round vessel seen from above, shaded per pixel. `profile(d)` gives the surface's radial tilt at
/// d = distance / radius (positive faces outward, negative faces the centre) and a zone id.
/// `radiusScale(angle)` bends the outline (pour spouts). Hammered zones get dimples of `dimple` points.
func aVesselImage(_ c: CGPoint, _ radius: CGFloat, dimple: Float = 0, dimpleDepth: Float = 0.3, dimpleZones: Set<Int> = [],
                  floorDimple: Float = 1,
                  radiusScale: ((Float) -> Float)? = nil,
                  profile: (Float) -> (Float, Int), material: (AShade) -> AVec) -> CGImage {
    let cx = Float(c.x), cy = Float(c.y), r0 = Float(radius)
    return textureImage { x, y in
        let dx = x + 0.5 - cx, dy = y + 0.5 - cy
        let dist = sqrt(dx * dx + dy * dy)
        let r = r0 * (radiusScale?(atan2(dy, dx)) ?? 1)
        let alpha = max(0, min(1, r - dist + 0.5))
        if alpha <= 0 { return (0, 0, 0, 0) }
        let ux = dist > 0 ? dx / dist : 0, uy = dist > 0 ? dy / dist : 0
        let d = dist / r
        let (tilt, zone) = profile(d)
        let t = max(-0.95, min(0.95, tilt))
        var n = AVec(ux * t, uy * t, sqrt(1 - t * t))
        if dimple > 0 && dimpleZones.contains(zone) {
            let o = aDimple(x, y, dimple)
            let k = dimpleDepth * (zone == 0 ? floorDimple : 1)
            n = simd_normalize(n + AVec(-o.x * k, -o.y * k, 0))
        }
        let col = material(AShade(n: n, d: d, zone: zone, x: x, y: y))
        return (col.x, col.y, col.z, alpha)
    }
}

/// Tapered bar from `from` along `angle`, `w0` wide at the start and `w1` at the end, rounded end.
func aBarPath(_ from: CGPoint, angle: CGFloat, length: CGFloat, w0: CGFloat, w1: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: -w0 / 2))
    p.addCurve(to: CGPoint(x: length, y: -w1 / 2), control1: CGPoint(x: length * 0.3, y: -w1 / 2 - (w0 - w1) * 0.1),
               control2: CGPoint(x: length * 0.6, y: -w1 / 2))
    p.addArc(center: CGPoint(x: length, y: 0), radius: w1 / 2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    p.addCurve(to: CGPoint(x: 0, y: w0 / 2), control1: CGPoint(x: length * 0.6, y: w1 / 2),
               control2: CGPoint(x: length * 0.3, y: w1 / 2 + (w0 - w1) * 0.1))
    p.closeSubpath()
    var t = CGAffineTransform(translationX: from.x, y: from.y).rotated(by: angle)
    return p.copy(using: &t)!
}

/// Shades a bar like a cylinder lying along `angle`: colours run across its width.
func aCylinderShade(_ ctx: CGContext, _ path: CGPath, from: CGPoint, angle: CGFloat, width: CGFloat, _ colors: [RGB], _ locations: [CGFloat]) {
    clipped(ctx, path) {
        let n = angle + .pi / 2
        ctx.drawLinearGradient(gradient(colors, locations), start: pt(from, n, -width / 2), end: pt(from, n, width / 2),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

/// Subtle stone or slate mottling over the ground, light and dark appearances only.
func aMottle(_ ctx: CGContext, seed: UInt32, scale: Float, strength: Float) {
    guard appearance != .tinted else { return }
    let n = Noise(seed: seed)
    let image = textureImage { x, y in
        let v = n.fbm(x * scale, y * scale * 1.3, octaves: 5) - 0.5
        return v > 0 ? (1, 1, 1, v * strength) : (0, 0, 0, -v * strength * 1.4)
    }
    drawTexture(ctx, image)
}

// MARK: - Enamel Cocotte

func aCocotteProfile(_ d: Float) -> (Float, Int) {
    if d > 0.9 { return (0.15 + 0.7 * pow((d - 0.9) / 0.1, 1.6), 3) }          // bulging enamelled body
    if d > 0.865 { return ((d - 0.8825) / 0.0175 * 0.6, 2) }                  // bare black rim
    if d > 0.7 { return (-0.72 * aSmooth(0.7, 0.78, d), 1) }                   // cream wall
    return (0, 0)
}

/// Flame ombre on the outside, satin black rim, glossy cream inside.
func aEnamel(_ s: AShade) -> AVec {
    switch s.zone {
    case 3:
        let t = (s.d - 0.9) / 0.1
        let base = aRamp([(0, aV(0xFFA43A)), (0.45, aV(0xF0661C)), (1, aV(0x8E1E08))], t)
        var col = base * (0.42 + 0.72 * s.lambert)
        col += aV(0xFFF4E6) * (0.85 * aSmooth(0.86, 0.97, s.window) + 0.7 * s.spec(90))
        return col
    case 2:
        let v = 0.12 + 0.35 * s.lambert + 0.25 * aSmooth(0.6, 0.98, s.window)
        return aRamp([(0, aV(0x0A0807)), (0.5, aV(0x2A2522)), (1, aV(0x6A625A))], v) + aV(0xFFFFFF) * (0.12 * s.spec(30))
    default:
        // Warm cream: the near (upper-left) wall in shade, the far wall lit.
        var col = aRamp([(0, aV(0xA8967A)), (0.45, aV(0xDCCDB2)), (0.8, aV(0xF8EEDC)), (1, aV(0xFFF9EE))], s.lambert)
        col += aV(0xFFFFFF) * (0.45 * aSmooth(0.9, 0.99, s.window) + 0.3 * s.spec(60))
        return col
    }
}

/// Irregular chunk: a jittered polygon with rounded corners, straighter sides than a blob.
func aChunkPath(_ c: CGPoint, _ r: CGFloat, seed: UInt64, stretch: CGFloat) -> CGPath {
    var rng = SeededRandom(seed &+ 77)
    let n = 5 + Int(rng.next() * 2)
    let phase = rng.next() * .pi
    let a = CGFloat(seed) * 0.9
    let pts: [CGPoint] = (0..<n).map { i in
        let t = phase + (CGFloat(i) + rng.range(-0.25, 0.25)) / CGFloat(n) * .pi * 2
        let d = r * rng.range(0.85, 1.12)
        let x = cos(t) * d * stretch, y = sin(t) * d
        return CGPoint(x: c.x + x * cos(a) - y * sin(a), y: c.y + x * sin(a) + y * cos(a))
    }
    let path = CGMutablePath()
    let mid = { (p: CGPoint, q: CGPoint) in CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
    path.move(to: mid(pts[n - 1], pts[0]))
    for i in 0..<n { path.addArc(tangent1End: pts[i], tangent2End: mid(pts[i], pts[(i + 1) % n]), radius: r * 0.32) }
    path.closeSubpath()
    return path
}

/// Braised beef chunk: irregular, seared and glazed with sauce.
func aBeef(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, seed: UInt64, stretch: CGFloat = 1.25) {
    let path = aChunkPath(p, r, seed: seed, stretch: stretch)
    withShadow(ctx, dy: r * 0.16, blur: r * 0.32, RGB(0x140200, alpha: 0.7)) { fill(ctx, path, RGB(0x4A1E12)) }
    shade(ctx, path, [RGB(0x8E4A30), RGB(0x5A2414), RGB(0x2A0C05)], light: CGPoint(x: -0.35, y: -0.4), locations: [0, 0.5, 1])
    clipped(ctx, path) {
        // Seared, fibrous surface.
        var rng = SeededRandom(seed &+ 3)
        for _ in 0..<40 {
            let q = pt(p, rng.next() * .pi * 2, sqrt(rng.next()) * r * 1.1)
            fill(ctx, blobPath(q, r * rng.range(0.05, 0.16), jitter: 0.4, points: 6, seed: UInt64(q.x * 7 + q.y), stretch: 1.8,
                               angle: CGFloat(seed) * 0.9 + rng.range(-0.3, 0.3)),
                 (rng.next() > 0.5 ? RGB(0x1E0603) : RGB(0xA45E40)).with(alpha: rng.range(0.25, 0.5)))
        }
        // Sauce pooled on the lower side.
        ctx.drawRadialGradient(gradient([RGB(0x3A0804, alpha: 0), RGB(0x3A0804, alpha: 0.55)], [0.5, 1]), startCenter: pt(p, deg(-130), r * 0.3),
                               startRadius: 0, endCenter: pt(p, deg(-130), r * 0.3), endRadius: r * 1.4, options: [])
    }
    // Glossy glaze: a crisp window glint and a few small catchlights.
    glint(ctx, pt(p, deg(-125), r * 0.5), w: r * 0.7, h: r * 0.16, angle: deg(-38), alpha: 0.75)
    var rng = SeededRandom(seed &+ 9)
    for _ in 0..<4 {
        glint(ctx, pt(p, deg(-130) + rng.range(-0.9, 0.9), r * rng.range(0.1, 0.6)), w: r * rng.range(0.12, 0.22), h: r * 0.07,
              angle: deg(-38), alpha: 0.6)
    }
}

/// Carrot round, slightly tilted: a visible side, orange flesh with a paler ring and core.
func aCarrot(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, angle: CGFloat) {
    func disc(_ c: CGPoint, _ rr: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).scaledBy(x: 1, y: 0.78)
        return CGPath(ellipseIn: circle(.zero, rr), transform: &t)
    }
    let side = disc(CGPoint(x: p.x + r * 0.06, y: p.y + r * 0.16), r)
    withShadow(ctx, dy: r * 0.15, blur: r * 0.3, RGB(0x1A0400, alpha: 0.6)) { fill(ctx, side, RGB(0xB04A0C)) }
    shade(ctx, side, [RGB(0xD8641A), RGB(0x9A3A08)])
    let top = disc(p, r)
    shade(ctx, top, [RGB(0xFFA552), RGB(0xF07A26), RGB(0xD25E14)], locations: [0, 0.6, 1])
    ctx.addPath(disc(p, r * 0.6))
    ctx.setStrokeColor(RGB(0xFFC27A, alpha: 0.85).cg)
    ctx.setLineWidth(r * 0.12)
    ctx.strokePath()
    fill(ctx, disc(p, r * 0.3), RGB(0xF89A44))
    glint(ctx, pt(p, deg(-130), r * 0.45), w: r * 0.6, h: r * 0.16, angle: deg(-35), alpha: 0.7)
}

/// Glazed pearl onion: translucent layers, bright highlight.
func aPearlOnion(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat) {
    let path = blobPath(p, r, jitter: 0.03, points: 9, seed: UInt64(p.x), stretch: 1.08, angle: p.y)
    withShadow(ctx, dy: r * 0.2, blur: r * 0.35, RGB(0x1A0400, alpha: 0.6)) { fill(ctx, path, RGB(0xD8BCA8)) }
    shade(ctx, path, [RGB(0xFFFBF4), RGB(0xEAD6C2), RGB(0xB08068), RGB(0x8A4A30)], locations: [0, 0.4, 0.8, 1])
    clipped(ctx, path) {
        // Layers showing through the glaze.
        ctx.setStrokeColor(RGB(0xFFFFFF, alpha: 0.3).cg)
        ctx.setLineWidth(1.6)
        for k in 1...3 { ctx.strokeEllipse(in: circle(CGPoint(x: p.x + r * 0.08, y: p.y + r * 0.08), r * CGFloat(k) * 0.26)) }
        let b = CGPoint(x: p.x + r * 0.55, y: p.y + r * 0.55)
        ctx.drawRadialGradient(gradient([RGB(0x9A4A20, alpha: 0.5), RGB(0x9A4A20, alpha: 0)]), startCenter: b, startRadius: 0,
                               endCenter: b, endRadius: r * 0.9, options: [])
    }
    glint(ctx, CGPoint(x: p.x - r * 0.32, y: p.y - r * 0.38), w: r * 0.6, h: r * 0.3, angle: deg(-35), alpha: 0.95)
    glint(ctx, CGPoint(x: p.x + r * 0.4, y: p.y + r * 0.35), w: r * 0.3, h: r * 0.1, angle: deg(-35), alpha: 0.4)
}

func aMushroom(_ ctx: CGContext, _ p: CGPoint, _ s: CGFloat, angle: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -s, y: 0))
    path.addCurve(to: CGPoint(x: s, y: 0), control1: CGPoint(x: -s * 0.95, y: -s * 1.15), control2: CGPoint(x: s * 0.95, y: -s * 1.15))
    path.addCurve(to: CGPoint(x: s * 0.36, y: s * 0.12), control1: CGPoint(x: s * 0.8, y: s * 0.16), control2: CGPoint(x: s * 0.5, y: s * 0.1))
    path.addCurve(to: CGPoint(x: s * 0.3, y: s * 0.8), control1: CGPoint(x: s * 0.32, y: s * 0.4), control2: CGPoint(x: s * 0.4, y: s * 0.65))
    path.addQuadCurve(to: CGPoint(x: -s * 0.3, y: s * 0.8), control: CGPoint(x: 0, y: s * 0.9))
    path.addCurve(to: CGPoint(x: -s * 0.36, y: s * 0.12), control1: CGPoint(x: -s * 0.4, y: s * 0.65), control2: CGPoint(x: -s * 0.32, y: s * 0.4))
    path.addCurve(to: CGPoint(x: -s, y: 0), control1: CGPoint(x: -s * 0.5, y: s * 0.1), control2: CGPoint(x: -s * 0.8, y: s * 0.16))
    path.closeSubpath()
    var t = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: angle)
    let shape = path.copy(using: &t)!
    withShadow(ctx, dy: s * 0.12, blur: s * 0.3, RGB(0x1A0400, alpha: 0.55)) { fill(ctx, shape, RGB(0x8A5A34)) }
    fill(ctx, shape, RGB(0x7A4A28))
    // Cut face, a hair inside the brown skin, browned at the edge.
    var inset = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: angle).scaledBy(x: 0.86, y: 0.86)
    let face = path.copy(using: &inset)!
    shade(ctx, face, [RGB(0xF2E0C4), RGB(0xDCBE96), RGB(0xA87A4E)], locations: [0, 0.6, 1])
    // Gills line under the cap.
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: angle)
    ctx.setStrokeColor(RGB(0x6A4024, alpha: 0.6).cg)
    ctx.setLineWidth(s * 0.06)
    ctx.move(to: CGPoint(x: -s * 0.72, y: -s * 0.06))
    ctx.addQuadCurve(to: CGPoint(x: s * 0.72, y: -s * 0.06), control: CGPoint(x: 0, y: s * 0.05))
    ctx.strokePath()
    ctx.restoreGState()
}

func aThyme(_ ctx: CGContext, _ start: CGPoint, length: CGFloat, angle: CGFloat, bend: CGFloat, seed: UInt64) {
    let end = pt(start, angle, length)
    let ctrl = pt(pt(start, angle, length / 2), angle + .pi / 2, bend)
    withShadow(ctx, dy: 3, blur: 5, RGB(0x000000, alpha: 0.45)) {
        ctx.setStrokeColor(RGB(0x6A5232).cg)
        ctx.setLineWidth(3.5)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addQuadCurve(to: end, control: ctrl)
        ctx.strokePath()
        var rng = SeededRandom(seed)
        for k in 1..<12 {
            let t = CGFloat(k) / 12
            let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, cc = t * t
            let q = CGPoint(x: a * start.x + b * ctrl.x + cc * end.x, y: a * start.y + b * ctrl.y + cc * end.y)
            for s: CGFloat in [-1, 1] {
                let leaf = leafPath(pt(q, angle + s * deg(55), 9), length: 18 - t * 5, width: 6, angle: angle + s * deg(55) + rng.range(-0.2, 0.2))
                shade(ctx, leaf, [RGB(0xA6C482), RGB(0x6E8E4C), RGB(0x46612E)])
            }
        }
    }
}

func drawEnamelCocotte(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0x2E5560), outer: RGB(0x10262D), dark: (RGB(0x183139), RGB(0x050D10)), light: CGPoint(x: 0.32, y: 0.28))
    aMottle(ctx, seed: 37, scale: 0.005, strength: 0.05)
    let c = CGPoint(x: 512, y: 522)
    let R: CGFloat = 352

    // Loop handles, east and west, enamelled like the body.
    for side: CGFloat in [0, .pi] {
        let hc = pt(c, side, R + 40)
        let loop = CGMutablePath()
        loop.addPath(roundedRect(hc, w: 150, h: 196, r: 64, angle: side))
        loop.addPath(roundedRect(pt(hc, side, 18), w: 52, h: 120, r: 26, angle: side))
        withShadow(ctx, dy: 22, blur: 30, RGB(0x000000, alpha: 0.55)) {
            ctx.addPath(loop); ctx.setFillColor(RGB(0xC8501A).cg); ctx.fillPath(using: .evenOdd)
        }
        clippedEO(ctx, loop) {
            let lc = pt(hc, side, 30)
            ctx.drawRadialGradient(gradient([RGB(0xFFC070), RGB(0xF27A22), RGB(0xB83A10), RGB(0x6A1A06)], [0, 0.35, 0.75, 1]),
                                   startCenter: CGPoint(x: lc.x - 30, y: lc.y - 45), startRadius: 0, endCenter: lc, endRadius: 130,
                                   options: [.drawsAfterEndLocation])
        }
        glint(ctx, pt(pt(hc, side, 35), side + .pi / 2, -60), w: 80, h: 18, angle: side + .pi / 2, alpha: 0.7)
    }

    withShadow(ctx, dy: R * 0.08, blur: R * 0.2, RGB(0x000000, alpha: 0.6)) { fill(ctx, ellipsePath(c, R), RGB(0xB8400E)) }
    drawTexture(ctx, aVesselImage(c, R, profile: aCocotteProfile, material: aEnamel))

    // Bourguignon: a thick, glossy, wine-dark braise heaped with large pieces.
    let rs = R * 0.72
    let sauce = ellipsePath(c, rs)
    fill(ctx, sauce, RGB(0x4A140C))
    clipped(ctx, sauce) {
        ctx.drawRadialGradient(gradient([RGB(0x7E2814), RGB(0x58180C), RGB(0x2A0805)], [0, 0.6, 1]),
                               startCenter: CGPoint(x: c.x - 60, y: c.y - 70), startRadius: 0, endCenter: c, endRadius: rs,
                               options: [.drawsAfterEndLocation])
        // The rim's shadow on the far side of the sauce.
        ctx.setShadow(offset: CGSize(width: 8, height: -14), blur: 22, color: RGB(0x000000, alpha: 0.6).cg)
        ctx.addPath(sauce)
        ctx.setLineWidth(30)
        ctx.setStrokeColor(RGB(0x2A0805).cg)
        ctx.strokePath()
    }
    // Sauce clinging to the enamel.
    ctx.setStrokeColor(RGB(0x6A2414, alpha: 0.5).cg)
    ctx.setLineWidth(5)
    ctx.strokeEllipse(in: circle(c, rs + 3))
    // Gloss streaks: the window reflected in the sauce's curved surface.
    clipped(ctx, sauce) {
        ctx.setLineCap(.round)
        for (rr, a0, a1, w, al) in [(0.9, -168.0, -112.0, 12.0, 0.32), (0.8, -158.0, -128.0, 7.0, 0.25), (0.93, 20.0, 60.0, 6.0, 0.14)]
            as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
            ctx.setStrokeColor(RGB(0xFFE8DC, alpha: al).cg)
            ctx.setLineWidth(w)
            ctx.addArc(center: c, radius: rs * rr, startAngle: deg(a0), endAngle: deg(a1), clockwise: false)
            ctx.strokePath()
        }
    }

    // Heaped: outer pieces first, the middle ones on top.
    aBeef(ctx, CGPoint(x: c.x - 130, y: c.y - 70), 70, seed: 11, stretch: 1.3)
    aBeef(ctx, CGPoint(x: c.x + 120, y: c.y - 110), 64, seed: 12, stretch: 1.15)
    aBeef(ctx, CGPoint(x: c.x + 130, y: c.y + 100), 72, seed: 13, stretch: 1.35)
    aBeef(ctx, CGPoint(x: c.x - 110, y: c.y + 130), 66, seed: 14, stretch: 1.2)
    aMushroom(ctx, CGPoint(x: c.x - 10, y: c.y - 175), 50, angle: deg(-15))
    aMushroom(ctx, CGPoint(x: c.x + 190, y: c.y - 5), 46, angle: deg(80))
    aCarrot(ctx, CGPoint(x: c.x - 190, y: c.y + 30), 38, angle: deg(70))
    aCarrot(ctx, CGPoint(x: c.x + 40, y: c.y + 185), 36, angle: deg(-20))
    aCarrot(ctx, CGPoint(x: c.x + 60, y: c.y - 160), 36, angle: deg(30))
    aBeef(ctx, CGPoint(x: c.x + 10, y: c.y + 10), 82, seed: 15, stretch: 1.2)
    aCarrot(ctx, CGPoint(x: c.x - 40, y: c.y - 95), 40, angle: deg(-40))
    aCarrot(ctx, CGPoint(x: c.x + 95, y: c.y + 15), 38, angle: deg(10))
    aPearlOnion(ctx, CGPoint(x: c.x - 75, y: c.y + 60), 30)
    aPearlOnion(ctx, CGPoint(x: c.x + 60, y: c.y - 60), 28)
    aPearlOnion(ctx, CGPoint(x: c.x - 180, y: c.y - 140), 26)
    aPearlOnion(ctx, CGPoint(x: c.x + 20, y: c.y + 120), 27)
    aMushroom(ctx, CGPoint(x: c.x - 40, y: c.y + 195), 44, angle: deg(170))
    aThyme(ctx, CGPoint(x: c.x - 120, y: c.y - 160), length: 200, angle: deg(30), bend: -24, seed: 141)
    aThyme(ctx, CGPoint(x: c.x + 60, y: c.y + 80), length: 150, angle: deg(-40), bend: 20, seed: 143)
    drawFlecks(ctx, center: c, radius: rs * 0.8, count: 18, size: 5, colors: [RGB(0x4E8A3A), RGB(0x6EA850), RGB(0x3A6E2A)], seed: 147)
}



// MARK: - Shared bits (Candlelight, Sunday Brunch)

/// A blurred shape without a hard edge: the path is drawn off canvas and only its shadow lands.
func bSoftFill(_ ctx: CGContext, _ path: CGPath, _ color: RGB, blur: CGFloat) {
    let away: CGFloat = 4000
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -away, height: 0), blur: blur, color: color.cg)
    ctx.translateBy(x: away, y: 0)
    ctx.addPath(path)
    ctx.setFillColor(RGB(0x000000).cg)
    ctx.fillPath()
    ctx.restoreGState()
}

/// Fine porcelain plate seen from above: bright rim with a gilded band, a shallow well.
/// Returns the radius of the well.
@discardableResult
func bPorcelainPlate(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, body: RGB, bodyShade: RGB, shadow: RGB, gold: Bool) -> CGFloat {
    withShadow(ctx, dy: r * 0.05, blur: r * 0.14, shadow) { fill(ctx, ellipsePath(c, r), body) }
    shade(ctx, ellipsePath(c, r), [body, body, bodyShade], light: CGPoint(x: -0.35, y: -0.45), locations: [0, 0.5, 1])
    let well = r * 0.74
    if gold {
        bGoldRing(ctx, c, outer: r * 0.975, inner: r * 0.945)
        bGoldRing(ctx, c, outer: well + r * 0.012, inner: well + r * 0.002)
    }
    // The well dips a little: the far (top) slope in shade, a lip line under the light.
    clipped(ctx, ellipsePath(c, well)) {
        ctx.drawLinearGradient(gradient([bodyShade.mixed(with: body, 0.3), body, body]), start: CGPoint(x: c.x, y: c.y - well),
                               end: CGPoint(x: c.x, y: c.y + well * 0.2), options: [])
        ctx.setShadow(offset: CGSize(width: 0, height: -well * 0.02), blur: well * 0.05, color: RGB(0x000000, alpha: 0.12).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(well * 0.06)
        ctx.strokeEllipse(in: circle(c, well + well * 0.03))
    }
    return well
}

/// Polished gold band: a conic sweep gives the turned-metal glints.
func bGoldRing(_ ctx: CGContext, _ c: CGPoint, outer: CGFloat, inner: CGFloat) {
    clippedEO(ctx, ringPath(c, outer: outer, inner: inner)) {
        let deep = RGB(0x8A6424), mid = RGB(0xC69A48), bright = RGB(0xF2D58E), hi = RGB(0xFFF4D2)
        drawConic(ctx, [hi, bright, mid, deep, mid, bright, hi, bright, mid, deep, mid, bright, hi],
                  [0, 0.05, 0.14, 0.25, 0.36, 0.45, 0.5, 0.55, 0.64, 0.75, 0.86, 0.95, 1],
                  center: c, radius: outer, angle: deg(-135))
    }
}

func bMintLeaf(_ ctx: CGContext, _ c: CGPoint, length: CGFloat, angle: CGFloat) {
    let path = leafPath(c, length: length, width: length * 0.4, angle: angle)
    withShadow(ctx, dy: length * 0.05, blur: length * 0.12, RGB(0x0A2A10, alpha: 0.35)) { fill(ctx, path, RGB(0x3E8A40)) }
    shade(ctx, path, [RGB(0x9AD47E), RGB(0x55A04A), RGB(0x2E6E30)], light: CGPoint(x: -0.2, y: -0.3))
    // Mint is crinkled: veins pressed in.
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.setStrokeColor(RGB(0x245A26, alpha: 0.6).cg)
    ctx.setLineCap(.round)
    ctx.setLineWidth(max(1.2, length * 0.022))
    ctx.move(to: CGPoint(x: -length * 0.48, y: 0))
    ctx.addLine(to: CGPoint(x: length * 0.42, y: 0))
    ctx.strokePath()
    ctx.setLineWidth(max(1, length * 0.014))
    for i in 0..<4 {
        let x = -length * 0.3 + CGFloat(i) * length * 0.17
        for s: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addQuadCurve(to: CGPoint(x: x + length * 0.13, y: s * length * 0.14), control: CGPoint(x: x + length * 0.03, y: s * length * 0.1))
        }
    }
    ctx.strokePath()
    ctx.restoreGState()
}

/// Glossy fruit-glaze glint.
func bGloss(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, alpha: CGFloat = 0.75) {
    glint(ctx, CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), w: r * 0.55, h: r * 0.3, angle: deg(-35), alpha: alpha)
}

func bRaspberry(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, seed: UInt64) {
    withShadow(ctx, dy: r * 0.15, blur: r * 0.35, RGB(0x4A0010, alpha: 0.4)) { fill(ctx, ellipsePath(c, r), RGB(0xA8162E)) }
    shade(ctx, ellipsePath(c, r), [RGB(0xD8324E), RGB(0xB21C36), RGB(0x7A0A1E)])
    // Drupelets in rings around the hollow top.
    var rng = SeededRandom(seed)
    for ring in 0..<3 {
        let d = r * (0.32 + CGFloat(ring) * 0.26)
        let n = 6 + ring * 5
        let off = rng.next()
        for k in 0..<n {
            let a = (CGFloat(k) + off) / CGFloat(n) * .pi * 2
            let p = pt(c, a, d)
            let dr = r * (0.2 - CGFloat(ring) * 0.025)
            shade(ctx, ellipsePath(p, dr), [RGB(0xF2667A), RGB(0xC52440), RGB(0x8A1028)], light: CGPoint(x: -0.4, y: -0.45))
            ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.55).cg)
            ctx.fillEllipse(in: circle(CGPoint(x: p.x - dr * 0.35, y: p.y - dr * 0.35), dr * 0.22))
        }
    }
    // The hollow where the stem was.
    shade(ctx, ellipsePath(c, r * 0.17), [RGB(0x5A0614), RGB(0x8A1228)], light: CGPoint(x: 0.3, y: 0.3))
}

func bBlueberry(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, angle: CGFloat) {
    withShadow(ctx, dy: r * 0.15, blur: r * 0.35, RGB(0x0A0A30, alpha: 0.4)) { fill(ctx, ellipsePath(c, r), RGB(0x2E3A66)) }
    shade(ctx, ellipsePath(c, r), [RGB(0x8C9AC4), RGB(0x46558A), RGB(0x1E264A)], locations: [0, 0.45, 1])
    // Crown: a small five-point star.
    let star = CGMutablePath()
    for k in 0..<10 {
        let p = pt(c, angle + CGFloat(k) * .pi / 5, k % 2 == 0 ? r * 0.3 : r * 0.12)
        if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
    }
    star.closeSubpath()
    fill(ctx, star, RGB(0x1A1E36))
    bGloss(ctx, c, r, alpha: 0.5)
}

/// Halved strawberry, cut side up, tip pointing along `angle`.
func bStrawberryHalf(_ ctx: CGContext, _ c: CGPoint, _ len: CGFloat, angle: CGFloat) {
    let shape = CGMutablePath()
    let h = len / 2, w = len * 0.42
    shape.move(to: CGPoint(x: h, y: 0))
    shape.addCurve(to: CGPoint(x: -h * 0.92, y: -w * 0.35), control1: CGPoint(x: h * 0.3, y: -w * 1.05), control2: CGPoint(x: -h * 0.7, y: -w * 1.15))
    shape.addQuadCurve(to: CGPoint(x: -h * 0.92, y: w * 0.35), control: CGPoint(x: -h * 1.1, y: 0))
    shape.addCurve(to: CGPoint(x: h, y: 0), control1: CGPoint(x: -h * 0.7, y: w * 1.15), control2: CGPoint(x: h * 0.3, y: w * 1.05))
    shape.closeSubpath()
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    let outer = shape.copy(using: &t)!
    var ti = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).scaledBy(x: 0.84, y: 0.78)
    let inner = shape.copy(using: &ti)!
    withShadow(ctx, dy: len * 0.06, blur: len * 0.14, RGB(0x4A0008, alpha: 0.4)) { fill(ctx, outer, RGB(0xC4182A)) }
    shade(ctx, outer, [RGB(0xF0465A), RGB(0xD01E30), RGB(0x980C1C)])
    // Pale flesh with a red blush towards the skin and a white core.
    shade(ctx, inner, [RGB(0xFFD9D6), RGB(0xF68C8A), RGB(0xE24A52)], light: CGPoint(x: 0, y: 0), locations: [0, 0.5, 1])
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.setStrokeColor(RGB(0xFFF1EC, alpha: 0.85).cg)
    ctx.setLineCap(.round)
    ctx.setLineWidth(len * 0.06)
    ctx.move(to: CGPoint(x: -h * 0.65, y: 0))
    ctx.addQuadCurve(to: CGPoint(x: h * 0.55, y: 0), control: CGPoint(x: 0, y: len * 0.02))
    ctx.strokePath()
    ctx.restoreGState()
    clipped(ctx, outer) {
        // Apricot glaze shine.
        glint(ctx, pt(c, angle + deg(-150), len * 0.18), w: len * 0.45, h: len * 0.18, angle: angle, alpha: 0.75)
        glint(ctx, pt(c, angle + deg(-120), len * 0.22), w: len * 0.14, h: len * 0.07, angle: angle, alpha: 0.95)
    }
}

/// Halved fig, cut side up.
func bFigHalf(_ ctx: CGContext, _ c: CGPoint, _ len: CGFloat, angle: CGFloat, seed: UInt64) {
    let shape = CGMutablePath()
    let h = len / 2, w = len * 0.46
    shape.move(to: CGPoint(x: h, y: 0))
    shape.addCurve(to: CGPoint(x: -h, y: 0), control1: CGPoint(x: h * 0.55, y: -w * 0.5), control2: CGPoint(x: -h, y: -w * 1.35))
    shape.addCurve(to: CGPoint(x: h, y: 0), control1: CGPoint(x: -h, y: w * 1.35), control2: CGPoint(x: h * 0.55, y: w * 0.5))
    shape.closeSubpath()
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    let outer = shape.copy(using: &t)!
    var t2 = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).translatedBy(x: -len * 0.03, y: 0).scaledBy(x: 0.86, y: 0.84)
    let cream = shape.copy(using: &t2)!
    var t3 = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).translatedBy(x: -len * 0.08, y: 0).scaledBy(x: 0.62, y: 0.6)
    let flesh = shape.copy(using: &t3)!
    withShadow(ctx, dy: len * 0.06, blur: len * 0.14, RGB(0x200010, alpha: 0.45)) { fill(ctx, outer, RGB(0x4A1A3A)) }
    shade(ctx, outer, [RGB(0x8A4A7A), RGB(0x5A2048), RGB(0x2E0C24)])
    shade(ctx, cream, [RGB(0xFFF2DA), RGB(0xF2D9B2), RGB(0xD9A890)], light: CGPoint(x: 0, y: 0))
    shade(ctx, flesh, [RGB(0xF05A6A), RGB(0xC22A44), RGB(0x8A1030)], light: CGPoint(x: 0.1, y: 0), locations: [0, 0.6, 1])
    // Seeds: tiny pale strands radiating from the centre.
    var rng = SeededRandom(seed)
    let fc = pt(c, angle, -len * 0.08)
    clipped(ctx, flesh) {
        for _ in 0..<38 {
            let a = rng.next() * .pi * 2
            let d = rng.range(0.15, 1) * len * 0.26
            fill(ctx, leafPath(pt(fc, a, d), length: len * 0.06, width: len * 0.018, angle: a), RGB(0xFFD6A0, alpha: 0.85))
        }
    }
    clipped(ctx, outer) {
        glint(ctx, pt(c, angle + deg(-140), len * 0.2), w: len * 0.4, h: len * 0.16, angle: angle, alpha: 0.5)
    }
}

// MARK: - Candlelight

/// Woven table linen: fine warp and weft threads with slubs.
func bLinenTexture(base: RGB, light: RGB) -> CGImage {
    let slub = Noise(seed: 61), tone = Noise(seed: 67)
    let b = (Float(base.r), Float(base.g), Float(base.b)), l = (Float(light.r), Float(light.g), Float(light.b))
    return textureImage { x, y in
        let warpT = 0.5 + 0.5 * sin(x * 0.9 + slub.value(x * 0.02, y * 0.4) * 3)
        let weftT = 0.5 + 0.5 * sin(y * 0.9 + slub.value(x * 0.4, y * 0.02) * 3)
        let thread = (warpT * 0.5 + weftT * 0.5)
        let t = thread * 0.35 + tone.fbm(x * 0.004, y * 0.004, octaves: 3) * 0.25
        return (b.0 + (l.0 - b.0) * t, b.1 + (l.1 - b.1) * t, b.2 + (l.2 - b.2) * t, 1)
    }
}

/// One slice of steak, cut face up: a dark seared crust round the edge, a thin grey-brown band, a rosé centre.
func bSteakSlice(_ ctx: CGContext, _ c: CGPoint, length: CGFloat, thickness: CGFloat, angle: CGFloat, seed: UInt64) {
    let crust = blobPath(.zero, length / 2, jitter: 0.03, points: 12, seed: seed, stretch: 1, angle: 0)
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).scaledBy(x: 1, y: thickness / length)
    let outer = crust.copy(using: &t)!
    var tBand = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).scaledBy(x: 0.91, y: thickness / length * 0.66)
    let band = crust.copy(using: &tBand)!
    var tPink = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).scaledBy(x: 0.84, y: thickness / length * 0.5)
    let pink = crust.copy(using: &tPink)!
    withShadow(ctx, dy: 8, blur: 14, RGB(0x1A0602, alpha: 0.55)) { fill(ctx, outer, RGB(0x3A1608)) }
    shade(ctx, outer, [RGB(0x7A3A18), RGB(0x4A1E0A), RGB(0x240C04)], light: CGPoint(x: -0.3, y: -0.5))
    fill(ctx, band, RGB(0x8A5444))
    shade(ctx, pink, [RGB(0xF8A0A4), RGB(0xE8737C), RGB(0xC44E5C)], light: CGPoint(x: 0, y: 0), locations: [0, 0.55, 1])
    // Resting juices make the cut face shine.
    clipped(ctx, pink) {
        glint(ctx, pt(c, angle + deg(-160), length * 0.2), w: length * 0.42, h: thickness * 0.22, angle: angle, alpha: 0.45)
    }
}

func bRosemary(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, seed: UInt64) {
    let mid = CGPoint(x: (a.x + b.x) / 2 + 10, y: (a.y + b.y) / 2 - 8)
    ctx.setStrokeColor(RGB(0x5A4A2A).cg)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.move(to: a)
    ctx.addQuadCurve(to: b, control: mid)
    ctx.strokePath()
    var rng = SeededRandom(seed)
    let ang = atan2(b.y - a.y, b.x - a.x)
    for k in 0..<22 {
        let t = 0.04 + CGFloat(k) / 22 * 0.94
        let p = CGPoint(x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * mid.x + t * t * b.x,
                        y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * mid.y + t * t * b.y)
        let side: CGFloat = k % 2 == 0 ? 1 : -1
        let la = ang + side * deg(rng.range(35, 55))
        let len = rng.range(40, 52) * (1 - t * 0.35)
        let needle = leafPath(pt(p, la, len / 2), length: len, width: 5, angle: la)
        withShadow(ctx, dy: 3, blur: 5, RGB(0x000000, alpha: 0.35)) { fill(ctx, needle, RGB(0x2E5A36)) }
        shade(ctx, needle, [RGB(0x6E9A6A), RGB(0x3E6E44), RGB(0x24482A)])
    }
}

/// Blistered cherry tomatoes still on the vine.
func bVineTomatoes(_ ctx: CGContext, _ points: [CGPoint], r: CGFloat) {
    let vine = CGMutablePath()
    let tops = points.map { pt($0, deg(-110), r * 0.9) }
    vine.move(to: CGPoint(x: tops[0].x - r * 0.4, y: tops[0].y - r * 0.6))
    for (i, p) in tops.enumerated() where i > 0 {
        let prev = tops[i - 1]
        vine.addQuadCurve(to: p, control: CGPoint(x: (prev.x + p.x) / 2, y: min(prev.y, p.y) - r * 0.7))
    }
    for (i, c) in points.enumerated() {
        withShadow(ctx, dy: r * 0.15, blur: r * 0.35, RGB(0x1A0000, alpha: 0.55)) { fill(ctx, ellipsePath(c, r), RGB(0xB8200E)) }
        shade(ctx, ellipsePath(c, r), [RGB(0xFF6A40), RGB(0xD8301A), RGB(0x7A0E06)], locations: [0, 0.5, 1])
        // Blisters: split, slightly charred skin.
        var rng = SeededRandom(UInt64(i + 50))
        clipped(ctx, ellipsePath(c, r)) {
            for _ in 0..<3 {
                let p = pt(c, rng.next() * .pi * 2, rng.range(0.3, 0.8) * r)
                bSoftFill(ctx, blobPath(p, r * rng.range(0.14, 0.24), jitter: 0.3, points: 7, seed: UInt64(p.x), stretch: 1.4, angle: rng.next() * 3),
                          RGB(0x3A0A02, alpha: 0.55), blur: 4)
            }
        }
        glint(ctx, CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), w: r * 0.6, h: r * 0.3, angle: deg(-35), alpha: 0.85)
    }
    ctx.addPath(vine)
    ctx.setStrokeColor(RGB(0x4E6A2A).cg)
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.strokePath()
    for t in tops {
        let calyx = CGMutablePath()
        for k in 0..<5 { calyx.addPath(leafPath(pt(t, CGFloat(k) * .pi * 0.4, r * 0.28), length: r * 0.56, width: r * 0.12, angle: CGFloat(k) * .pi * 0.4)) }
        fill(ctx, calyx, RGB(0x5A7A30))
    }
}

func drawCandlelight(_ ctx: CGContext) {
    let dark = appearance == .dark
    let candle = CGPoint(x: 168, y: 170)
    if appearance != .tinted {
        drawTexture(ctx, bLinenTexture(base: dark ? RGB(0x24080E) : RGB(0x3A0E18), light: dark ? RGB(0x3A121A) : RGB(0x5A1C28)))
    }
    // Ivory porcelain with a thin gold line: it catches the warm light on the candle side.
    let c = CGPoint(x: 522, y: 524)
    let r: CGFloat = 372
    let ivory = appearance == .tinted ? RGB(0x8A8680) : RGB(0xF6EEDC)
    let ivoryShade = appearance == .tinted ? RGB(0x5A5652) : RGB(0xD8CBB0)
    bPorcelainPlate(ctx, c, r, body: ivory, bodyShade: ivoryShade, shadow: RGB(0x000000, alpha: 0.6), gold: false)
    bGoldRing(ctx, c, outer: r * 0.965, inner: r * 0.952)

    // Jus: a glossy pool under the slices.
    let jus = blobPath(CGPoint(x: c.x + 6, y: c.y + 8), 178, jitter: 0.1, points: 13, seed: 5, stretch: 1.14, angle: deg(-42))
    fill(ctx, jus, RGB(0x2A0804))
    shade(ctx, jus, [RGB(0x6A2410), RGB(0x3A1006), RGB(0x1E0602)], light: CGPoint(x: -0.45, y: -0.45))
    clipped(ctx, jus) {
        ctx.setStrokeColor(RGB(0xFFD8A0, alpha: 0.45).cg)
        ctx.setLineWidth(5)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: c.x + 6, y: c.y + 8), radius: 160, startAngle: deg(-175), endAngle: deg(-115), clockwise: false)
        ctx.strokePath()
    }

    // Sliced steak fanned out like dominoes, each slice overlapping the one before.
    let dir = deg(-42)
    for i in 0..<7 {
        let o = CGFloat(i) - 3
        let p = pt(pt(c, dir, o * 52), dir + .pi / 2, o * o * 3 - 14)
        bSteakSlice(ctx, p, length: 236 - abs(o) * 14, thickness: 92, angle: dir + .pi / 2 + deg(o * 4), seed: UInt64(i + 3))
    }
    // Flaky salt on the slices.
    var salt = SeededRandom(12)
    for _ in 0..<22 {
        let p = pt(pt(c, dir, salt.range(-150, 150)), dir + .pi / 2, salt.range(-80, 80))
        fill(ctx, roundedRect(p, w: salt.range(6, 10), h: salt.range(5, 8), r: 1.5, angle: salt.next() * 3), RGB(0xFFF8F0, alpha: 0.9))
    }
    bRosemary(ctx, from: CGPoint(x: c.x - 250, y: c.y + 40), to: CGPoint(x: c.x - 120, y: c.y + 230), seed: 3)
    bVineTomatoes(ctx, [CGPoint(x: c.x + 150, y: c.y + 205), CGPoint(x: c.x + 215, y: c.y + 140), CGPoint(x: c.x + 248, y: c.y + 60)], r: 40)

    // A glass of red wine, lower right, from above: rim ring, garnet wine, the flame mirrored in it.
    let gc = CGPoint(x: 862, y: 866)
    let gr: CGFloat = 108
    withShadow(ctx, dy: 8, blur: 26, RGB(0x000000, alpha: 0.5)) { fill(ctx, ellipsePath(gc, gr), RGB(0x2A0610, alpha: 0.35)) }
    shade(ctx, ellipsePath(gc, gr * 0.8), [RGB(0x9A1C30), RGB(0x5A0818), RGB(0x24020A)], light: CGPoint(x: -0.5, y: -0.5))
    ctx.setStrokeColor(RGB(0xFFFFFF, alpha: 0.12).cg)
    ctx.setLineWidth(gr * 0.18)
    ctx.strokeEllipse(in: circle(gc, gr * 0.9))
    ctx.setStrokeColor(RGB(0xFFFFFF, alpha: 0.4).cg)
    ctx.setLineWidth(3)
    ctx.strokeEllipse(in: circle(gc, gr))
    glint(ctx, pt(gc, deg(-135), gr * 0.42), w: 34, h: 18, angle: deg(45), alpha: 0.95)
    ctx.setStrokeColor(RGB(0xFFE0B0, alpha: 0.85).cg)
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.addArc(center: gc, radius: gr - 2, startAngle: deg(-165), endAngle: deg(-105), clockwise: false)
    ctx.strokePath()

    // Candlelight: warm near the flame, falling off into deep shadow on the far side.
    if appearance != .tinted {
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        ctx.drawRadialGradient(gradient([RGB(0xFFFFFF), RGB(0xF0D8C0), RGB(0xA88078), RGB(dark ? 0x3A2A2E : 0x4A3438)], [0, 0.3, 0.62, 1]),
                               startCenter: candle, startRadius: 60, endCenter: candle, endRadius: 1200, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        glow(ctx, candle, 640, RGB(0xFF9A40), dark ? 0.22 : 0.3)
        ctx.restoreGState()
    }

    // The candle from above: a cream pillar, a pool of melted wax, the wick and flame.
    let cr: CGFloat = 92
    withShadow(ctx, dy: 10, blur: 24, RGB(0x000000, alpha: 0.5)) { fill(ctx, ellipsePath(candle, cr), RGB(0xF2E6D0)) }
    shade(ctx, ellipsePath(candle, cr), [RGB(0xFFF8EA), RGB(0xF4E4C6), RGB(0xD8BE96)], light: CGPoint(x: 0.25, y: 0.25))
    let poolR = cr * 0.72
    shade(ctx, ellipsePath(candle, poolR), [RGB(0xFFF6D8), RGB(0xFBE3B0), RGB(0xE8C890)], light: CGPoint(x: 0, y: 0))
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    glow(ctx, candle, 300, RGB(0xFFC070), 0.75)
    glow(ctx, candle, 90, RGB(0xFFF0C0), 0.9)
    ctx.restoreGState()
    fill(ctx, ellipsePath(candle, 6), RGB(0x2A1A10))
    // Flame from above: a bright teardrop leaning away from the wick.
    let flame = leafPath(CGPoint(x: candle.x + 10, y: candle.y + 12), length: 46, width: 15, angle: deg(48))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: RGB(0xFFC060, alpha: 1).cg)
    fill(ctx, flame, RGB(0xFFF4D0))
    ctx.restoreGState()
    shade(ctx, flame, [RGB(0xFFFFFF), RGB(0xFFE8A0), RGB(0xFFA040)], light: CGPoint(x: -0.2, y: -0.2))
}

// MARK: - Sunday Brunch

/// Window light: the whole scene in soft shade except the sunlit panes, crossed by the window bars and
/// the shadow of a plant's leaves. Drawn over everything, so the light falls across the plate too.
func bWindowLight(_ ctx: CGContext, shadow: RGB) {
    ctx.saveGState()
    ctx.setBlendMode(.multiply)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(shadow.cg)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // Cut out the panes, soft edged.
    ctx.setBlendMode(.destinationOut)
    let angle = deg(-28)
    let pane = CGSize(width: 520, height: 400), bar: CGFloat = 34
    let origin = CGPoint(x: 470, y: 470)
    for i in 0..<2 {
        for j in 0..<2 {
            let cx = (CGFloat(i) - 0.5) * (pane.width + bar), cy = (CGFloat(j) - 0.5) * (pane.height + bar)
            let p = CGPoint(x: origin.x + cx * cos(angle) - cy * sin(angle), y: origin.y + cx * sin(angle) + cy * cos(angle))
            bSoftFill(ctx, roundedRect(p, w: pane.width, h: pane.height, r: 6, angle: angle), RGB(0x000000), blur: 22)
        }
    }
    // The shadow of an olive branch in the window, upper right.
    ctx.setBlendMode(.normal)
    let stem0 = CGPoint(x: 1090, y: -30), stem1 = CGPoint(x: 760, y: 250)
    let stemAngle = atan2(stem1.y - stem0.y, stem1.x - stem0.x)
    let stem = CGMutablePath()
    stem.move(to: stem0)
    stem.addQuadCurve(to: stem1, control: CGPoint(x: 900, y: 60))
    bSoftFill(ctx, stem.copy(strokingWithWidth: 7, lineCap: .round, lineJoin: .round, miterLimit: 1), shadow, blur: 8)
    for k in 0..<9 {
        let t = 0.12 + CGFloat(k) * 0.1
        let p = CGPoint(x: (1 - t) * (1 - t) * stem0.x + 2 * (1 - t) * t * 900 + t * t * stem1.x,
                        y: (1 - t) * (1 - t) * stem0.y + 2 * (1 - t) * t * 60 + t * t * stem1.y)
        let side: CGFloat = k % 2 == 0 ? 1 : -1
        let a = stemAngle + side * deg(38)
        bSoftFill(ctx, leafPath(pt(p, a, 62), length: 128, width: 26, angle: a), shadow, blur: 10)
    }
    bSoftFill(ctx, leafPath(pt(stem1, stemAngle, 55), length: 120, width: 24, angle: stemAngle), shadow, blur: 10)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func bPancake(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, seed: UInt64, top: Bool) {
    let path = blobPath(c, r, jitter: 0.025, points: 16, seed: seed, stretch: 1.02)
    withShadow(ctx, dy: 8, blur: 16, RGB(0x6A3A08, alpha: 0.35)) { fill(ctx, path, RGB(0xE9C080)) }
    // Edge pale, centre browned.
    shade(ctx, path, [RGB(0xB8732E), RGB(0xC98A40), RGB(0xE6B26A), RGB(0xF4D49A)], light: CGPoint(x: 0, y: 0), locations: [0, 0.4, 0.72, 0.8])
    guard top else { return }
    // Little bubbles that set while it cooked.
    var rng = SeededRandom(seed + 9)
    clipped(ctx, path) {
        for _ in 0..<70 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * r * 0.7)
            ctx.setFillColor(RGB(0x8A4A14, alpha: 0.35).cg)
            ctx.fillEllipse(in: circle(p, rng.range(1.5, 4)))
        }
    }
}

func drawSundayBrunch(_ ctx: CGContext) {
    let dark = appearance == .dark
    drawGround(ctx, inner: RGB(0xFFF2D6), outer: RGB(0xF2D9A8), dark: (RGB(0x6A5232), RGB(0x2E2214)), light: CGPoint(x: 0.4, y: 0.4))

    // Speckled pastel coupe plate: no well ring, just the rim's soft roll.
    let c = CGPoint(x: 504, y: 528)
    let r: CGFloat = 430
    // Tinted: a mid-grey plate so the pancakes, not the plate, carry the light.
    let glaze = appearance == .tinted ? RGB(0x5A6462) : dark ? RGB(0x9EB4AE) : RGB(0xD3E4DE)
    let glazeShade = appearance == .tinted ? RGB(0x3A4240) : dark ? RGB(0x7A908A) : RGB(0xB6CCC6)
    withShadow(ctx, dy: 16, blur: 36, RGB(0x6A4A20, alpha: 0.35)) { fill(ctx, ellipsePath(c, r), glaze) }
    shade(ctx, ellipsePath(c, r), [glaze.mixed(with: RGB(0xFFFFFF), 0.3), glaze, glazeShade], light: CGPoint(x: -0.4, y: -0.45))
    clipped(ctx, ellipsePath(c, r)) {
        var rng = SeededRandom(17)
        for _ in 0..<700 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * r)
            ctx.setFillColor(RGB(0x4A3A30, alpha: rng.range(0.2, 0.55)).cg)
            ctx.fillEllipse(in: circle(p, rng.range(0.8, 2.6)))
        }
    }

    // A stack of three, each a little offset to the lower right: golden-brown sides with pale crumb lines between.
    let pr: CGFloat = 262
    let tc = CGPoint(x: c.x - 18, y: c.y - 22)
    let sides = CGMutablePath()
    for (i, o) in [CGFloat(44), 22].enumerated() {
        let pc = CGPoint(x: tc.x + o * 0.7, y: tc.y + o)
        let side = blobPath(pc, pr + 2, jitter: 0.02, points: 16, seed: UInt64(i + 3), stretch: 1.02)
        sides.addPath(side)
        withShadow(ctx, dy: 10, blur: 18, RGB(0x6A3A08, alpha: 0.35)) { fill(ctx, side, RGB(0xC88A40)) }
        shade(ctx, side, [RGB(0xE8B470), RGB(0xC88A40), RGB(0x9A5E22)], light: CGPoint(x: -0.2, y: -0.25))
        // The pale crumb where this pancake meets the one above.
        let crumb = blobPath(CGPoint(x: pc.x - 10 * 0.7, y: pc.y - 10), pr + 1, jitter: 0.02, points: 16, seed: UInt64(i + 30), stretch: 1.02)
        ctx.addPath(crumb)
        ctx.setStrokeColor(RGB(0xF8E2B0, alpha: 0.9).cg)
        ctx.setLineWidth(7)
        ctx.strokePath()
    }
    bPancake(ctx, tc, pr, seed: 5, top: true)

    // Maple syrup: a glossy amber layer with a wavy edge and a few short drips over the rim.
    let syrup = CGMutablePath()
    syrup.addPath(blobPath(CGPoint(x: tc.x + 6, y: tc.y + 6), 222, jitter: 0.06, points: 22, seed: 8, stretch: 1.04, angle: 0.4))
    // Seen from above only the near (lower) side shows drips: they leave the pool, taper over the rim
    // and end in a bead. Drips on the far side would read as ears.
    let drips: [(CGFloat, CGFloat, CGFloat)] = [(deg(38), 22, 40), (deg(82), 30, 46), (deg(122), 14, 34)]
    for (a, over, w) in drips {
        for k in 0...24 {
            let t = CGFloat(k) / 24
            let rw = w / 2 * (1.25 - 0.55 * t)
            let d = 196 + (pr + over - 196) * t
            syrup.addEllipse(in: circle(pt(tc, a + sin(t * 3) * 0.02, d), rw))
        }
        syrup.addEllipse(in: circle(pt(tc, a, pr + over + w * 0.05), w * 0.42))
    }
    // Where drips cross the rim on the lower right, the syrup carries on down the stack's sides.
    for (a, _, w) in drips where a > 0 {
        let run = CGMutablePath()
        for k in 0...12 {
            let d = pr + CGFloat(k) / 12 * 44
            run.addEllipse(in: circle(pt(tc, a, d), w * (0.36 - CGFloat(k) * 0.008)))
        }
        clipped(ctx, sides) { fill(ctx, run, RGB(0x9A4A0C, alpha: 0.85)) }
    }
    ctx.saveGState()
    ctx.setAlpha(0.9)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    withShadow(ctx, dy: 4, blur: 8, RGB(0x5A2A00, alpha: 0.4)) { fill(ctx, syrup, RGB(0xB25E14)) }
    shade(ctx, syrup, [RGB(0xEAA24A), RGB(0xC06A18), RGB(0x8A4008)], light: CGPoint(x: -0.25, y: -0.3))
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    clipped(ctx, syrup) {
        ctx.setStrokeColor(RGB(0xFFF0C8, alpha: 0.75).cg)
        ctx.setLineCap(.round)
        ctx.setLineWidth(8)
        ctx.addArc(center: tc, radius: 168, startAngle: deg(-175), endAngle: deg(-128), clockwise: false)
        ctx.strokePath()
        ctx.setLineWidth(5)
        ctx.addArc(center: tc, radius: 182, startAngle: deg(-110), endAngle: deg(-88), clockwise: false)
        ctx.strokePath()
    }

    // Butter, melting: a softened pat in a glossy golden puddle.
    let bc = CGPoint(x: tc.x - 6, y: tc.y - 10)
    let puddle = blobPath(CGPoint(x: bc.x + 10, y: bc.y + 12), 80, jitter: 0.16, points: 11, seed: 29, stretch: 1.2, angle: 0.5)
    fill(ctx, puddle, RGB(0xF2BE50, alpha: 0.6))
    clipped(ctx, puddle) {
        glint(ctx, CGPoint(x: bc.x - 30, y: bc.y - 40), w: 90, h: 26, angle: deg(-30), alpha: 0.6)
    }
    let butter = roundedRect(bc, w: 104, h: 94, r: 30, angle: deg(12))
    withShadow(ctx, dy: 5, blur: 10, RGB(0x6A3A00, alpha: 0.35)) { fill(ctx, butter, RGB(0xFBE8A8)) }
    shade(ctx, butter, [RGB(0xFFFBE6), RGB(0xFCEAAE), RGB(0xEED08A)])
    glint(ctx, CGPoint(x: bc.x - 16, y: bc.y - 18), w: 48, h: 16, angle: deg(-20), alpha: 0.85)

    // Berries: a few on top, a little heap on the plate.
    for (p, rr, k) in [(CGPoint(x: tc.x + 110, y: tc.y - 100), CGFloat(30), 1), (CGPoint(x: tc.x - 120, y: tc.y + 80), 28, 2),
                       (CGPoint(x: c.x + 300, y: c.y - 170), 30, 3), (CGPoint(x: c.x + 250, y: c.y - 238), 28, 4)] {
        bRaspberry(ctx, p, rr, seed: UInt64(k))
    }
    for (i, p) in [CGPoint(x: tc.x + 60, y: tc.y + 110), CGPoint(x: tc.x - 70, y: tc.y - 110), CGPoint(x: c.x + 345, y: c.y - 110),
                   CGPoint(x: c.x + 330, y: c.y - 230), CGPoint(x: c.x + 360, y: c.y - 165), CGPoint(x: c.x + 205, y: c.y - 285)].enumerated() {
        bBlueberry(ctx, p, 24, angle: CGFloat(i))
    }
    bMintLeaf(ctx, CGPoint(x: tc.x + 52, y: tc.y - 128), length: 70, angle: deg(-35))
    bMintLeaf(ctx, CGPoint(x: tc.x + 92, y: tc.y - 140), length: 56, angle: deg(15))

    // Powdered sugar dusting.
    var dust = SeededRandom(33)
    for _ in 0..<500 {
        let p = pt(tc, dust.next() * .pi * 2, sqrt(dust.next()) * 270)
        ctx.setFillColor(RGB(0xFFFFFF, alpha: dust.range(0.35, 0.8)).cg)
        ctx.fillEllipse(in: circle(p, dust.range(0.8, 2)))
    }

    if appearance != .tinted { bWindowLight(ctx, shadow: dark ? RGB(0x8A7E98) : RGB(0xD2C2C8)) }
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
    Icon(suffix: "EnamelCocotte", slug: "enamel-cocotte", label: "Enamel Cocotte", draw: drawEnamelCocotte),
    Icon(suffix: "Candlelight", slug: "candlelight", label: "Candlelight", draw: drawCandlelight),
    Icon(suffix: "SundayBrunch", slug: "sunday-brunch", label: "Sunday Brunch", draw: drawSundayBrunch),
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
