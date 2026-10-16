// MealMate subscriber app icon proposals. Design exploration only: nothing here writes into the app.
//
// Usage:  swift Design/make-icon-subscriber-proposals.swift [out-dir]
// Faster: swiftc -O Design/make-icon-subscriber-proposals.swift -o /tmp/sub-icons && /tmp/sub-icons [out-dir]
// Default out dir: /tmp/mealmate-sub-icons. Run from the repo root (the current Salad, Copper Pot
// and Midnight Kitchen icons are read from MealMate/Resources for comparison).
//
// Writes:
//   proposal-<n>-<slug>.png              1024x1024 light appearance
//   appearances/proposal-<n>-<slug>-{dark,tinted}.png
//   overview.png                         every proposal large and at home-screen size, next to the current icons,
//                                        plus light / dark / tinted home-screen strips
//
// The helpers below are copied from Design/make-icon-variants.swift (same light, shadows and ground grain),
// so a chosen proposal can move over unchanged.

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


// MARK: - Extra helpers for the subscriber proposals

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


// MARK: - Proposals A: metal and enamel cookware
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

// MARK: - 1. Hammered Copper

/// Polished hammered copper: deep shadows, rosy mids, near-white glints.
func aCopper(_ s: AShade) -> AVec {
    let mirror = aSmooth(0.5, 0.97, s.window)
    var v = 0.08 + 0.58 * s.lambert + 0.5 * mirror
    // The crease where the rolled lip meets the wall stays dark.
    if s.d > 0.935 && s.d < 0.955 { v *= 0.55 + 0.45 * abs(s.d - 0.945) / 0.01 }
    var col = aRamp([(0, aV(0x2E1006)), (0.3, aV(0x7A3519)), (0.55, aV(0xB9643A)), (0.78, aV(0xE69766)),
                     (0.95, aV(0xF8C59C)), (1.1, aV(0xFFEBD8))], v)
    col += aV(0xFFF0E0) * (0.6 * s.spec(70))
    return col * (1 + s.grain(5) * 0.04)
}

func aCopperProfile(_ d: Float) -> (Float, Int) {
    if d > 0.955 {
        // Rolled lip: a half torus, outer half faces out, inner half faces in.
        let t = (d - 0.9775) / 0.0225
        return (t * 0.92, 2)
    }
    if d > 0.79 {
        // Wall, flaring out: faces the centre.
        return (-0.62 * aSmooth(0.79, 0.86, d), 1)
    }
    return (-0.06 * d / 0.79, 0)
}

/// Seared scallop from above: a thin ivory side ring under a caramelised crust, dark bronze at the edge
/// and golden-brown in the middle, mottled by the sear and glossy with butter.
func aScallop(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, seed: UInt64) {
    let body = blobPath(p, r, jitter: 0.025, points: 11, seed: seed, stretch: 1.03, angle: CGFloat(seed))
    withShadow(ctx, dy: r * 0.14, blur: r * 0.3, RGB(0x1E0800, alpha: 0.65)) { fill(ctx, body, RGB(0xEAD8B8)) }
    shade(ctx, body, [RGB(0xFFF8EA), RGB(0xF3E3C6), RGB(0xC9AC84)], light: CGPoint(x: -0.35, y: -0.4), locations: [0, 0.45, 1])
    // The crust sits on top of the cylinder, so it's nudged towards the light and the side shows below it.
    let pc = CGPoint(x: p.x - r * 0.025, y: p.y - r * 0.035)
    let rc = Float(r * 0.94)
    let mottle = Noise(seed: UInt32(seed) &+ 500), spots = Noise(seed: UInt32(seed) &+ 600), rim = Noise(seed: UInt32(seed) &+ 700)
    let box = circle(pc, r)
    let ox = Float(box.minX), oy = Float(box.minY), pcx = Float(pc.x), pcy = Float(pc.y)
    let crust = textureImage(width: Int(box.width), height: Int(box.height)) { lx, ly in
        let x = lx + ox, y = ly + oy
        let dx = x - pcx, dy = y - pcy
        let dist = sqrt(dx * dx + dy * dy)
        let ang = atan2(dy, dx)
        let edge = rc * (1 + 0.07 * (rim.fbm(cos(ang) * 3 + 9, sin(ang) * 3 + 9, octaves: 4) - 0.5))
        let alpha = max(0, min(1, edge - dist + 0.5))
        if alpha <= 0 { return (0, 0, 0, 0) }
        let d = dist / edge
        var col = aRamp([(0, aV(0xDAA35C)), (0.5, aV(0xC9883E)), (0.8, aV(0xA25C22)), (0.94, aV(0x7E4014)), (1, aV(0xB98250))], d)
        // Maillard mottling: blend towards deeper brown or paler gold, keeping the hue warm.
        let m = mottle.fbm(x * 0.05, y * 0.05, octaves: 3) - 0.5
        col = col + (aV(0x8A4616) - col) * min(1, max(0, m) * 1.5)
        col = col + (aV(0xEEC488) - col) * min(1, max(0, -m) * 0.9)
        let sp = spots.fbm(x * 0.02, y * 0.02, octaves: 2)
        col = col + (aV(0x7A3810) - col) * (0.45 * aSmooth(0.58, 0.66, sp))
        col *= 1 + (aHash(Int32(x), Int32(y), 3) - 0.5) * 0.1
        // Gently domed, bumpy surface for the butter gloss.
        let m0 = mottle.fbm(x * 0.03, y * 0.03, octaves: 2)
        let bx = mottle.fbm(x * 0.03 + 0.1, y * 0.03, octaves: 2) - m0
        let by = mottle.fbm(x * 0.03, y * 0.03 + 0.1, octaves: 2) - m0
        let n = simd_normalize(AVec(dx / rc * 0.22 + bx * 3, dy / rc * 0.22 + by * 3, 1))
        let lambert = max(0, simd_dot(n, aLight))
        col = col * (0.62 + 0.45 * lambert)
        col += aV(0xFFF0D8) * (0.5 * pow(max(0, simd_dot(n, aHalf)), 120) + 0.05 * pow(max(0, simd_dot(n, aHalf)), 8))
        return (col.x, col.y, col.z, alpha)
    }
    drawTexture(ctx, crust, in: box)
}

/// Fried sage leaf: darker olive, a soft sheen, one edge curling up to show its paler underside.
func aSage(_ ctx: CGContext, _ c: CGPoint, length: CGFloat, angle: CGFloat, seed: UInt64) {
    let path = leafPath(c, length: length, width: length * 0.3, angle: angle, belly: -length * 0.06)
    let under = leafPath(pt(c, angle + .pi / 2, length * 0.07), length: length * 0.96, width: length * 0.29, angle: angle + 0.05, belly: -length * 0.06)
    withShadow(ctx, dy: length * 0.05, blur: length * 0.12, RGB(0x140800, alpha: 0.55)) { fill(ctx, under, RGB(0x4A5630)) }
    shade(ctx, under, [RGB(0x9AA27A), RGB(0x6E7A50)])
    shade(ctx, path, [RGB(0x6C7840), RGB(0x48562C), RGB(0x2A3418)], light: CGPoint(x: -0.25, y: -0.3), locations: [0, 0.5, 1])
    clipped(ctx, path) {
        // Velvety texture.
        var rng = SeededRandom(seed)
        for _ in 0..<70 {
            let q = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * length * 0.5)
            ctx.setFillColor(RGB(0xE2E8C8, alpha: rng.range(0.04, 0.14)).cg)
            ctx.fillEllipse(in: circle(q, rng.range(1, 2.5)))
        }
        // Fried sheen along the leaf.
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: 1, y: 0.18)
        ctx.drawRadialGradient(gradient([RGB(0xFFFBE8, alpha: 0.4), RGB(0xFFFBE8, alpha: 0)]), startCenter: CGPoint(x: -length * 0.05, y: -length * 0.25),
                               startRadius: 0, endCenter: CGPoint(x: -length * 0.05, y: -length * 0.25), endRadius: length * 0.4, options: [])
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.setStrokeColor(RGB(0xC8D0A8, alpha: 0.55).cg)
    ctx.setLineCap(.round)
    ctx.setLineWidth(length * 0.02)
    ctx.move(to: CGPoint(x: -length * 0.5, y: 0))
    ctx.addQuadCurve(to: CGPoint(x: length * 0.4, y: 0), control: CGPoint(x: 0, y: -length * 0.025))
    ctx.strokePath()
    ctx.setLineWidth(length * 0.01)
    for i in 0..<4 {
        let x = -length * 0.3 + CGFloat(i) * length * 0.17
        for s: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addQuadCurve(to: CGPoint(x: x + length * 0.13, y: s * length * 0.1), control: CGPoint(x: x + length * 0.03, y: s * length * 0.08))
        }
    }
    ctx.strokePath()
    ctx.setStrokeColor(RGB(0x4E5A32).cg)
    ctx.setLineWidth(length * 0.03)
    ctx.move(to: CGPoint(x: -length * 0.5, y: 0))
    ctx.addLine(to: CGPoint(x: -length * 0.62, y: length * 0.02))
    ctx.strokePath()
    ctx.restoreGState()
}

func drawHammeredCopper(_ ctx: CGContext) {
    drawGround(ctx, inner: RGB(0x403936), outer: RGB(0x191615), dark: (RGB(0x262120), RGB(0x0A0908)), light: CGPoint(x: 0.3, y: 0.25))
    aMottle(ctx, seed: 31, scale: 0.006, strength: 0.08)
    let c = CGPoint(x: 566, y: 572)
    let R: CGFloat = 384
    let handleAngle = deg(-135)

    // Handle: solid cast brass, riveted under the lip, running off to the upper left.
    let start = pt(c, handleAngle, R * 0.9)
    let bar = aBarPath(start, angle: handleAngle, length: 560, w0: 92, w1: 52)
    withShadow(ctx, dy: 26, blur: 34, RGB(0x000000, alpha: 0.55)) { fill(ctx, bar, RGB(0x8A6420)) }
    aCylinderShade(ctx, bar, from: start, angle: handleAngle, width: 92,
                   [RGB(0x3E2A0A), RGB(0x8A6420), RGB(0xE8C46E), RGB(0xFFF0C0), RGB(0xC99A42), RGB(0x6A4812), RGB(0x2E1E06)],
                   [0, 0.18, 0.38, 0.46, 0.6, 0.85, 1])
    // A hanging loop worked into the end.
    let hole = pt(start, handleAngle, 470)
    fill(ctx, ellipsePath(hole, 15), RGB(0x1E1A16, alpha: 0.85))

    // Pan.
    withShadow(ctx, dy: R * 0.07, blur: R * 0.18, RGB(0x000000, alpha: 0.65)) { fill(ctx, ellipsePath(c, R), RGB(0x5A2810)) }
    drawTexture(ctx, aVesselImage(c, R, dimple: 28, dimpleDepth: 0.3, dimpleZones: [0, 1], floorDimple: 0.45,
                                  profile: aCopperProfile, material: aCopper))
    // Interior rivet heads where the handle is fixed.
    for s: CGFloat in [-1, 1] {
        let rp = pt(pt(c, handleAngle, R * 0.885), handleAngle + .pi / 2, s * 24)
        withShadow(ctx, dy: 3, blur: 5, RGB(0x2A0A00, alpha: 0.6)) { fill(ctx, ellipsePath(rp, 11), RGB(0xB8743E)) }
        shade(ctx, ellipsePath(rp, 11), [RGB(0xFFE0BE), RGB(0xC8804A), RGB(0x6A3014)], locations: [0, 0.5, 1])
    }

    // Brown butter pooled on the floor, nut-brown foam gathering around the scallops.
    let floor = R * 0.79
    let pool = blobPath(c, floor * 0.93, jitter: 0.05, points: 13, seed: 51)
    clipped(ctx, pool) {
        ctx.drawRadialGradient(gradient([RGB(0xA86020, alpha: 0.5), RGB(0x8A4616, alpha: 0.62), RGB(0x5A2408, alpha: 0.8)], [0, 0.6, 1]),
                               startCenter: pt(c, deg(-130), floor * 0.25), startRadius: 0, endCenter: c, endRadius: floor * 0.95,
                               options: [.drawsAfterEndLocation])
    }
    let ring: CGFloat = 160
    let spots = (0..<5).map { pt(c, deg(-90 + CGFloat($0) * 72), ring) }
    let scallopR: CGFloat = 88
    var rng = SeededRandom(81)
    func foam(around p: CGPoint, from r0: CGFloat, to r1: CGFloat, count: Int) {
        // Soft band of nut-brown froth, tiny bubbles in it, browned flecks.
        ctx.drawRadialGradient(gradient([RGB(0xD9AE78, alpha: 0), RGB(0xD9AE78, alpha: 0.75), RGB(0xC8955E, alpha: 0.35), RGB(0xC8955E, alpha: 0)],
                                        [0, 0.02, 0.6, 1]),
                               startCenter: p, startRadius: r0, endCenter: p, endRadius: r1, options: [])
        for _ in 0..<count {
            let q = pt(p, rng.next() * .pi * 2, rng.range(r0, r1))
            if rng.next() > 0.5 {
                ctx.setFillColor(RGB(0xF2DDB4, alpha: rng.range(0.5, 0.85)).cg)
                ctx.fillEllipse(in: circle(q, rng.range(1.2, 3)))
            } else {
                ctx.setFillColor(RGB(0x3A1604, alpha: rng.range(0.6, 0.9)).cg)
                ctx.fillEllipse(in: circle(q, rng.range(0.9, 2)))
            }
        }
    }
    clipped(ctx, pool) {
        for p in spots { foam(around: p, from: scallopR * 0.9, to: scallopR * 1.35, count: 120) }
        foam(around: c, from: 0, to: 60, count: 70)
    }
    for (i, p) in spots.enumerated() { aScallop(ctx, p, scallopR, seed: UInt64(i * 5 + 3)) }
    // Sage: two crossed in the middle, three in the outer gaps.
    aSage(ctx, CGPoint(x: c.x - 18, y: c.y + 4), length: 122, angle: deg(-30), seed: 70)
    aSage(ctx, CGPoint(x: c.x + 20, y: c.y + 8), length: 112, angle: deg(62), seed: 71)
    for (k, i) in [0, 2, 3].enumerated() {
        let a = deg(-54 + CGFloat(i) * 72)
        aSage(ctx, pt(c, a, ring * 1.32), length: 104, angle: a + deg(k % 2 == 0 ? 75 : -70), seed: UInt64(k + 72))
    }
    // Flaky salt and cracked pepper.
    var r2 = SeededRandom(91)
    for p in spots {
        for _ in 0..<4 {
            let q = pt(p, r2.next() * .pi * 2, r2.range(10, 50))
            fill(ctx, blobPath(q, r2.range(2.5, 4.5), jitter: 0.35, points: 5, seed: UInt64(q.x), angle: r2.next() * 3),
                 RGB(0xFFFFFF, alpha: 0.9))
        }
    }
    drawFlecks(ctx, center: c, radius: floor * 0.85, count: 30, size: 2.4, colors: [RGB(0x1E140E)], seed: 93)
}

// MARK: - 2. Cast Iron

/// Seasoned cast iron: satin black with a warm, soft sheen and a sand-cast grain.
func aIron(_ s: AShade) -> AVec {
    let mirror = aSmooth(0.55, 0.98, s.window)
    let v = 0.08 + 0.38 * s.lambert + 0.5 * mirror + s.grain(11) * 0.05
    var col = aRamp([(0, aV(0x070606)), (0.35, aV(0x1A1817)), (0.6, aV(0x302C29)), (0.85, aV(0x5E5852)), (1.0, aV(0x9A938A))], v)
    col += aV(0xE8E0D4) * (0.35 * s.spec(40))
    return col
}

func aIronProfile(_ d: Float) -> (Float, Int) {
    if d > 0.955 { return ((d - 0.9775) / 0.0225 * 0.85, 2) }
    if d > 0.74 { return (-0.6 * aSmooth(0.74, 0.8, d), 1) }
    return (0, 0)
}

/// Walnut board: long wavering grain, open pores, a soft tone drift.
func aWalnutImage(dark: Bool) -> CGImage {
    let warp = Noise(seed: 21), tone = Noise(seed: 22), pores = Noise(seed: 23)
    let k: Float = dark ? 0.5 : 1
    let light = aV(0x84593A) * k, base = aV(0x5A3823) * k, deep = aV(0x2A170C) * k
    return textureImage { x, y in
        let w = warp.fbm(x * 0.0016, y * 0.005, octaves: 3)
        let g = y * 0.04 + w * 7
        let line = pow(0.5 + 0.5 * sin(g * 2 * .pi), 9)
        let t = tone.fbm(x * 0.0014, y * 0.007, octaves: 3)
        let p = pores.fbm(x * 0.008, y * 0.32, octaves: 2)
        var col = light + (base - light) * min(1, max(0, t * 1.3 - 0.1))
        let darken = min(1, line * 0.38 + max(0, p - 0.56) * 0.7)
        col = col + (deep - col) * darken
        return (col.x, col.y, col.z, 1)
    }
}

/// Raspberry from above: ringed drupelets around a hollow.
func aRaspberry(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, seed: UInt64) {
    withShadow(ctx, dy: r * 0.2, blur: r * 0.35, RGB(0x3A0A00, alpha: 0.5)) { fill(ctx, ellipsePath(p, r), RGB(0xB01838)) }
    var drupes: [(CGPoint, CGFloat)] = []
    var rng = SeededRandom(seed)
    for (ringR, count) in [(0.72, 11), (0.42, 7)] as [(CGFloat, Int)] {
        let phase = rng.next() * .pi
        for i in 0..<count {
            drupes.append((pt(p, phase + CGFloat(i) / CGFloat(count) * .pi * 2, r * ringR), r * (ringR > 0.5 ? 0.26 : 0.24)))
        }
    }
    // Back to front from the far side so the near drupelets overlap.
    for (q, dr) in drupes.sorted(by: { $0.0.y < $1.0.y }) {
        shade(ctx, ellipsePath(q, dr), [RGB(0xFF7A92), RGB(0xD92A4E), RGB(0x8A0C26)], locations: [0, 0.5, 1])
        ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.55).cg)
        ctx.fillEllipse(in: circle(CGPoint(x: q.x - dr * 0.35, y: q.y - dr * 0.38), dr * 0.22))
    }
    fill(ctx, ellipsePath(p, r * 0.17), RGB(0x5A0414))
}

func aBlueberry(_ ctx: CGContext, _ p: CGPoint, _ r: CGFloat, seed: UInt64) {
    let path = blobPath(p, r, jitter: 0.04, points: 8, seed: seed)
    withShadow(ctx, dy: r * 0.2, blur: r * 0.35, RGB(0x000020, alpha: 0.5)) { fill(ctx, path, RGB(0x2A2E5C)) }
    shade(ctx, path, [RGB(0x8A96C8), RGB(0x3C4482), RGB(0x1A1C40)], locations: [0, 0.45, 1])
    // Crown.
    let crown = pt(p, deg(-60 + CGFloat(seed % 5) * 30), r * 0.2)
    let star = CGMutablePath()
    for i in 0..<10 {
        let q = pt(crown, CGFloat(i) * .pi / 5, i % 2 == 0 ? r * 0.3 : r * 0.12)
        if i == 0 { star.move(to: q) } else { star.addLine(to: q) }
    }
    star.closeSubpath()
    fill(ctx, star, RGB(0x14102A))
    ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.4).cg)
    ctx.fillEllipse(in: CGRect(x: p.x - r * 0.62, y: p.y - r * 0.6, width: r * 0.36, height: r * 0.2))
}

/// Lemon wedge lying cut side up: rind arc, pith, juicy segments.
func aLemonWedge(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, angle: CGFloat) {
    func wedge(_ rr: CGFloat, _ squash: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -rr, y: 0))
        p.addArc(center: .zero, radius: rr, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addQuadCurve(to: CGPoint(x: -rr, y: 0), control: CGPoint(x: 0, y: rr * squash))
        p.closeSubpath()
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle).scaledBy(x: 1, y: 0.62)
        return p.copy(using: &t)!
    }
    let rind = wedge(r, -0.05)
    withShadow(ctx, dy: r * 0.12, blur: r * 0.25, RGB(0x3A2000, alpha: 0.45)) { fill(ctx, rind, RGB(0xF2C21A)) }
    shade(ctx, rind, [RGB(0xFFE87A), RGB(0xF4C514), RGB(0xC8920A)])
    fill(ctx, wedge(r * 0.9, 0.02), RGB(0xFBF4D4))
    let flesh = wedge(r * 0.82, 0.08)
    shade(ctx, flesh, [RGB(0xFFF4A8), RGB(0xF9DE58), RGB(0xEEC63A)])
    ctx.saveGState()
    ctx.addPath(flesh)
    ctx.clip()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    ctx.scaleBy(x: 1, y: 0.62)
    ctx.setStrokeColor(RGB(0xFFFBE6, alpha: 0.85).cg)
    ctx.setLineWidth(3)
    for i in 1..<5 {
        let a = .pi + CGFloat(i) / 5 * .pi
        ctx.move(to: CGPoint(x: 0, y: r * 0.05))
        ctx.addLine(to: CGPoint(x: cos(a) * r, y: sin(a) * r))
    }
    ctx.strokePath()
    ctx.restoreGState()
    glint(ctx, pt(c, angle - deg(110), r * 0.4), w: r * 0.35, h: r * 0.1, angle: angle, alpha: 0.6)
}

/// Dutch baby as a height field: a crisp, scalloped ring of puffed folds (browned peaks, golden valleys)
/// around a flat, custardy centre with a few browned spots.
func aDutchBabyImage(_ c: CGPoint, _ ri: CGFloat) -> CGImage {
    let warp = Noise(seed: 41), amp = Noise(seed: 43), spots = Noise(seed: 47), crinkle = Noise(seed: 49)
    let cx = Float(c.x), cy = Float(c.y), r = Float(ri)
    /// Ridged noise over the ring: wavy, broken folds running roughly outwards, sharp at the crests.
    func fold(_ ux: Float, _ uy: Float, _ ang: Float, _ d: Float) -> Float {
        let n1 = warp.fbm(ux * 4.5 + d * 1.6 + 10, uy * 4.5 - d * 1.2 + 10, octaves: 3)
        let n2 = warp.fbm(ux * 9 + d * 4 + 30, uy * 9 + d * 3 + 30, octaves: 2)
        return (1 - abs(2 * n1 - 1)) * 0.75 + (1 - abs(2 * n2 - 1)) * 0.25
    }
    func height(_ x: Float, _ y: Float) -> Float {
        let dx = x - cx, dy = y - cy
        let dist = sqrt(dx * dx + dy * dy)
        let d = dist / r
        let ang = atan2(dy, dx)
        let ux = cos(ang), uy = sin(ang)
        let p = fold(ux, uy, ang, d)
        let a = 0.55 + 0.9 * amp.fbm(ux * 2 + 7, uy * 2 + 7, octaves: 2)
        let reach = 0.08 * (amp.fbm(ux * 3 + 1, uy * 3 + 1, octaves: 2) - 0.5) - 0.06 * p
        let ring = aSmooth(0.48 + reach, 0.7 + reach, d) * (1 - aSmooth(0.9, 1.0, d) * 0.6)
        let k = 1 - abs(crinkle.fbm(x * 0.05, y * 0.05, octaves: 2) * 2 - 1)
        return ring * (0.3 + 0.7 * pow(p, 1.4) * a) * 64 + k * 2.5 * ring + (1 - ring) * spots.fbm(x * 0.03, y * 0.03, octaves: 2) * 3
    }
    return textureImage { x, y in
        let dx = x - cx, dy = y - cy
        let dist = sqrt(dx * dx + dy * dy)
        let ang = atan2(dy, dx)
        let p = fold(cos(ang), sin(ang), ang, dist / r)
        // Scalloped outline: the valleys between folds pull in a little.
        let edge = r * (1 - 0.03 * (1 - p))
        let alpha = max(0, min(1, edge - dist + 0.5))
        if alpha <= 0 { return (0, 0, 0, 0) }
        let d = dist / r
        let h = height(x, y)
        let n = simd_normalize(AVec(-(height(x + 1, y) - h), -(height(x, y + 1) - h), 1))
        let lambert = max(0, simd_dot(n, aLight))
        let ring = aSmooth(0.5, 0.7, d)
        // Centre: pale gold with crisp browned spots. Rim: golden valleys, deep brown peaks.
        var centre = aV(0xEFCF86)
        let sp = spots.fbm(x * 0.022, y * 0.022, octaves: 3)
        centre = centre + (aV(0xC98A3E) - centre) * (0.75 * aSmooth(0.6, 0.63, sp))
        // Browned where the folds crest and rise highest.
        let peak = min(1, max(0, h / 70)) * 0.55 + pow(p, 2.5) * 0.7 * aSmooth(0.6, 0.85, d) + aSmooth(0.9, 1, d) * 0.4
        let rimCol = aRamp([(0, aV(0xF0C46A)), (0.4, aV(0xDE9C44)), (0.7, aV(0xB0621E)), (1, aV(0x7A3A0E))], min(1, peak))
        var col = centre + (rimCol - centre) * ring
        col *= 1 - 0.35 * aSmooth(0.94, 1.0, d)
        col = col * (0.6 + 0.5 * lambert) + aV(0xFFF4DC) * (0.15 * pow(max(0, simd_dot(n, aHalf)), 30))
        return (col.x, col.y, col.z, alpha)
    }
}

func drawCastIron(_ ctx: CGContext) {
    if appearance != .tinted {
        drawTexture(ctx, aWalnutImage(dark: appearance == .dark))
        ctx.drawRadialGradient(gradient([RGB(0xFFD9A8, alpha: 0.16), RGB(0xFFD9A8, alpha: 0)]), startCenter: CGPoint(x: 300, y: 260),
                               startRadius: 0, endCenter: CGPoint(x: 300, y: 260), endRadius: 760, options: [])
        vignette(ctx, 0.35)
    }
    let c = CGPoint(x: 492, y: 492)
    let R: CGFloat = 392
    let handleAngle = deg(45)

    // Long handle off to the lower right, helper handle at the upper left.
    let start = pt(c, handleAngle, R * 0.9)
    let bar = aBarPath(start, angle: handleAngle, length: 420, w0: 120, w1: 86)
    let ironBar = [RGB(0x050505), RGB(0x2A2725), RGB(0x5C5650), RGB(0x2E2B28), RGB(0x121110), RGB(0x050505)]
    withShadow(ctx, dy: 24, blur: 36, RGB(0x000000, alpha: 0.6)) { fill(ctx, bar, RGB(0x151413)) }
    aCylinderShade(ctx, bar, from: start, angle: handleAngle, width: 120, ironBar, [0, 0.12, 0.3, 0.55, 0.85, 1])
    // Recessed channel down the handle.
    let channel = aBarPath(pt(start, handleAngle, 60), angle: handleAngle, length: 330, w0: 64, w1: 48)
    fill(ctx, channel, RGB(0x0C0B0B))
    clipped(ctx, channel) {
        ctx.setShadow(offset: CGSize(width: 3, height: -4), blur: 6, color: RGB(0x000000, alpha: 0.9).cg)
        ctx.addPath(channel)
        ctx.setLineWidth(10)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.strokePath()
    }
    let helperAngle = handleAngle + .pi
    let hc = pt(c, helperAngle, R * 1.0)
    let helper = CGMutablePath()
    helper.addPath(roundedRect(hc, w: 120, h: 150, r: 56, angle: helperAngle))
    helper.addPath(roundedRect(pt(hc, helperAngle, 16), w: 46, h: 82, r: 23, angle: helperAngle))
    withShadow(ctx, dy: 18, blur: 26, RGB(0x000000, alpha: 0.55)) {
        ctx.addPath(helper); ctx.setFillColor(RGB(0x151413).cg); ctx.fillPath(using: .evenOdd)
    }
    clippedEO(ctx, helper) {
        ctx.drawLinearGradient(gradient([RGB(0x6A635C), RGB(0x2A2725), RGB(0x0A0909)]), start: pt(hc, helperAngle, 75),
                               end: pt(hc, helperAngle, -40), options: [])
    }

    // Skillet with two pour spouts across the handle axis.
    let spouts: [Float] = [Float(handleAngle + .pi / 2), Float(handleAngle - .pi / 2)]
    let spoutScale: (Float) -> Float = { a in
        var s: Float = 1
        for sp in spouts {
            var da = abs(a - sp)
            da = min(da, 2 * .pi - da)
            s += 0.045 * max(0, 1 - da / 0.28) * max(0, 1 - da / 0.28)
        }
        return s
    }
    withShadow(ctx, dy: R * 0.07, blur: R * 0.18, RGB(0x000000, alpha: 0.6)) { fill(ctx, ellipsePath(c, R), RGB(0x151413)) }
    drawTexture(ctx, aVesselImage(c, R, radiusScale: spoutScale, profile: aIronProfile, material: aIron))

    // Dutch baby, leaving a wide band of glossy iron wall.
    let ri = R * 0.78
    withShadow(ctx, dy: 8, blur: 16, RGB(0x000000, alpha: 0.6)) { fill(ctx, ellipsePath(c, ri * 0.97), RGB(0x8A4A14)) }
    drawTexture(ctx, aDutchBabyImage(c, ri))

    // Berries scattered over the centre, a small lemon wedge, a fine dusting of sugar.
    aLemonWedge(ctx, CGPoint(x: c.x - 92, y: c.y + 98), 76, angle: deg(-30))
    let blues: [(CGFloat, CGFloat)] = [(-105, -40), (35, -128), (128, 18), (12, 92), (-38, -78), (88, -60), (-4, 6), (150, -88),
                                       (70, 128), (-140, 40)]
    let rasps: [(CGFloat, CGFloat)] = [(-60, -120), (60, -40), (110, 80), (-58, 22), (30, 50), (-130, -90), (160, -30)]
    for (i, o) in blues.enumerated() { aBlueberry(ctx, CGPoint(x: c.x + o.0, y: c.y + o.1), 21, seed: UInt64(i + 300)) }
    for (i, o) in rasps.enumerated() { aRaspberry(ctx, CGPoint(x: c.x + o.0, y: c.y + o.1), 31, seed: UInt64(i + 400)) }
    var r3 = SeededRandom(113)
    for _ in 0..<4200 {
        let d = ri * 0.88 * pow(r3.next(), 0.85)
        let q = pt(CGPoint(x: c.x - 8, y: c.y - 8), r3.next() * .pi * 2, d)
        ctx.setFillColor(RGB(0xFFFFFF, alpha: r3.range(0.7, 1) * (1 - d / ri * 0.85)).cg)
        ctx.fillEllipse(in: circle(q, r3.range(0.7, 1.5)))
    }
}

// MARK: - 3. Enamel Cocotte

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

let proposalsA: [Proposal] = [
    Proposal(number: 1, slug: "hammered-copper", label: "Hammered Copper", draw: drawHammeredCopper),
    Proposal(number: 2, slug: "cast-iron", label: "Cast Iron", draw: drawCastIron),
    Proposal(number: 3, slug: "enamel-cocotte", label: "Enamel Cocotte", draw: drawEnamelCocotte),
]


// MARK: - Proposals B: moments (marble pâtisserie, candlelight, sunday brunch)

let proposalsB: [Proposal] = [
    Proposal(number: 4, slug: "marble-patisserie", label: "Marble Pâtisserie", draw: drawMarblePatisserie),
    Proposal(number: 5, slug: "candlelight", label: "Candlelight", draw: drawCandlelight),
    Proposal(number: 8, slug: "sunday-brunch", label: "Sunday Brunch", draw: drawSundayBrunch),
]

// MARK: Shared bits

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

// MARK: - 4. Marble pâtisserie

/// Carrara (light) or Nero Marquina (dark) marble: soft clouds, a few branching diagonal veins that fade in
/// and out, hairline veins, and one very fine gold vein.
func bMarbleTexture(dark: Bool) -> CGImage {
    let warp = Noise(seed: 41), fine = Noise(seed: 43), cloud = Noise(seed: 47), fade = Noise(seed: 53)
    let base: (Float, Float, Float) = dark ? (0.07, 0.07, 0.078) : (0.958, 0.952, 0.94)
    let cloudy: (Float, Float, Float) = dark ? (0.12, 0.12, 0.13) : (0.875, 0.872, 0.865)
    let vein: (Float, Float, Float) = dark ? (0.72, 0.71, 0.69) : (0.5, 0.52, 0.56)
    let gold: (Float, Float, Float) = (0.8, 0.64, 0.36)
    func smooth(_ a: Float, _ b: Float, _ t: Float) -> Float { let u = min(max((t - a) / (b - a), 0), 1); return u * u * (3 - 2 * u) }
    func band(_ f: Float, _ width: Float) -> Float { let s = abs(sin(f * .pi)); return exp(-(s * s) / (width * width)) }
    return textureImage { x, y in
        let w = warp.fbm(x * 0.0016, y * 0.0016, octaves: 5)
        let w2 = fine.fbm(x * 0.005 + 10, y * 0.005, octaves: 4)
        // Main veins run diagonally, warped, and come and go along their length.
        let f = (x * 0.9 + y * 0.5) / 1024 * 2.2 + w * 2.2 + w2 * 0.15
        let main = band(f, 0.035 + 0.03 * w2) + band(f, 0.2) * 0.22
        let mainFade = smooth(0.38, 0.62, fade.fbm(x * 0.0025, y * 0.0025, octaves: 3))
        // Branches: steeper, thinner.
        let g = (x * -0.4 + y * 0.9) / 1024 * 3.0 + w * 2.8 + w2 * 0.4
        let branch = band(g, 0.02) * smooth(0.5, 0.7, fade.fbm(x * 0.003 + 5, y * 0.003 + 9, octaves: 3))
        // Hairlines everywhere, faint.
        let hc = (x * 0.7 + y * 0.7) / 1024 * 9 + w2 * 3.5
        let hair = band(hc, 0.012) * 0.3 * smooth(0.45, 0.75, fade.fbm(x * 0.004 + 3, y * 0.004, octaves: 2))
        // One rare fine gold vein.
        let gv = (x * 0.55 + y * -0.85) / 1024 * 1.4 + w * 1.6 + 0.35
        let goldAmt = band(gv, 0.01) * smooth(0.42, 0.6, fade.fbm(x * 0.002 + 20, y * 0.002, octaves: 2)) * 0.8
        let cl = smooth(0.4, 0.8, cloud.fbm(x * 0.0028, y * 0.0028, octaves: 5))
        var r = base.0 + (cloudy.0 - base.0) * cl
        var gg = base.1 + (cloudy.1 - base.1) * cl
        var b = base.2 + (cloudy.2 - base.2) * cl
        let v = min(1, main * mainFade * 0.8 + branch * 0.55 + hair) * (dark ? 0.55 : 0.62)
        r += (vein.0 - r) * v; gg += (vein.1 - gg) * v; b += (vein.2 - b) * v
        r += (gold.0 - r) * goldAmt; gg += (gold.1 - gg) * goldAmt; b += (gold.2 - b) * goldAmt
        return (r, gg, b, 1)
    }
}

func drawMarblePatisserie(_ ctx: CGContext) {
    let dark = appearance == .dark
    if appearance != .tinted {
        drawTexture(ctx, bMarbleTexture(dark: dark))
        // Soft daylight from the upper left, polished stone sheen.
        let lightPos = CGPoint(x: 260, y: 200)
        ctx.drawRadialGradient(gradient([RGB(0xFFFFFF, alpha: dark ? 0.08 : 0.35), RGB(0xFFFFFF, alpha: 0)]), startCenter: lightPos, startRadius: 0,
                               endCenter: lightPos, endRadius: 700, options: [])
        vignette(ctx, dark ? 0.35 : 0.12)
    }
    let c = CGPoint(x: 512, y: 518)
    let plateR: CGFloat = 450
    let tinted = appearance == .tinted
    bPorcelainPlate(ctx, c, plateR, body: tinted ? RGB(0x6A6A6A) : dark ? RGB(0xEDE9E2) : RGB(0xFFFFFF),
                    bodyShade: tinted ? RGB(0x4A4A4A) : dark ? RGB(0xC9C3B8) : RGB(0xE6E1D8),
                    shadow: RGB(dark ? 0x000000 : 0x4A4030, alpha: dark ? 0.6 : 0.3), gold: true)

    // Tart: fluted pastry shell.
    let tr: CGFloat = 336
    let fluted = CGMutablePath()
    let flutes = 34
    for k in 0...360 {
        let a = CGFloat(k) / 360 * .pi * 2
        let d = tr * (1 + 0.028 * pow(abs(cos(a * CGFloat(flutes) / 2)), 0.8))
        let p = pt(c, a, d)
        if k == 0 { fluted.move(to: p) } else { fluted.addLine(to: p) }
    }
    fluted.closeSubpath()
    withShadow(ctx, dy: 12, blur: 26, RGB(0x5A3A10, alpha: 0.4)) { fill(ctx, fluted, RGB(0xD49A50)) }
    shade(ctx, fluted, [RGB(0xF4CB82), RGB(0xD39248), RGB(0x9C5E26)], light: CGPoint(x: -0.3, y: -0.35))
    // Flutes: soft grooves between rounded ridges; the ridges facing the light glow.
    clipped(ctx, fluted) {
        for k in 0..<flutes {
            let a = CGFloat(k) / CGFloat(flutes) * .pi * 2
            let groove = CGMutablePath()
            groove.move(to: pt(c, a, tr * 0.9))
            groove.addLine(to: pt(c, a, tr * 1.04))
            bSoftFill(ctx, groove.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 1), RGB(0x7A4012, alpha: 0.55), blur: 5)
            let mid = a + .pi / CGFloat(flutes)
            let lit = max(0, cos(mid - deg(-135)))
            bSoftFill(ctx, leafPath(pt(c, mid, tr * 0.97), length: tr * 0.1, width: tr * 0.022, angle: mid),
                      RGB(0xFFEAC0, alpha: 0.2 + 0.55 * lit), blur: 6)
        }
    }
    // Crème pâtissière inside the shell.
    let creamR = tr * 0.87
    shade(ctx, ellipsePath(c, creamR), [RGB(0xFFF4CC), RGB(0xF8E2A2), RGB(0xE8C77E)], light: CGPoint(x: -0.25, y: -0.3))
    clipped(ctx, ellipsePath(c, creamR)) {
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: RGB(0x6A4010, alpha: 0.4).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(30)
        ctx.strokeEllipse(in: circle(c, creamR + 15))
    }

    // Fruit, from the outside in: raspberries, strawberry halves, figs in the middle, blueberries in between.
    let rasp = 17
    for k in 0..<rasp {
        let a = CGFloat(k) / CGFloat(rasp) * .pi * 2 + deg(5)
        bRaspberry(ctx, pt(c, a, creamR * 0.8), 40, seed: UInt64(k + 1))
    }
    // Strawberry halves overlap like scales, tips out.
    let berries = 13
    for k in 0..<berries {
        let a = CGFloat(k) / CGFloat(berries) * .pi * 2 + deg(-80)
        bStrawberryHalf(ctx, pt(c, a, creamR * 0.5), 118, angle: a)
    }
    for k in 0..<8 {
        let a = (CGFloat(k) + 0.5) / 8 * .pi * 2
        bBlueberry(ctx, pt(c, a, creamR * 0.24), 24, angle: CGFloat(k))
    }
    // One fig half at the centre.
    bFigHalf(ctx, CGPoint(x: c.x + 4, y: c.y + 6), 128, angle: deg(-60), seed: 7)
    // Mint on top, glaze glints over all of it.
    bMintLeaf(ctx, CGPoint(x: c.x - 44, y: c.y - 40), length: 70, angle: deg(-150))
    bMintLeaf(ctx, CGPoint(x: c.x - 20, y: c.y - 62), length: 58, angle: deg(-100))
    clipped(ctx, ellipsePath(c, creamR)) {
        let hl = CGPoint(x: c.x - tr * 0.45, y: c.y - tr * 0.5)
        ctx.drawRadialGradient(gradient([RGB(0xFFFFFF, alpha: 0.18), RGB(0xFFFFFF, alpha: 0)]), startCenter: hl, startRadius: 0,
                               endCenter: hl, endRadius: tr * 0.7, options: [])
    }
}

// MARK: - 5. Candlelight

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

// MARK: - 8. Sunday brunch

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


// MARK: - Proposals C

let proposalsC: [Proposal] = [
    Proposal(number: 6, slug: "wood-fired", label: "Wood-fired", draw: cDrawWoodFired),
    Proposal(number: 7, slug: "night-market", label: "Night Market", draw: cDrawNightMarket),
]

// MARK: - 6. Wood-fired

/// Night ground: dark blue-charcoal, a touch lighter at the top. Nothing in tinted.
func cNightGround(_ ctx: CGContext, top: RGB, bottom: RGB, darkTop: RGB, darkBottom: RGB) {
    if appearance == .tinted { return }
    let (t, b) = appearance == .dark ? (darkTop, darkBottom) : (top, bottom)
    ctx.drawLinearGradient(gradient([t, b]), start: .zero, end: CGPoint(x: 0, y: size), options: [])
    var rng = SeededRandom(77)
    for _ in 0..<9000 {
        let p = CGPoint(x: rng.next() * size, y: rng.next() * size)
        ctx.setFillColor((rng.next() > 0.5 ? RGB(0xFFFFFF) : RGB(0x000000)).with(alpha: 0.03 * rng.next()).cg)
        ctx.fillEllipse(in: circle(p, 0.8 + rng.next() * 1.4))
    }
}

/// Upper half of an ellipse from the left to the right end, as a polyline (y down: the top is negative sin).
func cArch(_ path: CGMutablePath, center c: CGPoint, rx: CGFloat, ry: CGFloat, reverse: Bool = false) {
    let steps = 90
    for k in 0...steps {
        let t = CGFloat(reverse ? steps - k : k) / CGFloat(steps)
        let a = CGFloat.pi + t * .pi
        path.addLine(to: CGPoint(x: c.x + cos(a) * rx, y: c.y + sin(a) * ry))
    }
}

/// Mosaic-clad dome; false gives plain clay plaster.
var cMosaicDome = true

func cDrawWoodFired(_ ctx: CGContext) {
    cNightGround(ctx, top: RGB(0x1E2638), bottom: RGB(0x0D1018), darkTop: RGB(0x121725), darkBottom: RGB(0x06080C))
    let dim: CGFloat = appearance == .dark ? 0.82 : 1

    let mouthC = CGPoint(x: 512, y: 610)       // centre of the arch's half circle
    let mouthR: CGFloat = 205                   // inside of the arch
    let ringR: CGFloat = 288                    // outside of the voussoirs
    let floorY: CGFloat = 800                   // hearth / oven floor level

    // Warm halo of firelight around the oven, behind everything.
    glow(ctx, CGPoint(x: 512, y: 700), 560, RGB(0xFF8A3A), 0.22 * dim)

    // Dome: clay plaster, lit from the mouth below.
    let dome = CGMutablePath()
    dome.move(to: CGPoint(x: 92, y: floorY))
    dome.addLine(to: CGPoint(x: 92, y: 610))
    cArch(dome, center: CGPoint(x: 512, y: 610), rx: 420, ry: 440)
    dome.addLine(to: CGPoint(x: 932, y: floorY))
    dome.closeSubpath()
    withShadow(ctx, dy: 0, blur: 40, RGB(0x000000, alpha: 0.5)) { fill(ctx, dome, RGB(0x5A2E1E)) }
    let plaster = textureImage { x, y in
        let n = Noise(seed: 5).fbm(x * 0.012, y * 0.012, octaves: 5)
        let m = Noise(seed: 9).fbm(x * 0.05, y * 0.05, octaves: 3)
        let t = n * 0.75 + m * 0.25
        return (0.36 + t * 0.12, 0.19 + t * 0.07, 0.12 + t * 0.04, 1)
    }
    // Neapolitan ovens are often clad in mosaic: here small gold-leaf glass tiles, each catching the fire differently.
    let tintedMosaic = appearance == .tinted   // tinted stretches contrast: keep the tiles calm there
    let mosaic = textureImage { x, y in
        let tile: Float = 16
        let row = floor(y / tile)
        let ox = x + (Int(row) % 2 == 0 ? 0 : tile / 2)
        let col = floor(ox / tile)
        let fx = ox - col * tile, fy = y - row * tile
        let edge = min(min(fx, tile - fx), min(fy, tile - fy))
        var h = UInt32(bitPattern: Int32(col)) &* 374761393 &+ UInt32(bitPattern: Int32(row)) &* 668265263
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        let pick = Float(h & 0xFF) / 255, gloss = Float((h >> 8) & 0xFF) / 255
        // Grout.
        // Large-scale light: the fire lights the dome near the arch; it fades towards the top and the flanks.
        let dx = (x - 512) / 470, dy = (y - 780) / 560
        let lit = max(0.32, 1.4 - sqrt(dx * dx + dy * dy) * 0.8)
        // Gold leaf glass tiles; a few warmer, a few paler. Low tile-to-tile contrast, so it reads as one surface.
        var rgb: (Float, Float, Float) = (0.74, 0.54, 0.24)
        if pick < 0.2 { rgb = (0.78, 0.52, 0.22) } else if pick > 0.85 { rgb = (0.80, 0.62, 0.32) }
        // Each tile sits at a slightly different angle, so each catches a slightly different amount of light.
        var k: Float = (0.86 + gloss * 0.2 + (fy < 2 ? 0.06 : 0)) * lit
        if gloss > 0.996 && lit > 0.6 { k = 1.4 }   // the very odd tile flashes
        if tintedMosaic { k = 0.75 * lit + (k - 0.75 * lit) * 0.5 }
        if edge < 1.2 { k *= 0.55 }                 // grout, a darker version of the tile

        return (rgb.0 * k, rgb.1 * k, rgb.2 * k, 1)
    }
    clipped(ctx, dome) {
        drawTexture(ctx, cMosaicDome ? mosaic : plaster)
        // The dome is round: its flanks turn away from the light.
        ctx.drawLinearGradient(gradient([RGB(0x05070C, alpha: 0.6), RGB(0x05070C, alpha: 0), RGB(0x05070C, alpha: 0), RGB(0x05070C, alpha: 0.6)],
                                        [0, 0.3, 0.7, 1]), start: CGPoint(x: 92, y: 0), end: CGPoint(x: 932, y: 0), options: [])
        // Firelight: strong on the lower face around the mouth, falling off to a cool dark top.
        let fc = CGPoint(x: 512, y: 760)
        let warm: CGFloat = cMosaicDome ? 0.45 : 0.75
        ctx.drawRadialGradient(gradient([RGB(0xFF9A4A, alpha: warm * dim), RGB(0xE0662A, alpha: warm * 0.45 * dim), RGB(0xE0662A, alpha: 0)], [0, 0.45, 1]),
                               startCenter: fc, startRadius: 0, endCenter: fc, endRadius: 560, options: [])
        // Cool night rim light along the top of the dome.
        ctx.drawLinearGradient(gradient([RGB(0x0A0E18, alpha: 0.55), RGB(0x0A0E18, alpha: 0)]), start: CGPoint(x: 0, y: 170),
                               end: CGPoint(x: 0, y: 470), options: [])
        ctx.setStrokeColor(RGB(0x8AA0C8, alpha: 0.22).cg)
        ctx.setLineWidth(5)
        let rim = CGMutablePath()
        rim.move(to: CGPoint(x: 96, y: 610))
        cArch(rim, center: CGPoint(x: 512, y: 610), rx: 416, ry: 436)
        ctx.addPath(rim)
        ctx.strokePath()
    }

    // Voussoirs: a ring of bricks around the arch, plus jamb bricks down the sides.
    let mortar = RGB(0x2A140C)
    let ring = CGMutablePath()
    ring.move(to: CGPoint(x: mouthC.x - ringR, y: floorY))
    ring.addLine(to: CGPoint(x: mouthC.x - ringR, y: mouthC.y))
    cArch(ring, center: mouthC, rx: ringR, ry: ringR)
    ring.addLine(to: CGPoint(x: mouthC.x + ringR, y: floorY))
    ring.closeSubpath()
    withShadow(ctx, dy: 6, blur: 18, RGB(0x000000, alpha: 0.45)) { fill(ctx, ring, mortar) }
    let brickTones = [RGB(0xB0532C), RGB(0x9A4424), RGB(0xC2643A), RGB(0x8A3A1E), RGB(0xA84E2A)]
    var rng = SeededRandom(61)
    let gap: CGFloat = 5
    func brick(_ path: CGPath, inner: CGPoint, outer: CGPoint, tone: RGB) {
        // Lit from the fire: bright at the edge facing the opening.
        clipped(ctx, path) {
            ctx.drawLinearGradient(gradient([tone.mixed(with: RGB(0xFFB070), 0.4 * dim), tone.mixed(with: RGB(0x000000), 0.1 + (1 - dim)),
                                             tone.mixed(with: RGB(0x1A0A04), 0.55)], [0, 0.45, 1]),
                                   start: inner, end: outer, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            // Fine clay pitting.
            for _ in 0..<26 {
                let b = path.boundingBox
                let p = CGPoint(x: b.minX + rng.next() * b.width, y: b.minY + rng.next() * b.height)
                ctx.setFillColor(RGB(0x000000, alpha: 0.12 * rng.next()).cg)
                ctx.fillEllipse(in: circle(p, 1 + rng.next() * 2.5))
            }
        }
    }
    // Arch bricks (13 wedges over the half circle).
    let n = 13
    for i in 0..<n {
        let a0 = CGFloat.pi + CGFloat(i) / CGFloat(n) * .pi
        let a1 = CGFloat.pi + CGFloat(i + 1) / CGFloat(n) * .pi
        let ga = gap / mouthR
        let gb = gap / ringR
        let p = CGMutablePath()
        p.move(to: pt(mouthC, a0 + ga, mouthR + gap))
        p.addArc(center: mouthC, radius: mouthR + gap, startAngle: a0 + ga, endAngle: a1 - ga, clockwise: false)
        p.addLine(to: pt(mouthC, a1 - gb, ringR - gap))
        p.addArc(center: mouthC, radius: ringR - gap, startAngle: a1 - gb, endAngle: a0 + gb, clockwise: true)
        p.closeSubpath()
        let mid = (a0 + a1) / 2
        brick(p, inner: pt(mouthC, mid, mouthR), outer: pt(mouthC, mid, ringR), tone: brickTones[i % brickTones.count])
    }
    // Jambs: two columns of stacked bricks from the springing line down to the floor.
    for side: CGFloat in [-1, 1] {
        let rows = 2
        let h = (floorY - mouthC.y) / CGFloat(rows)
        for r in 0..<rows {
            let y0 = mouthC.y + CGFloat(r) * h
            let xIn = mouthC.x + side * (mouthR + gap)
            let xOut = mouthC.x + side * (ringR - gap)
            let rect = CGRect(x: min(xIn, xOut), y: y0 + gap, width: abs(xOut - xIn), height: h - gap * 2)
            let p = CGPath(rect: rect, transform: nil)
            brick(p, inner: CGPoint(x: xIn, y: rect.midY), outer: CGPoint(x: xOut, y: rect.midY), tone: brickTones[(r + (side > 0 ? 2 : 0)) % brickTones.count])
        }
    }

    // The mouth: a glowing chamber.
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: mouthC.x - mouthR, y: floorY))
    mouth.addLine(to: CGPoint(x: mouthC.x - mouthR, y: mouthC.y))
    cArch(mouth, center: mouthC, rx: mouthR, ry: mouthR)
    mouth.addLine(to: CGPoint(x: mouthC.x + mouthR, y: floorY))
    mouth.closeSubpath()
    clipped(ctx, mouth) {
        // Back wall: deep ember red at the top, glowing towards the floor.
        ctx.drawLinearGradient(gradient([RGB(0x2A0C05), RGB(0x6A1E08), RGB(0xC2470F), RGB(0xF08A2A)], [0, 0.35, 0.75, 1]),
                               start: CGPoint(x: 0, y: mouthC.y - mouthR), end: CGPoint(x: 0, y: floorY), options: [])
        // The fire at the back left: a bright heart and tongues of flame licking up the dome.
        let fire = CGPoint(x: mouthC.x - 95, y: 735)
        glow(ctx, fire, 300, RGB(0xFFB24A), 0.95)
        glow(ctx, fire, 140, RGB(0xFFE7A8), 0.9)
        // Three layers of flame tongues: deep orange at the back, orange, then small hot yellow ones in front.
        let layers: [([RGB], CGFloat, [(CGFloat, CGFloat, CGFloat, CGFloat)])] = [   // colours, blur, (x offset, height, half width, lean)
            ([RGB(0xFF8A2A), RGB(0xE0561A, alpha: 0.85), RGB(0xA02A0A, alpha: 0)], 34,
             [(-95, 230, 70, -0.15), (-20, 330, 80, 0.06), (60, 260, 66, 0.22), (-150, 160, 50, -0.25)]),
            ([RGB(0xFFD27A), RGB(0xFF9A30, alpha: 0.9), RGB(0xE0561A, alpha: 0)], 24,
             [(-70, 190, 48, -0.10), (-25, 270, 56, 0.05), (25, 215, 50, 0.18), (70, 150, 38, 0.3), (-120, 120, 34, -0.2)]),
            ([RGB(0xFFFBEA), RGB(0xFFE08A, alpha: 0.95), RGB(0xFFB040, alpha: 0)], 14,
             [(-60, 120, 32, -0.05), (-15, 165, 36, 0.08), (30, 110, 28, 0.2)]),
        ]
        for (colors, blur, tongues) in layers {
            for f in tongues {
                let base = CGPoint(x: fire.x + f.0, y: 772)
                let tip = CGPoint(x: base.x + f.3 * f.1 + 14, y: base.y - f.1)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: base.x - f.2, y: base.y))
                p.addCurve(to: tip, control1: CGPoint(x: base.x - f.2 * 1.1, y: base.y - f.1 * 0.5),
                           control2: CGPoint(x: tip.x - f.2 * 0.5, y: tip.y + f.1 * 0.4))
                p.addCurve(to: CGPoint(x: base.x + f.2, y: base.y), control1: CGPoint(x: tip.x + f.2 * 0.15, y: tip.y + f.1 * 0.5),
                           control2: CGPoint(x: base.x + f.2 * 1.05, y: base.y - f.1 * 0.4))
                p.closeSubpath()
                // Soft edges: each tongue sits in a layer whose shadow is its own blurred glow.
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: blur, color: colors[1].cg)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                clipped(ctx, p) {
                    ctx.drawLinearGradient(gradient(colors, [0, 0.45, 1]), start: base, end: tip, options: [])
                }
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            }
        }
        // Oven floor: hot stone in perspective, catching the fire.
        let floorRect = CGRect(x: 0, y: 748, width: size, height: floorY - 748)
        clipped(ctx, CGPath(rect: floorRect, transform: nil)) {
            ctx.drawLinearGradient(gradient([RGB(0x7A2E0E), RGB(0xB0521C), RGB(0x8A3A14)], [0, 0.5, 1]),
                                   start: CGPoint(x: 0, y: floorRect.minY), end: CGPoint(x: 0, y: floorRect.maxY), options: [])
            glow(ctx, CGPoint(x: fire.x, y: 770), 260, RGB(0xFFC060), 0.8)
        }
        // The hot heart of the fire, white-yellow, right where the wood burns.
        ctx.saveGState()
        ctx.translateBy(x: fire.x - 20, y: 768)
        ctx.scaleBy(x: 1, y: 0.55)
        glow(ctx, .zero, 150, RGB(0xFFF6D8), 1)
        ctx.restoreGState()
        // Wood logs and embers on the floor at the back.
        for l in [(CGPoint(x: fire.x - 30, y: 772), CGFloat(-0.12)), (CGPoint(x: fire.x + 40, y: 776), CGFloat(0.1))] {
            let log = roundedRect(l.0, w: 170, h: 30, r: 15, angle: l.1)
            fill(ctx, log, RGB(0x1A0A04))
            clipped(ctx, log) {
                // Charred on top, glowing cracks underneath.
                ctx.drawLinearGradient(gradient([RGB(0x3A1A0A), RGB(0x1A0A04), RGB(0xFF8A2A)], [0, 0.55, 1]), start: CGPoint(x: 0, y: l.0.y - 15),
                                       end: CGPoint(x: 0, y: l.0.y + 15), options: [])
                ctx.setStrokeColor(RGB(0xFFA040, alpha: 0.8).cg)
                ctx.setLineWidth(2)
                for j in 0..<5 {
                    let x = l.0.x - 60 + CGFloat(j) * 28
                    ctx.move(to: CGPoint(x: x, y: l.0.y + 14)); ctx.addLine(to: CGPoint(x: x + 6, y: l.0.y - 2))
                }
                ctx.strokePath()
            }
        }
        var er = SeededRandom(14)
        for _ in 0..<60 {
            let p = CGPoint(x: fire.x + er.range(-120, 140), y: er.range(778, 798))
            ctx.setFillColor((er.next() > 0.5 ? RGB(0xFFD27A) : RGB(0xFF7A26)).with(alpha: er.range(0.5, 1)).cg)
            ctx.fillEllipse(in: circle(p, er.range(1.5, 4.5)))
        }
        // The pizza baking on the floor, front right: low front-on view, so the near cornicione is a thick puffy
        // band and the far one a thin lip behind the top.
        let pc = CGPoint(x: mouthC.x + 38, y: 756)
        let prx: CGFloat = 172, pry: CGFloat = 40
        let pizzaOuter = CGPath(ellipseIn: CGRect(x: pc.x - prx, y: pc.y - pry, width: prx * 2, height: pry * 2), transform: nil)
        withShadow(ctx, dy: 5, blur: 12, RGB(0x1A0500, alpha: 0.7)) { fill(ctx, pizzaOuter, RGB(0xD9944A)) }
        clipped(ctx, pizzaOuter) {
            ctx.drawLinearGradient(gradient([RGB(0xFFE6B0), RGB(0xF2B868), RGB(0xC27A36), RGB(0x7A4018)], [0, 0.35, 0.75, 1]),
                                   start: CGPoint(x: 0, y: pc.y - pry), end: CGPoint(x: 0, y: pc.y + pry), options: [])
        }
        // Top: sauce and mozzarella, set back inside the rim.
        let topC = CGPoint(x: pc.x + 4, y: pc.y - pry * 0.24)
        let top = CGPath(ellipseIn: CGRect(x: topC.x - prx * 0.8, y: topC.y - pry * 0.5, width: prx * 1.6, height: pry * 0.92), transform: nil)
        withShadow(ctx, dy: -2, blur: 6, RGB(0x5A2008, alpha: 0.5)) { fill(ctx, top, RGB(0xC8361A)) }
        clipped(ctx, top) {
            ctx.drawLinearGradient(gradient([RGB(0x8E1E0C), RGB(0xD8401E), RGB(0xE85A2A)]), start: CGPoint(x: 0, y: topC.y - pry * 0.5),
                                   end: CGPoint(x: 0, y: topC.y + pry * 0.45), options: [])
            for (dx, dy, w) in [(-92.0, 2.0, 46.0), (-20.0, -6.0, 40.0), (50.0, 3.0, 48.0), (105.0, -5.0, 34.0)] as [(CGFloat, CGFloat, CGFloat)] {
                let m = CGPath(ellipseIn: CGRect(x: topC.x + dx - w / 2, y: topC.y + dy - 7, width: w, height: 15), transform: nil)
                fill(ctx, m, RGB(0xFFF6E2))
                clipped(ctx, m) { ctx.setFillColor(RGB(0xE8C890, alpha: 0.6).cg); ctx.fill(CGRect(x: topC.x + dx - w, y: topC.y + dy + 3, width: w * 2, height: 6)) }
            }
            for (dx, dy, a) in [(-55.0, -4.0, 0.4), (14.0, 5.0, -0.5), (82.0, -6.0, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
                fill(ctx, leafPath(CGPoint(x: topC.x + dx, y: topC.y + dy), length: 26, width: 9, angle: a), RGB(0x2F7A2E))
            }
        }
        // Puff of the near rim: a lit crown just in front of the top.
        clipped(ctx, pizzaOuter) {
            ctx.setStrokeColor(RGB(0xFFF2CC, alpha: 0.55).cg)
            ctx.setLineWidth(5)
            ctx.addEllipse(in: CGRect(x: topC.x - prx * 0.84, y: topC.y - pry * 0.5, width: prx * 1.68, height: pry * 1.3))
            ctx.strokePath()
        }
        // Leopard char: soft dark blisters, mostly on the near rim.
        clippedEO(ctx, { let p = CGMutablePath(); p.addPath(pizzaOuter); p.addPath(top); return p }()) {
            var lr = SeededRandom(3)
            for _ in 0..<20 {
                let a = lr.range(0.15, 0.85) * .pi + (lr.next() > 0.8 ? .pi : 0)
                let p = CGPoint(x: pc.x + cos(a) * prx * lr.range(0.8, 0.96), y: pc.y + sin(a) * pry * lr.range(0.35, 0.8))
                let blister = blobPath(p, lr.range(3, 6), jitter: 0.3, points: 6, seed: UInt64(p.x), stretch: 1.6, angle: 0)
                withShadow(ctx, dy: 0, blur: 5, RGB(0x2A0E04, alpha: 0.5)) { fill(ctx, blister, RGB(0x3A1A08, alpha: 0.7)) }
            }
        }
        // Firelight on the pizza's near rim from the left.
        clipped(ctx, pizzaOuter) { glow(ctx, CGPoint(x: pc.x - prx, y: pc.y), 180, RGB(0xFFC070), 0.5) }

        // Soot shadow at the crown of the chamber and inner rim darkening.
        let crown = CGPoint(x: mouthC.x, y: mouthC.y - mouthR)
        ctx.drawRadialGradient(gradient([RGB(0x0A0200, alpha: 0.6), RGB(0x0A0200, alpha: 0)]), startCenter: crown, startRadius: 0,
                               endCenter: crown, endRadius: 220, options: [])
    }
    // Lip shadow: the arch casts a thin dark line just inside.
    clipped(ctx, mouth) {
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: RGB(0x000000, alpha: 0.55).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(16)
        ctx.addPath(mouth)
        ctx.strokePath()
    }

    // Hearth: a stone slab across the front, lit at its top edge by the fire.
    let slab = CGRect(x: 70, y: floorY, width: 884, height: 74)
    withShadow(ctx, dy: 18, blur: 30, RGB(0x000000, alpha: 0.6)) { fill(ctx, CGPath(rect: slab, transform: nil), RGB(0x3A3430)) }
    let stone = textureImage(width: Int(slab.width), height: Int(slab.height)) { x, y in
        let t = Noise(seed: 21).fbm(x * 0.03, y * 0.08, octaves: 4)
        return (0.25 + t * 0.12, 0.23 + t * 0.1, 0.22 + t * 0.09, 1)
    }
    drawTexture(ctx, stone, in: slab)
    clipped(ctx, CGPath(rect: slab, transform: nil)) {
        let lip = CGPoint(x: 512, y: floorY)
        ctx.drawRadialGradient(gradient([RGB(0xFFA050, alpha: 0.8 * dim), RGB(0xE06A2A, alpha: 0.3 * dim), RGB(0xE06A2A, alpha: 0)], [0, 0.4, 1]),
                               startCenter: lip, startRadius: 0, endCenter: lip, endRadius: 380, options: [])
        ctx.setFillColor(RGB(0xFFD9A0, alpha: 0.35 * dim).cg)
        ctx.fill(CGRect(x: slab.minX, y: slab.minY, width: slab.width, height: 4))
        ctx.drawLinearGradient(gradient([RGB(0x000000, alpha: 0), RGB(0x000000, alpha: 0.35)]), start: CGPoint(x: 0, y: slab.minY + 10),
                               end: CGPoint(x: 0, y: slab.maxY), options: [])
        // Firelight spilling over the front face, warmest in the middle.
        ctx.saveGState()
        ctx.translateBy(x: 512, y: slab.minY + 20)
        ctx.scaleBy(x: 1, y: 0.22)
        glow(ctx, .zero, 420, RGB(0xFF9A50), 0.55 * dim)
        ctx.restoreGState()
        ctx.setFillColor(RGB(0xC07040, alpha: 0.12 * dim).cg)
        ctx.fill(slab)
    }

    // A few sparks drifting up out of the mouth.
    for (p, r) in [(CGPoint(x: 548, y: 286), CGFloat(3.5)), (CGPoint(x: 590, y: 232), CGFloat(2.5)), (CGPoint(x: 520, y: 190), CGFloat(2)),
                   (CGPoint(x: 470, y: 300), CGFloat(2.5))] {
        glow(ctx, p, r * 5, RGB(0xFFB050), 0.5)
        ctx.setFillColor(RGB(0xFFE2A0).cg)
        ctx.fillEllipse(in: circle(p, r))
    }
}

// MARK: - 7. Night Market

func cDrawNightMarket(_ ctx: CGContext) {
    // Deep lacquer-red table, lit by a lantern somewhere above at the upper left.
    if appearance != .tinted {
        let (inner, outer) = appearance == .dark ? (RGB(0x5A120C), RGB(0x1A0403)) : (RGB(0x8E1E14), RGB(0x3E0806))
        ctx.setFillColor(outer.cg)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let lc = CGPoint(x: size * 0.3, y: size * 0.22)
        ctx.drawRadialGradient(gradient([inner, outer]), startCenter: lc, startRadius: 0, endCenter: lc, endRadius: size * 1.05,
                               options: [.drawsAfterEndLocation])
        // Lacquer sheen: a long soft reflection of the lantern.
        glint(ctx, CGPoint(x: 210, y: 150), w: 520, h: 150, angle: deg(-28), alpha: appearance == .dark ? 0.08 : 0.12)
        // Bokeh: out-of-focus lantern lights reflected in the corners.
        var br = SeededRandom(41)
        let spots: [(CGPoint, CGFloat)] = [(CGPoint(x: 110, y: 120), 70), (CGPoint(x: 945, y: 120), 56), (CGPoint(x: 70, y: 930), 50)]
        for (p, r) in spots {
            let a = (appearance == .dark ? 0.1 : 0.14) * br.range(0.7, 1)
            ctx.drawRadialGradient(gradient([RGB(0xFFC070, alpha: a), RGB(0xFFB45A, alpha: a * 0.7), RGB(0xFFB45A, alpha: 0)], [0, 0.55, 1]),
                                   startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
        }
        var rng = SeededRandom(99)
        for _ in 0..<9000 {
            let p = CGPoint(x: rng.next() * size, y: rng.next() * size)
            ctx.setFillColor((rng.next() > 0.5 ? RGB(0xFFFFFF) : RGB(0x000000)).with(alpha: 0.03 * rng.next()).cg)
            ctx.fillEllipse(in: circle(p, 0.8 + rng.next() * 1.4))
        }
    }

    let c = CGPoint(x: 498, y: 520)
    let r: CGFloat = 418          // outside of the bamboo hoop
    let lip: CGFloat = 46         // width of the top edge of the hoop
    let ri = r - lip

    // Steamer: hoop with cast shadow.
    withShadow(ctx, dy: 26, blur: 46, RGB(0x1A0000, alpha: 0.6)) { fill(ctx, ellipsePath(c, r), RGB(0xC8A66A)) }
    cBambooHoop(ctx, c, outer: r, inner: ri)

    // Inner wall of the hoop: woven bamboo, in shade at the upper left, catching the lantern at the lower right.
    let liner = ri - 24
    clippedEO(ctx, ringPath(c, outer: ri, inner: liner)) {
        fill(ctx, ellipsePath(c, ri), RGB(0x9A7440))
        ctx.setLineWidth(3)
        for k in 0..<220 {
            let a = CGFloat(k) / 220 * .pi * 2
            ctx.setStrokeColor((k % 2 == 0 ? RGB(0x6A4A20) : RGB(0xC8A060)).with(alpha: 0.5).cg)
            ctx.move(to: pt(c, a, liner)); ctx.addLine(to: pt(c, a + 0.01, ri))
            ctx.strokePath()
        }
        ctx.drawLinearGradient(gradient([RGB(0x2A1404, alpha: 0.75), RGB(0x2A1404, alpha: 0.2), RGB(0xFFE0A8, alpha: 0.25)], [0, 0.55, 1]),
                               start: pt(c, deg(-135), ri), end: pt(c, deg(45), ri), options: [])
    }

    // Inside: parchment liner on bamboo slats.
    clipped(ctx, ellipsePath(c, liner)) {
        fill(ctx, ellipsePath(c, liner), RGB(0xEADCBE))
        // Slats show faintly through the paper.
        ctx.setStrokeColor(RGB(0xB89A64, alpha: 0.1).cg)
        ctx.setLineWidth(22)
        var x = c.x - liner
        while x < c.x + liner { ctx.move(to: CGPoint(x: x, y: c.y - liner)); ctx.addLine(to: CGPoint(x: x, y: c.y + liner)); x += 58 }
        ctx.strokePath()
        // Holes punched in rings.
        for ringIndex in 1...6 {
            let d = CGFloat(ringIndex) * 58
            let count = Int(d * 2 * .pi / 60)
            for k in 0..<count {
                let a = CGFloat(k) / CGFloat(count) * .pi * 2 + CGFloat(ringIndex) * 0.3
                let p = pt(c, a, d)
                ctx.setFillColor(RGB(0x7A5A2A, alpha: 0.45).cg)
                ctx.fillEllipse(in: circle(p, 6))
                ctx.setFillColor(RGB(0xFFFFFF, alpha: 0.25).cg)
                ctx.fillEllipse(in: circle(CGPoint(x: p.x + 1.5, y: p.y + 2), 4))
            }
        }
        // The hoop's far wall throws shadow, the lantern light from the upper left.
        ctx.setShadow(offset: CGSize(width: 12, height: -18), blur: 34, color: RGB(0x3A1A00, alpha: 0.6).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(40)
        ctx.strokeEllipse(in: circle(c, liner + 20))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.drawLinearGradient(gradient([RGB(0x3A1A00, alpha: 0.18), RGB(0x3A1A00, alpha: 0), RGB(0xFFF6E0, alpha: 0.12)], [0, 0.5, 1]),
                               start: pt(c, deg(-135), liner), end: pt(c, deg(45), liner), options: [])
        // Soft ambient occlusion all round where the paper meets the wall.
        ctx.drawRadialGradient(gradient([RGB(0x4A2A08, alpha: 0), RGB(0x4A2A08, alpha: 0.28)], [0.82, 1]), startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: liner, options: [])
    }

    // Dumplings: six round a seventh.
    var spots = [(c, CGFloat(-0.3))]
    for k in 0..<6 {
        let a = deg(-90) + CGFloat(k) * .pi / 3 + 0.12
        spots.append((pt(c, a, 222), a))
    }
    for (i, s) in spots.enumerated() {
        cDumpling(ctx, s.0, 104, seed: UInt64(i + 1), twist: s.1)
    }

    // Chopsticks resting across the lower right of the hoop.
    cChopsticks(ctx)
}

/// Top edge of a bent-bamboo hoop: two laminated strips, fibres along the ring, and rattan lashings.
func cBambooHoop(_ ctx: CGContext, _ c: CGPoint, outer r: CGFloat, inner ri: CGFloat) {
    let ring = ringPath(c, outer: r, inner: ri)
    let bamboo = textureImage { x, y in
        let dx = x - Float(c.x), dy = y - Float(c.y)
        let d = sqrt(dx * dx + dy * dy)
        let a = atan2(dy, dx)
        // Fibres run along the ring: noise stretched along the angle.
        let f = Noise(seed: 31).fbm(a * 260, d * 0.9, octaves: 3)
        let band = Noise(seed: 37).fbm(a * 6, d * 0.03, octaves: 2)
        let t = f * 0.55 + band * 0.45
        return (0.80 + t * 0.14, 0.64 + t * 0.12, 0.38 + t * 0.10, 1)
    }
    clippedEO(ctx, ring) {
        drawTexture(ctx, bamboo)
        // Seam between the two strips.
        ctx.setStrokeColor(RGB(0x6A4A1E, alpha: 0.55).cg)
        ctx.setLineWidth(2.5)
        ctx.strokeEllipse(in: circle(c, (r + ri) / 2 + 3))
        // Rounded edges: dark at the outside and inside, light along the crown, lantern from the upper left.
        ctx.drawRadialGradient(gradient([RGB(0x2A1404, alpha: 0.5), RGB(0x2A1404, alpha: 0), RGB(0x2A1404, alpha: 0), RGB(0x2A1404, alpha: 0.55)],
                                        [0, 0.25, 0.7, 1]),
                               startCenter: c, startRadius: ri, endCenter: c, endRadius: r, options: [])
        let hl = pt(c, deg(-135), r * 0.4)
        ctx.drawRadialGradient(gradient([RGB(0xFFE8B8, alpha: 0.45), RGB(0xFFE8B8, alpha: 0)]), startCenter: hl, startRadius: 0,
                               endCenter: hl, endRadius: r * 1.1, options: [])
        ctx.drawLinearGradient(gradient([RGB(0x000000, alpha: 0), RGB(0x1A0800, alpha: 0.35)]), start: pt(c, deg(-135), r),
                               end: pt(c, deg(45), r), options: [])
    }
    // Rattan lashings: wraps across the hoop at the strip ends.
    for a in [deg(-62), deg(58), deg(178)] {
        let wraps = 6
        for w in 0..<wraps {
            let aa = a + (CGFloat(w) - CGFloat(wraps - 1) / 2) * (13 / r)
            let p0 = pt(c, aa, ri - 3), p1 = pt(c, aa + 0.012, r + 3)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(RGB(0x5A3410).cg)
            ctx.setLineWidth(12)
            ctx.move(to: p0); ctx.addLine(to: p1); ctx.strokePath()
            ctx.setStrokeColor(RGB(0xB07A38).cg)
            ctx.setLineWidth(8)
            ctx.move(to: p0); ctx.addLine(to: p1); ctx.strokePath()
            ctx.setStrokeColor(RGB(0xF0C890, alpha: 0.7).cg)
            ctx.setLineWidth(2.5)
            ctx.move(to: pt(p0, aa + .pi / 2, -2)); ctx.addLine(to: pt(p1, aa + .pi / 2, -2)); ctx.strokePath()
        }
    }
}

/// Xiao long bao from above: a soft, glossy, slightly translucent parcel with pleats swirling to a knot.
func cDumpling(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, seed: UInt64, twist: CGFloat) {
    let body = blobPath(c, r, jitter: 0.035, points: 12, seed: seed &+ 200)
    withShadow(ctx, dy: r * 0.1, blur: r * 0.22, RGB(0x4A2A00, alpha: 0.5)) { fill(ctx, body, RGB(0xF0DCC0)) }
    let knot = CGPoint(x: c.x - r * 0.06, y: c.y - r * 0.1)
    clipped(ctx, body) {
        // Thin wrapper over soup: warm translucent belly, lighter crown.
        ctx.drawRadialGradient(gradient([RGB(0xFFF8EC), RGB(0xF8E6CC), RGB(0xEAC79C), RGB(0xD2A472)], [0, 0.35, 0.75, 1]),
                               startCenter: knot, startRadius: 0, endCenter: c, endRadius: r * 1.05, options: [.drawsAfterEndLocation])
        // Filling and soup showing through the thin wrapper near the base: a warm, darker band inside the edge.
        ctx.drawRadialGradient(gradient([RGB(0xB8743E, alpha: 0), RGB(0xB8743E, alpha: 0.3), RGB(0xB8743E, alpha: 0.12)], [0.5, 0.8, 0.94]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        glow(ctx, pt(c, deg(40), r * 0.55), r * 0.6, RGB(0xE89060), 0.25)
        // Lower body turns away from the light.
        let away = pt(c, deg(45), r * 0.9)
        ctx.drawRadialGradient(gradient([RGB(0x8A5A2A, alpha: 0.3), RGB(0x8A5A2A, alpha: 0)]), startCenter: away, startRadius: 0,
                               endCenter: away, endRadius: r * 0.9, options: [])
        // Pleats: tapering folds swirling into the knot, soft-edged. Each fold is a shadow crescent with a lit crest beside it.
        let n = 12
        var rng = SeededRandom(seed)
        func fold(_ a: CGFloat, _ reach: CGFloat, width w: CGFloat) -> CGPath {
            let start = pt(c, a, r * reach)
            let end = pt(knot, a + 0.45, r * 0.08)
            let ctrl = pt(c, a + 0.3, r * reach * 0.55)
            let p = CGMutablePath()
            p.move(to: end)
            p.addQuadCurve(to: pt(start, a + .pi / 2, w), control: pt(ctrl, a + .pi / 2, w * 0.9))
            p.addQuadCurve(to: pt(start, a - .pi / 2, w * 0.3), control: pt(start, a, w * 1.2))
            p.addQuadCurve(to: end, control: pt(ctrl, a - .pi / 2, w * 0.1))
            p.closeSubpath()
            return p
        }
        for k in 0..<n {
            let a = twist + CGFloat(k) / CGFloat(n) * .pi * 2 + rng.range(-0.05, 0.05)
            let reach = rng.range(0.4, 0.74)
            let w = r * rng.range(0.04, 0.06)
            let shadowFold = fold(a, reach, width: w)
            withShadow(ctx, dy: 0, blur: r * 0.07, RGB(0x8A6436, alpha: 0.25)) { fill(ctx, shadowFold, RGB(0x9A7448, alpha: 0.16)) }
            let crest = fold(a - 0.09, reach * 0.94, width: w * 0.55)
            withShadow(ctx, dy: 0, blur: r * 0.04, RGB(0xFFFFFF, alpha: 0.3)) { fill(ctx, crest, RGB(0xFFFDF6, alpha: 0.4)) }
        }
        // The pleats gather: darker ring around the knot.
        ctx.drawRadialGradient(gradient([RGB(0x8A6436, alpha: 0.35), RGB(0x8A6436, alpha: 0)]), startCenter: knot, startRadius: r * 0.08,
                               endCenter: knot, endRadius: r * 0.32, options: [])
    }
    let k = blobPath(knot, r * 0.11, jitter: 0.2, points: 7, seed: seed &+ 9)
    fill(ctx, k, RGB(0xEAD6B4))
    shade(ctx, k, [RGB(0xFFF8EA), RGB(0xE6CFA8), RGB(0xBF9A68)])
    // Thin wrapper edge: a translucent, lighter rim where the dough is a single layer.
    clipped(ctx, body) {
        ctx.addPath(body)
        ctx.setStrokeColor(RGB(0xFFF4E2, alpha: 0.5).cg)
        ctx.setLineWidth(r * 0.07)
        ctx.strokePath()
        // Gloss of the steamed wrapper: a broad sheen and a crisp highlight at the upper left.
        glint(ctx, pt(c, deg(-138), r * 0.48), w: r * 0.75, h: r * 0.36, angle: deg(-42), alpha: 0.55)
        glint(ctx, pt(c, deg(-140), r * 0.56), w: r * 0.3, h: r * 0.11, angle: deg(-42), alpha: 0.95)
    }
}

/// Black lacquer chopsticks with gilded bands, resting across the hoop at the lower right.
func cChopsticks(_ ctx: CGContext) {
    for (from, to) in [(CGPoint(x: 600, y: 985), CGPoint(x: 985, y: 615)), (CGPoint(x: 665, y: 1020), CGPoint(x: 1015, y: 690))] {
        let a = atan2(to.y - from.y, to.x - from.x)
        let len = hypot(to.x - from.x, to.y - from.y)
        let stick = CGMutablePath()
        // Tapered: thick end at `to`.
        let w0: CGFloat = 9, w1: CGFloat = 16
        stick.move(to: pt(from, a + .pi / 2, w0 / 2))
        stick.addLine(to: pt(to, a + .pi / 2, w1 / 2))
        stick.addLine(to: pt(to, a - .pi / 2, w1 / 2))
        stick.addLine(to: pt(from, a - .pi / 2, w0 / 2))
        stick.addArc(center: from, radius: w0 / 2, startAngle: a - .pi / 2, endAngle: a + .pi / 2, clockwise: true)
        stick.closeSubpath()
        withShadow(ctx, dy: 18, blur: 18, RGB(0x000000, alpha: 0.5)) { fill(ctx, stick, RGB(0x141010)) }
        clipped(ctx, stick) {
            ctx.drawLinearGradient(gradient([RGB(0x5A4A48), RGB(0x1A1414), RGB(0x080606)], [0, 0.45, 1]),
                                   start: pt(from, a - .pi / 2, w1), end: pt(from, a + .pi / 2, w1), options: [])
            // Lacquer highlight running along the stick.
            ctx.setStrokeColor(RGB(0xFFFFFF, alpha: 0.35).cg)
            ctx.setLineWidth(2.5)
            ctx.move(to: pt(pt(from, a, len * 0.1), a - .pi / 2, 2))
            ctx.addLine(to: pt(pt(from, a, len * 0.95), a - .pi / 2, 4))
            ctx.strokePath()
            // Gilded band near the top.
            let band0 = pt(from, a, len * 0.72), band1 = pt(from, a, len * 0.76)
            ctx.setStrokeColor(RGB(0xD9B060).cg)
            ctx.setLineWidth(40)
            ctx.move(to: band0); ctx.addLine(to: band1)
            ctx.strokePath()
            ctx.setStrokeColor(RGB(0xFFF0C0, alpha: 0.7).cg)
            ctx.setLineWidth(3)
            ctx.move(to: pt(band0, a - .pi / 2, 3)); ctx.addLine(to: pt(band1, a - .pi / 2, 4))
            ctx.strokePath()
        }
    }
}


// MARK: - Proposals D

let proposalsD: [Proposal] = [
    Proposal(number: 9, slug: "damascus", label: "Damascus", draw: drawDamascus),
    Proposal(number: 10, slug: "black-truffle", label: "Black Truffle", draw: drawBlackTruffle),
]

func dSmooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

func dMix(_ a: RGB, _ b: RGB, _ t: Float) -> (Float, Float, Float) {
    let t = CGFloat(max(0, min(1, t)))
    return (Float(a.r + (b.r - a.r) * t), Float(a.g + (b.g - a.g) * t), Float(a.b + (b.b - a.b) * t))
}

func dHash(_ i: Int, _ j: Int, _ k: Int) -> Float {
    var h = UInt32(truncatingIfNeeded: i &* 73856093 ^ j &* 19349663 ^ k &* 83492791)
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Float(h & 0xFFFF) / 65535
}

// MARK: - 9. Damascus

/// Classic end-grain checkerboard: walnut and maple blocks alternating, each showing arcs of growth
/// rings (the pith sits off the block), faint rays, pores, and a hairline glue joint.
func dEndGrainTexture() -> CGImage {
    let warp = Noise(seed: 41), pores = Noise(seed: 43)
    let tile: Float = 1024 / 5
    // (early wood, late wood) per species.
    let walnut = (RGB(0x64412B), RGB(0x382214)), maple = (RGB(0xCB8A4C), RGB(0x8E5426))
    return textureImage { x, y in
        let i = Int(floor((x + 60) / tile)), j = Int(floor((y + 60) / tile))
        let tx = (x + 60) - Float(i) * tile, ty = (y + 60) - Float(j) * tile
        let wood = (i + j) % 2 == 0 ? walnut : maple
        // Pith off the block, in a random direction, so rings show as arcs.
        let a = dHash(i, j, 1) * 2 * .pi
        let dist = tile * (0.7 + dHash(i, j, 2) * 0.6)
        let cx = tile / 2 + cos(a) * dist, cy = tile / 2 + sin(a) * dist
        let d = hypot(tx - cx, ty - cy) + warp.fbm(x * 0.012, y * 0.012, octaves: 3) * 12
        let spacing: Float = 6 + dHash(i, j, 3) * 4
        let ring = d / spacing - floor(d / spacing)
        let latewood = dSmooth(0.55, 0.85, ring) * (1 - dSmooth(0.88, 1, ring))
        let ang = atan2(ty - cy, tx - cx)
        let ray = pow(max(0, sin(ang * 140 + dHash(i, j, 4) * 9)), 40) * 0.08
        let pore = max(0, pores.fbm(x * 0.35, y * 0.35, octaves: 2) - 0.58) * 0.9
        let tone = dHash(i, j, 5) * 0.25
        var c = dMix(wood.0, wood.1, tone + latewood * 0.55 + pore)
        c = (c.0 + ray, c.1 + ray * 0.8, c.2 + ray * 0.6)
        // Glue joints.
        let edge = min(tx, tile - tx, ty, tile - ty)
        if edge < 2 {
            let k = (1 - edge / 2) * 0.35
            c = (c.0 * (1 - k), c.1 * (1 - k), c.2 * (1 - k))
        }
        return (c.0, c.1, c.2, 1)
    }
}

/// Knife geometry in its own coordinates: x along the knife (0 = heel of the blade, `dBladeLength` = tip,
/// the handle runs back to x = -330), y across, +y towards the edge. Drawn scaled by `dKnifeScale`.
let dBladeLength: CGFloat = 620
let dKnifeScale: CGFloat = 1.24
func dSpineY(_ x: CGFloat) -> CGFloat {
    let start = dBladeLength * 0.62
    guard x > start else { return -64 }
    let t = (x - start) / (dBladeLength - start)
    return -64 + 36 * t * t
}
func dEdgeY(_ x: CGFloat) -> CGFloat {
    let start = dBladeLength * 0.42
    guard x > start else { return 84 - 6 * x / start }
    let t = (x - start) / (dBladeLength - start)
    return 78 - 106 * pow(t, 1.8)
}

func dBladePath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: dSpineY(0)))
    for k in 1...80 {
        let x = dBladeLength * CGFloat(k) / 80
        p.addLine(to: CGPoint(x: x, y: dSpineY(x)))
    }
    for k in stride(from: 80, through: 0, by: -1) {
        let x = dBladeLength * CGFloat(k) / 80
        p.addLine(to: CGPoint(x: x, y: dEdgeY(x)))
    }
    p.closeSubpath()
    return p
}

/// A texture in knife coordinates covering `rect`, rendered at 1.5x for the scale-up.
func dLocalTexture(_ rect: CGRect, _ pixel: @escaping (Float, Float) -> (Float, Float, Float, Float)) -> CGImage {
    let res: CGFloat = 1.5
    let x0 = Float(rect.minX), y0 = Float(rect.minY), k = Float(1 / res)
    return textureImage(width: Int(rect.width * res), height: Int(rect.height * res)) { px, py in pixel(x0 + px * k, y0 + py * k) }
}

/// Mirror-polished Damascus: a broad, soft light-to-dark reflection with fine, organic folded layers
/// over it, and a plain polished bevel along the edge.
func dDamascusTexture(_ rect: CGRect) -> CGImage {
    let warp = Noise(seed: 51), warp2 = Noise(seed: 57), fine = Noise(seed: 53)
    let steel = [RGB(0x2E343B), RGB(0x6A737C), RGB(0xC4CBD2), RGB(0xF1F4F6)]
    func ramp(_ t: Float) -> (Float, Float, Float) {
        let t = max(0, min(0.999, t)) * Float(steel.count - 1)
        let i = Int(t)
        return dMix(steel[i], steel[i + 1], t - Float(i))
    }
    return dLocalTexture(rect) { lx, ly in
        let edge = Float(dEdgeY(CGFloat(lx))), spine = Float(dSpineY(CGFloat(lx)))
        let across = (ly - spine) / max(edge - spine, 1)
        // Reflection: bright towards the heel and spine (facing the light), falling to a dark band, a
        // second softer light near the tip.
        let s = lx / Float(dBladeLength) * 0.75 + across * 0.55
        var tone = 0.82 - 0.5 * dSmooth(0.15, 0.75, s) + 0.18 * exp(-pow(s - 0.95, 2) * 30)
        // Layers: domain-warped bands, fine and low contrast.
        let qx = warp.fbm(lx * 0.004, ly * 0.008, octaves: 4), qy = warp2.fbm(lx * 0.006 + 5, ly * 0.01, octaves: 3)
        let f = ly * 0.16 + qx * 16 + qy * 6 + fine.fbm(lx * 0.04, ly * 0.04, octaves: 2) * 1.2
        let band = 0.5 + 0.5 * sin(f * 2 * .pi)
        tone += (dSmooth(0.3, 0.7, band) - 0.5) * 0.2
        var c = ramp(tone)
        // Polished bevel along the edge, a crisp line where it starts.
        let toEdge = edge - ly
        let bevelWidth: Float = 40 * min(1, max(0.25, (edge - spine) / 140))
        if toEdge < bevelWidth {
            let t = toEdge / bevelWidth
            var b = ramp(0.95 - dSmooth(0.1, 0.8, s) * 0.45 + t * 0.1)
            if t > 0.9 { b = (b.0 * 0.75, b.1 * 0.75, b.2 * 0.75) }
            if t < 0.07 { b = (min(1, b.0 + 0.15), min(1, b.1 + 0.15), min(1, b.2 + 0.15)) }
            c = b
        }
        return (c.0, c.1, c.2, 1)
    }
}

/// Dark rosewood handle texture: long grain along the knife.
func dHandleTexture(_ rect: CGRect) -> CGImage {
    let n = Noise(seed: 61)
    let base = RGB(0x3A2218), light = RGB(0x6A3E28), dark = RGB(0x1A0E09)
    return dLocalTexture(rect) { lx, ly in
        let g = ly * 0.16 + n.fbm(lx * 0.006, ly * 0.04, octaves: 3) * 5
        let line = pow(0.5 + 0.5 * sin(g * 2 * .pi), 6)
        let tone = n.fbm(lx * 0.01 + 7, ly * 0.05, octaves: 3)
        var c = dMix(base, light, tone * 0.8)
        let d = dMix(base, dark, 1)
        c = (c.0 + (d.0 - c.0) * line * 0.7, c.1 + (d.1 - c.1) * line * 0.7, c.2 + (d.2 - c.2) * line * 0.7)
        return (c.0, c.1, c.2, 1)
    }
}

func dHandlePath() -> CGPath {
    // From the bolster back to the butt (x = -330), slightly swelling, rounded butt.
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -36, y: -34))
    p.addCurve(to: CGPoint(x: -300, y: -40), control1: CGPoint(x: -130, y: -36), control2: CGPoint(x: -230, y: -44))
    p.addCurve(to: CGPoint(x: -300, y: 40), control1: CGPoint(x: -352, y: -36), control2: CGPoint(x: -352, y: 36))
    p.addCurve(to: CGPoint(x: -36, y: 38), control1: CGPoint(x: -230, y: 46), control2: CGPoint(x: -130, y: 40))
    p.closeSubpath()
    return p
}

func dBolsterPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 6, y: -64))
    p.addLine(to: CGPoint(x: 6, y: 70))
    p.addCurve(to: CGPoint(x: -44, y: 40), control1: CGPoint(x: -14, y: 66), control2: CGPoint(x: -36, y: 52))
    p.addLine(to: CGPoint(x: -44, y: -36))
    p.addCurve(to: CGPoint(x: 6, y: -64), control1: CGPoint(x: -36, y: -50), control2: CGPoint(x: -14, y: -62))
    p.closeSubpath()
    return p
}

/// Finely chopped parsley heaped on the board: a low, loose mound of small flecks, lit from the upper left.
func dHerbHeap(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, seed: UInt64) {
    let mound = blobPath(c, r, jitter: 0.16, points: 12, seed: seed, stretch: 1.35, angle: deg(-30))
    withShadow(ctx, dy: 6, blur: 14, RGB(0x2A1200, alpha: 0.45)) { fill(ctx, mound, RGB(0x1F4A1A)) }
    var rng = SeededRandom(seed &+ 7)
    let palette = [RGB(0x7FAE58), RGB(0x548C3C), RGB(0x3B722C), RGB(0x285A20), RGB(0x173F14)]
    for k in 0..<1100 {
        // Denser in the middle, thinning out at the edge.
        let d = pow(rng.next(), 0.7) * r * 1.08
        let a = rng.next() * .pi * 2
        let local = CGPoint(x: cos(a) * d * 1.35, y: sin(a) * d)
        let rot = deg(-30)
        let p = CGPoint(x: c.x + local.x * cos(rot) - local.y * sin(rot), y: c.y + local.x * sin(rot) + local.y * cos(rot))
        // The heap is lit from the upper left: lighter flecks there, darker at the lower right and the rim.
        let lit = ((c.x - p.x) + (c.y - p.y)) / (r * 2.4) + 0.5 - d / r * 0.25
        let idx = min(palette.count - 1, max(0, Int((1 - lit) * 3.2 + rng.range(-1.2, 1.2))))
        fill(ctx, blobPath(p, rng.range(4, 9), jitter: 0.45, points: 5, seed: UInt64(k) &+ seed, stretch: rng.range(0.8, 1.8),
                           angle: rng.next() * .pi), palette[idx])
    }
    for k in 0..<70 {
        let p = pt(c, rng.next() * .pi * 2, r * rng.range(1.15, 2))
        fill(ctx, blobPath(p, rng.range(2.5, 5), jitter: 0.3, points: 6, seed: UInt64(k) &+ 999, stretch: 1.4, angle: rng.next() * 3),
             palette[1 + Int(rng.next() * 2.99)])
    }
}

/// Half a shallot, cut side up: copper skin, nested pink-violet layers, off-centre towards the root.
func dShallotHalf(_ ctx: CGContext, _ c: CGPoint, w: CGFloat, h: CGFloat, angle: CGFloat) {
    func layer(_ k: CGFloat) -> CGPath {
        // Layers shrink towards the root end (−x), so they nest off-centre.
        let ww = w * k, hh = h * k
        let cx = -w * (1 - k) * 0.35
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
        return CGPath(ellipseIn: CGRect(x: cx - ww / 2, y: -hh / 2, width: ww, height: hh), transform: &t)
    }
    withShadow(ctx, dy: 8, blur: 14, RGB(0x2A0A00, alpha: 0.45)) { fill(ctx, layer(1), RGB(0x9A4A30)) }
    shade(ctx, layer(1), [RGB(0xD48A62), RGB(0xA9553A), RGB(0x6E2E1C)])
    let tones = [RGB(0xF2D3DC), RGB(0xD999B2), RGB(0xF6E0E7), RGB(0xC9809E), RGB(0xF3DCE4), RGB(0xD38EAA), RGB(0xF8E7EC)]
    for (i, k) in [0.93, 0.86, 0.72, 0.64, 0.5, 0.42, 0.26].enumerated() {
        fill(ctx, layer(CGFloat(k)), tones[i])
    }
    clipped(ctx, layer(0.93)) {
        ctx.drawLinearGradient(gradient([RGB(0xFFFFFF, alpha: 0.3), RGB(0xFFFFFF, alpha: 0), RGB(0x5A1A30, alpha: 0.18)]),
                               start: CGPoint(x: c.x - w / 2, y: c.y - h / 2), end: CGPoint(x: c.x + w / 2, y: c.y + h / 2), options: [])
    }
}

/// A peeled garlic clove from above: curved back, flatter inner side, pointed tip, blunt root end.
func dGarlicClove(_ ctx: CGContext, _ c: CGPoint, length l: CGFloat, angle: CGFloat) {
    let w = l * 0.42
    let shape = CGMutablePath()
    shape.move(to: CGPoint(x: -l * 0.5, y: -w * 0.3))
    shape.addCurve(to: CGPoint(x: l * 0.5, y: -w * 0.05), control1: CGPoint(x: -l * 0.3, y: -w * 1.15), control2: CGPoint(x: l * 0.3, y: -w * 0.95))
    shape.addCurve(to: CGPoint(x: -l * 0.5, y: w * 0.35), control1: CGPoint(x: l * 0.25, y: w * 0.35), control2: CGPoint(x: -l * 0.2, y: w * 0.6))
    shape.addQuadCurve(to: CGPoint(x: -l * 0.5, y: -w * 0.3), control: CGPoint(x: -l * 0.56, y: 0))
    shape.closeSubpath()
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
    let path = shape.copy(using: &t)!
    withShadow(ctx, dy: 7, blur: 12, RGB(0x2A1200, alpha: 0.45)) { fill(ctx, path, RGB(0xEFE3C4)) }
    shade(ctx, path, [RGB(0xFFFCF2), RGB(0xF4EAD0), RGB(0xD6C398)], light: CGPoint(x: -0.2, y: -0.45))
    clipped(ctx, path) {
        // Faint lengthwise lines and the darker root end.
        ctx.saveGState()
        ctx.concatenate(t)
        ctx.setStrokeColor(RGB(0xC9B68A, alpha: 0.35).cg)
        ctx.setLineWidth(1.5)
        for k in 0..<4 {
            let y = -w * 0.7 + CGFloat(k) * w * 0.3
            ctx.move(to: CGPoint(x: -l * 0.45, y: y * 0.8))
            ctx.addQuadCurve(to: CGPoint(x: l * 0.45, y: -w * 0.05), control: CGPoint(x: 0, y: y))
        }
        ctx.strokePath()
        ctx.drawLinearGradient(gradient([RGB(0xB89A62, alpha: 0.55), RGB(0xB89A62, alpha: 0)]), start: CGPoint(x: -l * 0.52, y: 0),
                               end: CGPoint(x: -l * 0.36, y: 0), options: [])
        ctx.restoreGState()
    }
    glint(ctx, pt(c, angle - .pi / 2, w * 0.4), w: l * 0.4, h: w * 0.18, angle: angle, alpha: 0.55)
}

func drawDamascus(_ ctx: CGContext) {
    if appearance != .tinted {
        drawTexture(ctx, dEndGrainTexture())
        // Oiled board: a soft, broad sheen from the upper left, warm light falling off, a vignette.
        let lightPool = CGPoint(x: size * 0.28, y: size * 0.22)
        ctx.drawRadialGradient(gradient([RGB(0xFFE2B8, alpha: 0.26), RGB(0xFFE2B8, alpha: 0)]), startCenter: lightPool, startRadius: 0,
                               endCenter: lightPool, endRadius: size * 0.8, options: [])
        glint(ctx, CGPoint(x: size * 0.26, y: size * 0.2), w: size * 0.75, h: size * 0.32, angle: deg(-40), alpha: 0.1)
        vignette(ctx, 0.42)
        if appearance == .dark {
            ctx.setFillColor(RGB(0x0A0503, alpha: 0.55).cg)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    // Prep around the knife: herbs at the lower right (by the edge), shallot and garlic at the upper left.
    dHerbHeap(ctx, CGPoint(x: 752, y: 790), 98, seed: 9)
    dShallotHalf(ctx, CGPoint(x: 250, y: 300), w: 150, h: 112, angle: deg(-35))
    dGarlicClove(ctx, CGPoint(x: 380, y: 170), length: 112, angle: deg(-20))
    dGarlicClove(ctx, CGPoint(x: 170, y: 440), length: 100, angle: deg(115))

    // The knife, corner to corner, in its own coordinates.
    let angle = deg(-40)
    let origin = CGPoint(x: 372, y: 612)   // heel of the blade
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.rotate(by: angle)
    ctx.scaleBy(x: dKnifeScale, y: dKnifeScale)
    let blade = dBladePath(), handle = dHandlePath(), bolster = dBolsterPath()

    // Shadow: the blade lies flat, so a tight shadow; the handle is rounder and higher.
    let silhouette = CGMutablePath()
    silhouette.addPath(blade)
    silhouette.addPath(handle)
    silhouette.addPath(bolster)
    ctx.saveGState()
    // Shadow offsets ignore the CTM: in device space the icon is y-up, so negative height falls down.
    ctx.setShadow(offset: CGSize(width: 4, height: -20), blur: 30, color: RGB(0x1A0800, alpha: 0.6).cg)
    fill(ctx, silhouette, RGB(0x30343A))
    ctx.restoreGState()

    clipped(ctx, blade) {
        let r = CGRect(x: 0, y: -70, width: dBladeLength, height: 160)
        drawTexture(ctx, dDamascusTexture(r), in: r)
    }
    // Spine: a thin bright line catching the light.
    ctx.setLineCap(.round)
    ctx.setStrokeColor(RGB(0xFFFFFF, alpha: 0.75).cg)
    ctx.setLineWidth(2.5)
    ctx.move(to: CGPoint(x: 4, y: dSpineY(0) + 2))
    for k in 1...60 {
        let x = (dBladeLength - 8) * CGFloat(k) / 60
        ctx.addLine(to: CGPoint(x: x, y: dSpineY(x) + 2))
    }
    ctx.strokePath()

    // Bolster: polished steel.
    clipped(ctx, bolster) {
        ctx.drawLinearGradient(gradient([RGB(0xF4F6F8), RGB(0xB8C0C8), RGB(0x5E666E), RGB(0x9AA2AA)], [0, 0.35, 0.75, 1]),
                               start: CGPoint(x: 0, y: -70), end: CGPoint(x: 0, y: 70), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    // Handle: dark rosewood, rounded (light along the top), three brass rivets.
    clipped(ctx, handle) {
        let r = CGRect(x: -340, y: -50, width: 310, height: 100)
        drawTexture(ctx, dHandleTexture(r), in: r)
        ctx.drawLinearGradient(gradient([RGB(0xFFE8D0, alpha: 0.0), RGB(0xFFE8D0, alpha: 0.32), RGB(0x000000, alpha: 0.0),
                                         RGB(0x000000, alpha: 0.45)], [0, 0.22, 0.55, 1]),
                               start: CGPoint(x: 0, y: -44), end: CGPoint(x: 0, y: 44), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.addPath(handle)
    ctx.setStrokeColor(RGB(0x15100C, alpha: 0.6).cg)
    ctx.setLineWidth(2)
    ctx.strokePath()
    for x in [CGFloat(-95), -175, -255] {
        let rc = CGPoint(x: x, y: 0)
        fill(ctx, ellipsePath(rc, 13), RGB(0x2A1A10))
        shade(ctx, ellipsePath(rc, 11), [RGB(0xFFF0C0), RGB(0xD6A94E), RGB(0x8A6224)], locations: [0, 0.45, 1])
    }
    // A few herb bits on the blade, as if it just did the chopping.
    var rng = SeededRandom(77)
    for k in 0..<22 {
        let p = CGPoint(x: rng.range(70, 300), y: rng.range(18, 70))
        let color = [RGB(0x548C3C), RGB(0x3B722C), RGB(0x7FAE58)][k % 3]
        fill(ctx, blobPath(p, rng.range(3, 6), jitter: 0.35, points: 6, seed: UInt64(k) &+ 300, stretch: 1.4, angle: rng.next() * 3), color)
    }
    ctx.restoreGState()
}

// MARK: - 10. Black Truffle

/// Truffle flesh: dark brown with a maze of fine white veins (the marbling of a sliced black truffle).
func dTruffleFleshTexture() -> CGImage {
    let n1 = Noise(seed: 71), n2 = Noise(seed: 73), n3 = Noise(seed: 79)
    let flesh = RGB(0x2C1E17), fleshLight = RGB(0x4E3A2C), vein = RGB(0xEADCC4), halo = RGB(0x8A7462)
    return textureImage { x, y in
        let v1 = abs(n1.fbm(x * 0.055, y * 0.055, octaves: 4) - 0.5)
        let v2 = abs(n2.fbm(x * 0.1 + 3, y * 0.1, octaves: 3) - 0.5)
        let v3 = abs(n3.fbm(x * 0.03 + 9, y * 0.03, octaves: 3) - 0.5)
        // Fine bright veins, each with a soft paler halo; a broader, fainter network underneath.
        let veins = (1 - dSmooth(0.0, 0.03, v1)) * 0.95 + (1 - dSmooth(0.0, 0.022, v2)) * 0.6
        let halos = (1 - dSmooth(0.0, 0.08, v1)) * 0.35 + (1 - dSmooth(0.0, 0.06, v3)) * 0.3
        var c = dMix(flesh, fleshLight, n2.fbm(x * 0.02, y * 0.02, octaves: 2))
        let h = dMix(halo, halo, 0), w = dMix(vein, vein, 0)
        let th = min(1, halos), tv = min(1, veins)
        c = (c.0 + (h.0 - c.0) * th, c.1 + (h.1 - c.1) * th, c.2 + (h.2 - c.2) * th)
        c = (c.0 + (w.0 - c.0) * tv, c.1 + (w.1 - c.1) * tv, c.2 + (w.2 - c.2) * tv)
        return (c.0, c.1, c.2, 1)
    }
}

/// Satin charcoal stoneware plate, speckled, the rim lit at the upper left. Returns the well radius.
func dSlatePlate(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) -> CGFloat {
    let well = r * 0.84
    withShadow(ctx, dy: r * 0.06, blur: r * 0.18, RGB(0x1A0E04, alpha: 0.6)) { fill(ctx, ellipsePath(c, r), RGB(0x48443F)) }
    shade(ctx, ellipsePath(c, r), [RGB(0x8A847C), RGB(0x58534D), RGB(0x34312D)], light: CGPoint(x: -0.45, y: -0.5), locations: [0, 0.45, 1])
    // Well: a step down, its far (upper) wall in shadow, the near wall lighter.
    clipped(ctx, ellipsePath(c, well)) {
        ctx.drawLinearGradient(gradient([RGB(0x2C2926), RGB(0x423E3A), RGB(0x4E4945)]), start: CGPoint(x: c.x, y: c.y - well),
                               end: CGPoint(x: c.x, y: c.y + well), options: [])
        ctx.setShadow(offset: CGSize(width: 0, height: -well * 0.03), blur: well * 0.07, color: RGB(0x000000, alpha: 0.55).cg)
        ctx.setStrokeColor(RGB(0x000000).cg)
        ctx.setLineWidth(well * 0.1)
        ctx.strokeEllipse(in: circle(c, well + well * 0.05))
    }
    // Satin glaze: a broad, soft sheen at the upper left, and the rim's outer edge catching the light.
    clipped(ctx, ellipsePath(c, r)) {
        let hl = CGPoint(x: c.x - r * 0.55, y: c.y - r * 0.6)
        ctx.drawRadialGradient(gradient([RGB(0xF2E8DA, alpha: 0.26), RGB(0xF2E8DA, alpha: 0.07), RGB(0xF2E8DA, alpha: 0)], [0, 0.4, 1]),
                               startCenter: hl, startRadius: 0, endCenter: hl, endRadius: r * 1.05, options: [])
    }
    ctx.setLineWidth(3)
    ctx.setStrokeColor(RGB(0xD8CFC2, alpha: 0.45).cg)
    ctx.addArc(center: c, radius: r - 2, startAngle: deg(170), endAngle: deg(280), clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(RGB(0x9A9188, alpha: 0.5).cg)
    ctx.setLineWidth(2)
    ctx.addArc(center: c, radius: well, startAngle: deg(-10), endAngle: deg(110), clockwise: false)
    ctx.strokePath()
    // Pale clay speckles.
    clipped(ctx, ellipsePath(c, r)) {
        var rng = SeededRandom(5)
        for _ in 0..<900 {
            let p = pt(c, rng.next() * .pi * 2, sqrt(rng.next()) * r)
            ctx.setFillColor((rng.next() > 0.3 ? RGB(0xD9CDB8) : RGB(0x1A1816)).with(alpha: rng.range(0.15, 0.45)).cg)
            ctx.fillEllipse(in: circle(p, rng.range(0.8, 2.4)))
        }
    }
    return well
}

/// One ribbon of tagliatelle along `spine` (centreline points). The width narrows where the ribbon
/// twists edge-on and at the tucked ends. It casts a shadow on what's below (the dark gaps); `shadowAt`
/// gives the extra darkening at a point (the nest's own volume); a butter gloss runs along the lit edge.
func dRibbon(_ ctx: CGContext, spine: [CGPoint], width: CGFloat, twists: CGFloat, phase: CGFloat, color: RGB,
             shadowAt: (CGPoint) -> CGFloat) {
    let n = spine.count - 1
    var left: [CGPoint] = [], right: [CGPoint] = [], turns: [CGFloat] = [], normals: [CGVector] = []
    for k in 0...n {
        let t = CGFloat(k) / CGFloat(n)
        let a = spine[max(0, k - 1)], b = spine[min(n, k + 1)]
        var tx = b.x - a.x, ty = b.y - a.y
        let len = max(hypot(tx, ty), 0.001)
        tx /= len; ty /= len
        let nx = -ty, ny = tx
        let tuck = min(1, 0.55 + t * 6, 0.55 + (1 - t) * 6)
        let twist = 0.3 + 0.7 * abs(cos(.pi * (twists * t + phase)))
        let hw = width / 2 * twist * tuck
        left.append(CGPoint(x: spine[k].x + nx * hw, y: spine[k].y + ny * hw))
        right.append(CGPoint(x: spine[k].x - nx * hw, y: spine[k].y - ny * hw))
        turns.append(1 - twist)
        normals.append(CGVector(dx: nx, dy: ny))
    }
    let outline = CGMutablePath()
    outline.addLines(between: left + right.reversed())
    outline.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -7), blur: 12, color: RGB(0x2A1400, alpha: 0.7).cg)
    fill(ctx, outline, color.mixed(with: RGB(0x6A400C), shadowAt(spine[n / 2])))
    ctx.restoreGState()
    for k in 0..<n {
        let quad = CGMutablePath()
        quad.addLines(between: [left[k], left[k + 1], right[k + 1], right[k]])
        quad.closeSubpath()
        let c = color.mixed(with: RGB(0xB07418), turns[k] * 0.55).mixed(with: RGB(0x7A4A0E), shadowAt(spine[k]))
        ctx.addPath(quad)
        ctx.setFillColor(c.cg)
        ctx.setStrokeColor(c.cg)
        ctx.setLineWidth(0.8)
        ctx.drawPath(using: .fillStroke)
    }
    let light = CGVector(dx: -0.707, dy: -0.707)
    ctx.setLineCap(.butt)
    for k in 0..<n {
        let dot = normals[k].dx * light.dx + normals[k].dy * light.dy
        let lit = 1 - shadowAt(spine[k])
        for (side, s) in [(left, CGFloat(1)), (right, CGFloat(-1))] {
            let facing = dot * s
            let inset = CGVector(dx: -normals[k].dx * s * 3.5, dy: -normals[k].dy * s * 3.5)
            ctx.move(to: CGPoint(x: side[k].x + inset.dx, y: side[k].y + inset.dy))
            ctx.addLine(to: CGPoint(x: side[k + 1].x + inset.dx, y: side[k + 1].y + inset.dy))
            if facing > 0 {
                ctx.setStrokeColor(RGB(0xFFF8DC, alpha: 0.85 * pow(facing, 1.2) * lit).cg)
                ctx.setLineWidth(4)
            } else {
                ctx.setStrokeColor(RGB(0x6A3E08, alpha: 0.5 * -facing).cg)
                ctx.setLineWidth(2.5)
            }
            ctx.strokePath()
        }
    }
}

/// Fresh tagliatelle twirled into a nest with volume: shadowed under-layers spiral round the outside,
/// bright top ribbons cross the dome diagonally, and the whole nest casts a soft shadow on the plate.
func dTagliatelle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
    // Shadow of the dome falls to the lower right; under it, the dark body that shows in the gaps.
    let body = blobPath(c, r * 0.97, jitter: 0.05, points: 13, seed: 17)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: r * 0.06, height: -r * 0.1), blur: r * 0.22, color: RGB(0x000000, alpha: 0.7).cg)
    fill(ctx, body, RGB(0x7A4C14))
    ctx.restoreGState()
    shade(ctx, body, [RGB(0xA8742A), RGB(0x7A4C14), RGB(0x40240A)], light: CGPoint(x: -0.3, y: -0.35))

    // Dome shading: darker towards the rim, most at the lower right.
    func shadowAt(_ p: CGPoint) -> CGFloat {
        let dx = (p.x - c.x) / r, dy = (p.y - c.y) / r
        let d = hypot(dx, dy)
        return max(0, min(0.6, d * d * 0.42 + (dx + dy) * 0.707 * d * 0.32))
    }
    var rng = SeededRandom(29)
    let tones = [RGB(0xF8CC62), RGB(0xF2BC4E), RGB(0xFBD878), RGB(0xEEB446)]
    // Under-layers: bold ribbons spiralling round the outside, clockwise.
    for i in 0..<24 {
        let ring = 0.9 - CGFloat(i) / 24 * 0.55
        let r0 = r * min(0.9, ring + rng.range(-0.08, 0.06)), r1 = r * min(0.9, ring + rng.range(-0.2, 0.06))
        let start = rng.next() * .pi * 2, sweep = rng.range(2.0, 3.2)
        let width = rng.range(46, 58)
        let twists = rng.next() < 0.4 ? rng.range(0.6, 1.2) : rng.range(0, 0.15)
        let phase = rng.next()
        var spine: [CGPoint] = []
        for k in 0...70 {
            let t = CGFloat(k) / 70
            let e = t * t * (3 - 2 * t)
            let a = start + sweep * t
            let d = r0 + (r1 - r0) * e
            spine.append(CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d))
        }
        dRibbon(ctx, spine: spine, width: width, twists: twists, phase: phase, color: tones[i % 4], shadowAt: shadowAt)
    }
    // Top ribbons: long loops over the dome on tilted ellipses, so they cross the circular under-layers
    // diagonally; brightest, barely shadowed.
    for i in 0..<5 {
        let tilt = deg(i % 2 == 0 ? -40 : 35) + rng.range(-0.2, 0.2)
        let ax = r * rng.range(0.62, 0.8), by = r * rng.range(0.3, 0.45)
        let oc = CGPoint(x: c.x + rng.range(-25, 25), y: c.y + rng.range(-25, 25))
        let start = rng.next() * .pi * 2, sweep = rng.range(2.4, 3.4)
        var spine: [CGPoint] = []
        for k in 0...80 {
            let a = start + sweep * CGFloat(k) / 80
            let ex = cos(a) * ax, ey = sin(a) * by
            spine.append(CGPoint(x: oc.x + ex * cos(tilt) - ey * sin(tilt), y: oc.y + ex * sin(tilt) + ey * cos(tilt)))
        }
        dRibbon(ctx, spine: spine, width: rng.range(46, 54), twists: rng.range(0.3, 0.7), phase: rng.range(0.1, 0.3),
                color: tones[(i + 2) % 4], shadowAt: { shadowAt($0) * 0.45 })
    }
}

/// Paper-thin shaved truffle slice: irregular round, dark rind, veined flesh, the curled edge catching light.
func dTruffleSlice(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, seed: UInt64, flesh: CGImage) {
    let path = blobPath(c, r, jitter: 0.07, points: 14, seed: seed, stretch: 1.1, angle: CGFloat(seed % 7))
    withShadow(ctx, dy: 3, blur: 7, RGB(0x2A1400, alpha: 0.4)) { fill(ctx, path, RGB(0x1A120E)) }
    let inner = blobPath(c, r * 0.96, jitter: 0.07, points: 14, seed: seed, stretch: 1.1, angle: CGFloat(seed % 7))
    clipped(ctx, inner) {
        drawTexture(ctx, flesh)
        // Curl: lighter towards the light, darker at the far side.
        ctx.drawLinearGradient(gradient([RGB(0xFFFFFF, alpha: 0.16), RGB(0xFFFFFF, alpha: 0), RGB(0x000000, alpha: 0.3)]),
                               start: CGPoint(x: c.x - r, y: c.y - r), end: CGPoint(x: c.x + r, y: c.y + r), options: [])
    }
    // Paper-thin edge: lighter, almost translucent.
    clipped(ctx, inner) {
        ctx.addPath(inner)
        ctx.setStrokeColor(RGB(0xA88E78, alpha: 0.75).cg)
        ctx.setLineWidth(r * 0.12)
        ctx.strokePath()
    }
    // Butter gloss.
    glint(ctx, CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), w: r * 0.7, h: r * 0.28, angle: deg(-30), alpha: 0.28)
    // The thin edge curls up towards the light: a fine bright crescent at the upper left.
    clipped(ctx, path) {
        ctx.setStrokeColor(RGB(0xF4E6D0, alpha: 0.45).cg)
        ctx.setLineWidth(3)
        ctx.addArc(center: c, radius: r * 0.98, startAngle: deg(185), endAngle: deg(255), clockwise: false)
        ctx.strokePath()
    }
}

/// A whole black truffle: an irregular, potato-like lump covered in small pyramidal warts, each with a lit
/// upper-left facet and a shadowed lower-right one, a soft contact shadow, and a small cut face showing
/// the marbled flesh.
func dWholeTruffle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, flesh: CGImage) {
    // Potato-like lump with a bumpy outline (the warts break the silhouette).
    let body = CGMutablePath()
    for k in 0...240 {
        let th = CGFloat(k) / 240 * .pi * 2
        let lump = 1 + 0.08 * sin(2 * th + 1) + 0.05 * sin(3 * th + 2.5) + 0.03 * sin(5 * th)
        let bumps = 1 + 0.03 * abs(sin(22 * th))
        let q = CGPoint(x: c.x + cos(th) * r * 1.1 * lump * bumps, y: c.y + sin(th) * r * lump * bumps)
        if k == 0 { body.move(to: q) } else { body.addLine(to: q) }
    }
    body.closeSubpath()
    // Contact shadow: tight and dark right under it, a softer one further out.
    ctx.drawRadialGradient(gradient([RGB(0x0A0502, alpha: 0.7), RGB(0x0A0502, alpha: 0)]), startCenter: CGPoint(x: c.x + r * 0.12, y: c.y + r * 0.2),
                           startRadius: r * 0.7, endCenter: CGPoint(x: c.x + r * 0.12, y: c.y + r * 0.2), endRadius: r * 1.35, options: [])
    withShadow(ctx, dy: r * 0.1, blur: r * 0.18, RGB(0x000000, alpha: 0.6)) { fill(ctx, body, RGB(0x1C1410)) }
    shade(ctx, body, [RGB(0x3E2E24), RGB(0x1E1610), RGB(0x080504)], light: CGPoint(x: -0.35, y: -0.4), locations: [0, 0.5, 1])
    clipped(ctx, body) {
        // Warts on a jittered grid, drawn top to bottom so lower ones overlap upper ones.
        var rng = SeededRandom(91)
        let step: CGFloat = 17
        var warts: [CGPoint] = []
        var y = c.y - r * 1.3
        while y < c.y + r * 1.3 {
            var x = c.x - r * 1.3 + (Int((y - c.y) / step) % 2 == 0 ? 0 : step / 2)
            while x < c.x + r * 1.3 {
                warts.append(CGPoint(x: x + rng.range(-5, 5), y: y + rng.range(-5, 5)))
                x += step
            }
            y += step * 0.86
        }
        for p in warts {
            // Sphere normal at this point decides how much light the wart catches.
            let dx = (p.x - c.x) / (r * 1.1), dy = (p.y - c.y) / r
            let dz = sqrt(max(0, 1 - dx * dx - dy * dy))
            let lit = max(0, (-dx * 0.55 - dy * 0.6 + dz * 0.58))
            let s = rng.range(9, 13)
            let tip = CGPoint(x: p.x + rng.range(-2.5, 1), y: p.y + rng.range(-2.5, 1))
            let corners = (0..<4).map { CGPoint(x: p.x + [0, s, 0, -s][$0] * rng.range(0.8, 1.15), y: p.y + [-s, 0, s, 0][$0] * rng.range(0.8, 1.15)) }
            // Facets: upper right, lower right, lower left, upper left.
            let shades: [CGFloat] = [0.45, 0.08, 0.2, 1.0]
            for k in 0..<4 {
                let tri = CGMutablePath()
                tri.addLines(between: [tip, corners[k], corners[(k + 1) % 4]])
                tri.closeSubpath()
                let v = shades[k] * lit
                fill(ctx, tri, RGB(0x0E0906).mixed(with: RGB(0x8A705C), v))
            }
            // Tiny highlight on the lit facet.
            if lit > 0.35 {
                ctx.setFillColor(RGB(0xE8D8C4, alpha: min(0.8, (lit - 0.35) * 1.4)).cg)
                ctx.fillEllipse(in: circle(CGPoint(x: p.x - s * 0.35, y: p.y - s * 0.3), 1.6))
            }
        }
        // Soft rim darkening keeps the lump round.
        ctx.drawRadialGradient(gradient([RGB(0x000000, alpha: 0), RGB(0x000000, alpha: 0), RGB(0x000000, alpha: 0.5)], [0, 0.6, 1]),
                               startCenter: CGPoint(x: c.x - r * 0.2, y: c.y - r * 0.25), startRadius: 0, endCenter: c, endRadius: r * 1.15,
                               options: [.drawsAfterEndLocation])
    }
    // A slice taken off the upper right: flat, marbled cut face with a thin rind.
    let cut = blobPath(CGPoint(x: c.x + r * 0.42, y: c.y - r * 0.4), r * 0.42, jitter: 0.05, points: 9, seed: 12, stretch: 1.3, angle: deg(-40))
    clipped(ctx, body) {
        withShadow(ctx, dy: -3, blur: 4, RGB(0x000000, alpha: 0.6)) { fill(ctx, cut, RGB(0x2A1E16)) }
        let face = blobPath(CGPoint(x: c.x + r * 0.42, y: c.y - r * 0.4), r * 0.36, jitter: 0.05, points: 9, seed: 12, stretch: 1.3, angle: deg(-40))
        clipped(ctx, face) {
            drawTexture(ctx, flesh)
            ctx.drawLinearGradient(gradient([RGB(0xFFFFFF, alpha: 0.18), RGB(0x000000, alpha: 0.2)]),
                                   start: CGPoint(x: c.x, y: c.y - r * 0.8), end: CGPoint(x: c.x + r * 0.8, y: c.y), options: [])
        }
    }
}

/// Parmesan shaving: a thin, pale, irregular shard.
func dParmesan(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, angle: CGFloat, seed: UInt64) {
    var rng = SeededRandom(seed)
    let shard = CGMutablePath()
    for k in 0..<6 {
        let a = CGFloat(k) / 6 * .pi * 2 + rng.range(-0.3, 0.3)
        let d = r * rng.range(0.55, 1.1)
        let lx = cos(a) * d * 1.9, ly = sin(a) * d * 0.8
        let p = CGPoint(x: c.x + lx * cos(angle) - ly * sin(angle), y: c.y + lx * sin(angle) + ly * cos(angle))
        if k == 0 { shard.move(to: p) } else { shard.addLine(to: p) }
    }
    shard.closeSubpath()
    withShadow(ctx, dy: 4, blur: 7, RGB(0x000000, alpha: 0.4)) { fill(ctx, shard, RGB(0xF2E2B0)) }
    shade(ctx, shard, [RGB(0xFFF8E0), RGB(0xF2E2B4), RGB(0xDCC48A)])
}

/// Chopped chives: short bright green tubes.
func dChives(_ ctx: CGContext, center: CGPoint, radius: CGFloat, count: Int, seed: UInt64) {
    var rng = SeededRandom(seed)
    for _ in 0..<count {
        let p = pt(center, rng.next() * .pi * 2, sqrt(rng.next()) * radius)
        let a = rng.next() * .pi
        let piece = roundedRect(p, w: rng.range(13, 18), h: 8, r: 4, angle: a)
        withShadow(ctx, dy: 2, blur: 3, RGB(0x000000, alpha: 0.35)) { fill(ctx, piece, RGB(0x3E8A2A)) }
        shade(ctx, piece, [RGB(0x9AD66A), RGB(0x4E9A32), RGB(0x2E6A1E)])
    }
}

/// Umber linen tablecloth: fine weave with slubs, soft light from the upper left, vignette.
func dLinenTexture(_ base: RGB) -> CGImage {
    let slub = Noise(seed: 101), tone = Noise(seed: 103)
    return textureImage { x, y in
        let weft = sin(y * 1.45 + slub.fbm(x * 0.02, y * 0.6, octaves: 2) * 3)
        let warp = sin(x * 1.45 + slub.fbm(x * 0.6 + 9, y * 0.02, octaves: 2) * 3)
        let slubs = (slub.fbm(x * 0.01, y * 0.25, octaves: 3) - 0.5) * 0.12 + (slub.fbm(x * 0.25 + 4, y * 0.01, octaves: 3) - 0.5) * 0.1
        let k = 1 + weft * 0.035 + warp * 0.035 + slubs + (tone.fbm(x * 0.004, y * 0.004, octaves: 3) - 0.5) * 0.12
        return (Float(base.r) * k, Float(base.g) * k, Float(base.b) * k, 1)
    }
}

func drawBlackTruffle(_ ctx: CGContext) {
    if appearance != .tinted {
        drawTexture(ctx, dLinenTexture(appearance == .dark ? RGB(0x3E2C1E) : RGB(0x7A5A3E)))
        let lightPool = CGPoint(x: size * 0.25, y: size * 0.2)
        ctx.drawRadialGradient(gradient([RGB(0xFFE0B0, alpha: 0.22), RGB(0xFFE0B0, alpha: 0)]), startCenter: lightPool, startRadius: 0,
                               endCenter: lightPool, endRadius: size * 0.85, options: [])
        vignette(ctx, appearance == .dark ? 0.55 : 0.45)
    }

    let c = CGPoint(x: 466, y: 466)
    let well = dSlatePlate(ctx, c, 396)
    dTagliatelle(ctx, CGPoint(x: c.x + 2, y: c.y + 2), well * 0.88)

    let flesh = dTruffleFleshTexture()
    // Shavings of different sizes, overlapping, leaving the top ribbons visible between them.
    let slices: [(CGFloat, CGFloat, CGFloat)] = [
        (-60, -95, 66), (55, -40, 74), (-45, 20, 58), (110, 75, 52), (-120, -10, 44), (10, 110, 46), (130, -130, 38),
    ]
    for (k, s) in slices.enumerated() {
        dTruffleSlice(ctx, CGPoint(x: c.x + s.0, y: c.y + s.1), s.2, seed: UInt64(k * 13 + 5), flesh: flesh)
    }
    for (k, s) in [(CGPoint(x: c.x - 80, y: c.y + 140), CGFloat(0.4)), (CGPoint(x: c.x + 185, y: c.y + 0), 2.2),
                   (CGPoint(x: c.x - 170, y: c.y - 120), 1.2)].enumerated() {
        dParmesan(ctx, s.0, 22, angle: s.1, seed: UInt64(k + 40))
    }
    dChives(ctx, center: c, radius: well * 0.72, count: 24, seed: 151)
    // Cracked pepper.
    drawFlecks(ctx, center: c, radius: well * 0.8, count: 30, size: 2.6, colors: [RGB(0x15100C)], seed: 141)

    // One whole truffle resting beside the plate.
    dWholeTruffle(ctx, CGPoint(x: 826, y: 830), 104, flesh: flesh)
}


// MARK: - Rendering

struct Proposal {
    let number: Int
    let slug: String
    let label: String
    let draw: (CGContext) -> Void
}

func render(_ draw: (CGContext) -> Void, _ look: Appearance) -> CGImage {
    appearance = look
    transparentDarkGround = false
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    draw(ctx)
    return look == .tinted ? tintedMark(ctx) : flattened(ctx.makeImage()!)
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

/// Tinted appearance, same as Design/make-icon-variants.swift: luminance over black, levels stretched, S-curve.
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

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func loadPNG(_ path: String) -> CGImage? {
    guard let image = NSImage(contentsOfFile: path) else { return nil }
    var rect = CGRect(x: 0, y: 0, width: size, height: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

// MARK: - Overview

/// iOS-style mask (continuous corners approximated by a rounded rect at 22.4%).
func iconMask(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237, cornerHeight: rect.width * 0.2237, transform: nil)
}

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

typealias Entry = (tag: String, title: String, images: [Appearance: CGImage])

func writeOverview(current: [Entry], proposals: [Entry], to url: URL) throws {
    let cols = 4
    let cell = CGSize(width: 560, height: 470)
    let margin: CGFloat = 60
    let currentH: CGFloat = 330
    let rows = Int(ceil(Double(proposals.count) / Double(cols)))
    let strips: [(String, (RGB, RGB), Appearance, RGB?)] = [
        ("Light", (RGB(0xD9DEE6), RGB(0xB8C2D0)), .light, nil),
        ("Dark", (RGB(0x23262E), RGB(0x101216)), .dark, nil),
        ("Tinted", (RGB(0x2A2420), RGB(0x14100E)), .tinted, RGB(0xF2B36B)),
    ]
    let stripH: CGFloat = 230
    let w = margin * 2 + cell.width * CGFloat(cols)
    let h = margin * 2 + currentH + 70 + cell.height * CGFloat(rows) + CGFloat(strips.count) * (stripH + 20)
    let sheet = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    sheet.translateBy(x: 0, y: h)
    sheet.scaleBy(x: 1, y: -1)
    sheet.interpolationQuality = .high
    NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: true)
    sheet.setFillColor(RGB(0xF4F3F0).cg)
    sheet.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Current icons, smaller, for reference.
    label("Current icons", at: CGPoint(x: margin, y: margin - 10), size: 26, color: .darkGray, weight: .medium)
    for (i, e) in current.enumerated() {
        let o = CGPoint(x: margin + CGFloat(i) * 560, y: margin + 36)
        label("\(e.tag) · \(e.title)", at: o, size: 26, color: .darkGray)
        drawIcon(sheet, e.images[.light]!, in: CGRect(x: o.x, y: o.y + 44, width: 220, height: 220))
        drawIcon(sheet, e.images[.light]!, in: CGRect(x: o.x + 240, y: o.y + 44, width: 120, height: 120))
        drawIcon(sheet, e.images[.light]!, in: CGRect(x: o.x + 240, y: o.y + 184, width: 60, height: 60))
    }
    let gridTop = margin + currentH + 70
    sheet.setFillColor(RGB(0x000000, alpha: 0.12).cg)
    sheet.fill(CGRect(x: margin, y: gridTop - 40, width: w - margin * 2, height: 2))
    label("Subscriber proposals", at: CGPoint(x: margin, y: gridTop - 30), size: 26, color: .darkGray, weight: .medium)
    for (i, e) in proposals.enumerated() {
        let o = CGPoint(x: margin + CGFloat(i % cols) * cell.width, y: gridTop + 20 + CGFloat(i / cols) * cell.height)
        label("\(e.tag) · \(e.title)", at: o, size: 32, color: .black)
        let image = e.images[.light]!
        drawIcon(sheet, image, in: CGRect(x: o.x, y: o.y + 52, width: 360, height: 360))
        drawIcon(sheet, image, in: CGRect(x: o.x + 380, y: o.y + 52, width: 120, height: 120))
        drawIcon(sheet, image, in: CGRect(x: o.x + 380, y: o.y + 192, width: 60, height: 60))
    }

    let all = current + proposals
    let stripTop = gridTop + cell.height * CGFloat(rows) + 10
    for (k, strip) in strips.enumerated() {
        let r = CGRect(x: margin, y: stripTop + CGFloat(k) * (stripH + 20), width: w - margin * 2, height: stripH)
        sheet.saveGState()
        sheet.addPath(CGPath(roundedRect: r, cornerWidth: 28, cornerHeight: 28, transform: nil))
        sheet.clip()
        sheet.drawLinearGradient(gradient([strip.1.0, strip.1.1]), start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        sheet.restoreGState()
        let iconSize: CGFloat = 120
        let gap = (r.width - CGFloat(all.count) * iconSize) / CGFloat(all.count + 1)
        let textColor: NSColor = strip.2 == .light ? .black : .white
        for (i, e) in all.enumerated() {
            let x = r.minX + gap + CGFloat(i) * (iconSize + gap)
            drawIcon(sheet, e.images[strip.2]!, in: CGRect(x: x, y: r.minY + 40, width: iconSize, height: iconSize), tint: strip.3)
            let t = NSAttributedString(string: e.tag, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium)])
            label(e.tag, at: CGPoint(x: x + (iconSize - t.size().width) / 2, y: r.minY + 172), size: 22, color: textColor, weight: .medium)
        }
        label(strip.0, at: CGPoint(x: r.minX + 16, y: r.minY + 8), size: 18, color: textColor.withAlphaComponent(0.6), weight: .medium)
    }
    try writePNG(sheet.makeImage()!, to: url)
}

/// Renders `proposals` (all three appearances), writes the singles and, if `overview`, the overview sheet.
func run(_ proposals: [Proposal], out: URL, overview: Bool = true) throws {
    let fm = FileManager.default
    let appearancesDir = out.appendingPathComponent("appearances")
    try fm.createDirectory(at: appearancesDir, withIntermediateDirectories: true)
    var entries: [Entry] = []
    for p in proposals.sorted(by: { $0.number < $1.number }) {
        var images: [Appearance: CGImage] = [:]
        for look in Appearance.allCases { images[look] = render(p.draw, look) }
        let name = "proposal-\(p.number)-\(p.slug)"
        try writePNG(images[.light]!, to: out.appendingPathComponent("\(name).png"))
        try writePNG(images[.dark]!, to: appearancesDir.appendingPathComponent("\(name)-dark.png"))
        try writePNG(images[.tinted]!, to: appearancesDir.appendingPathComponent("\(name)-tinted.png"))
        entries.append(("\(p.number)", p.label, images))
        print("wrote \(name)")
    }
    guard overview else { return }
    let res = "MealMate/Resources/"
    let currentFiles: [(String, String, String)] = [
        ("S", "Salad (default)", res + "Assets.xcassets/AppIcon.appiconset/AppIcon"),
        ("C", "Copper Pot", res + "AppIcons.xcassets/AppIconCopperPot.appiconset/AppIconCopperPot"),
        ("M", "Midnight Kitchen", res + "AppIcons.xcassets/AppIconMidnightKitchen.appiconset/AppIconMidnightKitchen"),
    ]
    var current: [Entry] = []
    for (tag, title, base) in currentFiles {
        guard let l = loadPNG(base + ".png"), let d = loadPNG(base + "-dark.png"), let t = loadPNG(base + "-tinted.png") else {
            print("missing \(base), run from the repo root"); continue
        }
        current.append((tag, title, [.light: l, .dark: d, .tinted: t]))
    }
    try writeOverview(current: current, proposals: entries, to: out.appendingPathComponent("overview.png"))
    print("wrote \(out.appendingPathComponent("overview.png").path)")
}

// MARK: - Main

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/mealmate-sub-icons")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try run(proposalsA + proposalsB + proposalsC + proposalsD, out: outDir)
