#!/usr/bin/env swift
// MealMate subscription app icons: Copper Pot and Midnight Kitchen.
//
// Usage:  swift Design/make-icon.swift [resources-dir]
// Default resources dir: MealMate/Resources
//
// The default icon and the food icons come from Design/make-icon-variants.swift.
//
// Run from the repo root. Every icon is 1024x1024 in three appearances:
//   <Name>.png         light, opaque, no alpha channel
//   <Name>-dark.png    dark appearance
//   <Name>-tinted.png  tinted appearance (grayscale mark on black, the system tints it)
//
// Writes:
//   AppIcons.xcassets/AppIcon<Variant>.appiconset    alternate icons (subscription perk, see docs/supporter.md)
//   AppIcons.xcassets/IconPreview<Variant>.imageset  384px previews for the in-app icon picker (light + dark)
//
// The mark: ingredients prepped before cooking, seen from above. One larger prep bowl and two small bowls,
// each holding a single prepared ingredient (herbs, paprika, saffron), on a soft ground. Each icon changes
// ground, bowl material and palette.

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Palette

struct RGB {
    let r, g, b: CGFloat
    let a: CGFloat
    init(_ hex: UInt32, alpha: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        a = alpha
    }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func with(alpha: CGFloat) -> RGB { RGB(r: r, g: g, b: b, a: alpha) }
    func mixed(with other: RGB, _ t: CGFloat) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }
    private init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) { self.r = r; self.g = g; self.b = b; self.a = a }
}

enum Appearance: CaseIterable { case light, dark, tinted }

/// What the bowls sit on.
enum Ground {
    case transparent
    /// Very soft vertical tone shift, top to bottom.
    case linear(RGB, RGB)
    /// Pool of light at the upper left, falling off to `outer`.
    case radial(RGB, RGB)
    /// Procedural end-grain-free cutting board: base tone, light streaks, dark grain lines.
    case wood(base: RGB, light: RGB, dark: RGB)
}

/// What the bowls are made of.
enum BowlStyle {
    /// Plain glazed ceramic. `sheen` adds a soft glaze highlight at the upper left.
    case ceramic(sheen: CGFloat)
    /// Speckled stoneware.
    case stoneware(speck: RGB, sheen: CGFloat)
    /// Polished copper: conic metal sheen on the rim, a lighter brushed inside, specular highlights.
    /// The large bowl becomes a saucepan with a handle.
    case copper(CopperPalette)
    /// Dark ceramic with gilded rims.
    case gilded(gold: [RGB])
}

struct CopperPalette {
    let deep: RGB, mid: RGB, bright: RGB, glint: RGB
}

struct Palette {
    var ground: Ground
    var bowlRim: RGB
    var bowlInside: RGB
    var shadow: RGB
    var herb: RGB
    var herbDark: RGB
    var herbLight: RGB
    var paprika: RGB
    var paprikaLight: RGB
    var saffron: RGB
    var saffronLight: RGB
    var bowl: BowlStyle = .ceramic(sheen: 0)
    /// Fine flecks scattered on the ground (gold dust for Midnight Kitchen).
    var groundSpecks: RGB? = nil
    /// Soft darkening towards the corners, 0 = none.
    var vignette: CGFloat = 0
}

/// The original prep-bowl palettes. The icons start from these.
enum Base {
    static let light = Palette(
        ground: .linear(RGB(0xEFE9DC), RGB(0xE6DECD)),
        bowlRim: RGB(0xFCFAF6), bowlInside: RGB(0xF1ECE2),
        shadow: RGB(0x5A4A30, alpha: 0.24),
        herb: RGB(0x6E9A5A), herbDark: RGB(0x557D47), herbLight: RGB(0x8DB477),
        paprika: RGB(0xB95E40), paprikaLight: RGB(0xD9845F),
        saffron: RGB(0xE0AE4F), saffronLight: RGB(0xEEC877))
    static let dark = Palette(
        ground: .transparent,
        bowlRim: RGB(0x45423C), bowlInside: RGB(0x2F2D29),
        shadow: RGB(0x000000, alpha: 0.35),
        herb: RGB(0x86B070), herbDark: RGB(0x6A9658), herbLight: RGB(0xA6CA8E),
        paprika: RGB(0xD06E4C), paprikaLight: RGB(0xE8946E),
        saffron: RGB(0xE8B85A), saffronLight: RGB(0xF4D284))
    static let tinted = Palette(
        ground: .linear(RGB(0x000000), RGB(0x000000)),
        bowlRim: RGB(0x5C5C5C), bowlInside: RGB(0x3A3A3A),
        shadow: RGB(0x000000, alpha: 0.0),
        herb: RGB(0xE6E6E6), herbDark: RGB(0xBDBDBD), herbLight: RGB(0xFFFFFF),
        paprika: RGB(0xB8B8B8), paprikaLight: RGB(0xDADADA),
        saffron: RGB(0xD4D4D4), saffronLight: RGB(0xF2F2F2))
}

// MARK: - Variants

struct Variant {
    /// Asset name suffix: `AppIcon<suffix>` / `IconPreview<suffix>`.
    let suffix: String
    let palette: (Appearance) -> Palette
}

let alternates: [Variant] = [
    // Polished copper on a deep warm ground.
    Variant(suffix: "CopperPot") { appearance in
        switch appearance {
        case .light, .dark:
            let isDark = appearance == .dark
            var p = Base.light
            p.ground = isDark ? .radial(RGB(0x2A1A14), RGB(0x120B08)) : .radial(RGB(0x4A2A1E), RGB(0x24130D))
            p.shadow = RGB(0x000000, alpha: 0.6)
            p.bowl = .copper(CopperPalette(deep: RGB(0x4A1F0C), mid: RGB(0xA85A32),
                                           bright: RGB(0xE69A68), glint: RGB(0xFFE2C6)))
            p.vignette = 0.3
            return p
        case .tinted:
            var p = Base.tinted
            p.bowl = .copper(CopperPalette(deep: RGB(0x2A2A2A), mid: RGB(0x6A6A6A),
                                           bright: RGB(0x9A9A9A), glint: RGB(0xD0D0D0)))
            return p
        }
    },
    // Midnight blue-black, dark ceramic with gilded rims, a little gold dust.
    Variant(suffix: "MidnightKitchen") { appearance in
        switch appearance {
        case .light, .dark:
            let isDark = appearance == .dark
            var p = Base.dark
            p.ground = isDark ? .radial(RGB(0x141A2B), RGB(0x06080E)) : .radial(RGB(0x1C2438), RGB(0x080B13))
            p.bowlRim = RGB(0x27304C); p.bowlInside = RGB(0x161C30)
            p.shadow = RGB(0x000000, alpha: 0.7)
            p.bowl = .gilded(gold: [RGB(0x8A6424), RGB(0xE9C77A), RGB(0xB88C3C), RGB(0xF6E2A8), RGB(0x9C7430)])
            p.groundSpecks = RGB(0xD9B566)
            p.vignette = 0.25
            return p
        case .tinted:
            var p = Base.tinted
            p.bowl = .gilded(gold: [RGB(0x8A8A8A), RGB(0xEEEEEE), RGB(0xA8A8A8), RGB(0xFFFFFF), RGB(0x909090)])
            return p
        }
    },
]

// MARK: - Drawing helpers

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

/// Deterministic pseudo random generator so the icon is reproducible.
struct SeededRandom {
    var state: UInt64
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}

func gradient(_ colors: [RGB], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors.map(\.cg) as CFArray, locations: locations)!
}

/// Conic (angular) gradient around `center`, built from thin wedges so it runs on any macOS.
/// `angle` is where the first colour sits; colours advance clockwise on screen.
func drawConic(_ ctx: CGContext, _ colors: [RGB], _ locations: [CGFloat]?, center: CGPoint, radius: CGFloat, angle: CGFloat) {
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
        // Overlap a hair so no seams show between wedges.
        ctx.addArc(center: center, radius: radius * 1.05, startAngle: a0, endAngle: a0 + step * 1.6, clockwise: false)
        ctx.closePath()
        ctx.fillPath()
    }
}

/// Soft white glaze highlight at the upper left of a bowl.
func drawSheen(_ ctx: CGContext, center: CGPoint, radius r: CGFloat, strength: CGFloat) {
    guard strength > 0 else { return }
    ctx.saveGState()
    ctx.addEllipse(in: circle(center, r))
    ctx.clip()
    let hl = CGPoint(x: center.x - r * 0.55, y: center.y - r * 0.55)
    let white = RGB(0xFFFFFF)
    ctx.drawRadialGradient(gradient([white.with(alpha: strength), white.with(alpha: 0)]),
                           startCenter: hl, startRadius: 0, endCenter: hl, endRadius: r * 0.9, options: [])
    ctx.restoreGState()
}

/// Thin shadow just inside the lip, light from the top: gives the inside of a bowl depth.
func drawInnerLipShadow(_ ctx: CGContext, center: CGPoint, radius inner: CGFloat, color: RGB) {
    ctx.saveGState()
    ctx.addEllipse(in: circle(center, inner))
    ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: inner * 0.05), blur: inner * 0.08, color: color.cg)
    ctx.setStrokeColor(color.cg)
    ctx.setLineWidth(inner * 0.08)
    ctx.strokeEllipse(in: circle(center, inner + inner * 0.04))
    ctx.restoreGState()
}

func drawContactShadow(_ ctx: CGContext, center: CGPoint, radius r: CGFloat, palette p: Palette, fill: RGB) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: r * 0.10), blur: r * 0.24, color: p.shadow.cg)
    ctx.setFillColor(fill.cg)
    ctx.fillEllipse(in: circle(center, r))
    ctx.restoreGState()
}

func drawBowl(_ ctx: CGContext, center: CGPoint, radius r: CGFloat, palette p: Palette, contents: (CGContext, CGPoint, CGFloat) -> Void) {
    let inner = r * 0.82
    switch p.bowl {
    case .ceramic(let sheen):
        // Soft contact shadow, light from the top.
        drawContactShadow(ctx, center: center, radius: r, palette: p, fill: p.bowlRim)

        // Rim + inside of the bowl.
        ctx.setFillColor(p.bowlRim.cg)
        ctx.fillEllipse(in: circle(center, r))
        drawSheen(ctx, center: center, radius: r, strength: sheen)
        ctx.setFillColor(p.bowlInside.cg)
        ctx.fillEllipse(in: circle(center, inner))
        if sheen > 0 { drawInnerLipShadow(ctx, center: center, radius: inner, color: RGB(0x000000, alpha: 0.12)) }

    case .stoneware(let speck, let sheen):
        drawContactShadow(ctx, center: center, radius: r, palette: p, fill: p.bowlRim)
        ctx.setFillColor(p.bowlRim.cg)
        ctx.fillEllipse(in: circle(center, r))
        ctx.setFillColor(p.bowlInside.cg)
        ctx.fillEllipse(in: circle(center, inner))
        // Iron speckles in the clay.
        ctx.saveGState()
        ctx.addEllipse(in: circle(center, r))
        ctx.clip()
        var rng = SeededRandom(state: UInt64(center.x * 7 + center.y))
        for _ in 0..<Int(r * 1.6) {
            let a = rng.next() * .pi * 2
            let d = sqrt(rng.next()) * r
            let s = 0.8 + rng.next() * 2.2
            ctx.setFillColor(speck.with(alpha: 0.35 + rng.next() * 0.4).cg)
            ctx.fillEllipse(in: circle(CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d), s))
        }
        ctx.restoreGState()
        drawSheen(ctx, center: center, radius: r, strength: sheen)
        drawInnerLipShadow(ctx, center: center, radius: inner, color: RGB(0x000000, alpha: 0.3))

    case .copper(let c):
        drawContactShadow(ctx, center: center, radius: r, palette: p, fill: c.deep)
        // Rim: polished metal, the conic sweep reads as a turned, reflective surface.
        ctx.saveGState()
        ctx.addEllipse(in: circle(center, r))
        ctx.clip()
        // Two opposite bright bands and two dark ones, like a turned, polished pan under one light.
        drawConic(ctx, [c.glint, c.bright, c.mid, c.deep, c.mid, c.bright, c.glint, c.bright, c.mid, c.deep, c.mid, c.bright, c.glint],
                  [0, 0.04, 0.12, 0.25, 0.36, 0.45, 0.5, 0.55, 0.64, 0.75, 0.88, 0.96, 1],
                  center: center, radius: r, angle: -.pi * 0.75)
        ctx.restoreGState()
        // Rolled lip: a thin bright line at the outer edge, a dark one where the rim turns down.
        ctx.setStrokeColor(c.glint.with(alpha: 0.55).cg)
        ctx.setLineWidth(r * 0.012)
        ctx.strokeEllipse(in: circle(center, r - r * 0.01))
        // Inside: deeper, softer copper, lit from the upper left.
        ctx.saveGState()
        ctx.addEllipse(in: circle(center, inner))
        ctx.clip()
        let lit = CGPoint(x: center.x + inner * 0.35, y: center.y + inner * 0.35)
        ctx.drawRadialGradient(gradient([c.bright, c.mid, c.deep]),
                               startCenter: lit, startRadius: 0, endCenter: center, endRadius: inner * 1.1,
                               options: [.drawsAfterEndLocation])
        // The far wall catches the light: a soft glossy crescent at the lower right.
        let wall = CGPoint(x: center.x + inner * 0.62, y: center.y + inner * 0.62)
        ctx.drawRadialGradient(gradient([c.glint.with(alpha: 0.55), c.glint.with(alpha: 0)]),
                               startCenter: wall, startRadius: 0, endCenter: wall, endRadius: inner * 0.55, options: [])
        ctx.restoreGState()
        drawInnerLipShadow(ctx, center: center, radius: inner, color: RGB(0x1A0904, alpha: 0.55))
        ctx.setStrokeColor(c.deep.with(alpha: 0.9).cg)
        ctx.setLineWidth(r * 0.014)
        ctx.strokeEllipse(in: circle(center, inner))

    case .gilded(let gold):
        drawContactShadow(ctx, center: center, radius: r, palette: p, fill: p.bowlRim)
        // Glazed ink-blue body, glossy: a broad soft highlight at the upper left.
        ctx.saveGState()
        ctx.addEllipse(in: circle(center, r))
        ctx.clip()
        let hl = CGPoint(x: center.x - r * 0.5, y: center.y - r * 0.55)
        ctx.drawRadialGradient(gradient([p.bowlRim.mixed(with: RGB(0xA8B6D8), 0.35), p.bowlRim, p.bowlRim.mixed(with: RGB(0x000000), 0.25)],
                                        [0, 0.55, 1]),
                               startCenter: hl, startRadius: 0, endCenter: center, endRadius: r * 1.15,
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        // Inside: deeper glaze, the far wall a touch lighter.
        ctx.saveGState()
        ctx.addEllipse(in: circle(center, inner))
        ctx.clip()
        let wall = CGPoint(x: center.x + inner * 0.4, y: center.y + inner * 0.4)
        ctx.drawRadialGradient(gradient([p.bowlInside.mixed(with: RGB(0x6878A0), 0.25), p.bowlInside]),
                               startCenter: wall, startRadius: 0, endCenter: center, endRadius: inner * 1.1,
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()
        drawInnerLipShadow(ctx, center: center, radius: inner, color: RGB(0x000000, alpha: 0.45))
        // Glaze glint on the rim's upper left.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 0.05, color: RGB(0xDDE6FF, alpha: 0.8).cg)
        ctx.setStrokeColor(RGB(0xDDE6FF, alpha: 0.3).cg)
        ctx.setLineCap(.round)
        ctx.setLineWidth(r * 0.025)
        ctx.addArc(center: center, radius: (r * 0.94 + inner) / 2, startAngle: .pi * 1.12, endAngle: .pi * 1.36, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
        // The gilded rim: one confident band on the bowl's outer edge, polished (conic sheen).
        func goldBand(outer: CGFloat, width: CGFloat) {
            ctx.saveGState()
            ctx.addEllipse(in: circle(center, outer))
            ctx.addEllipse(in: circle(center, outer - width))
            ctx.clip(using: .evenOdd)
            drawConic(ctx, gold + [gold[0]], nil, center: center, radius: outer, angle: -.pi * 0.75)
            ctx.restoreGState()
        }
        goldBand(outer: r, width: r * 0.065)
        // Hairline of gold where the glaze turns into the bowl.
        goldBand(outer: inner + r * 0.006, width: r * 0.012)
    }

    // Contents, clipped to the bowl's inside.
    ctx.saveGState()
    ctx.addEllipse(in: circle(center, inner))
    ctx.clip()
    contents(ctx, center, inner)
    ctx.restoreGState()

    if case .copper(let c) = p.bowl {
        // Specular highlights on the polished rim, after the contents so nothing covers them.
        ctx.saveGState()
        ctx.addEllipse(in: circle(center, r))
        ctx.addEllipse(in: circle(center, inner))
        ctx.clip(using: .evenOdd)
        let glint = CGPoint(x: center.x - r * 0.62, y: center.y - r * 0.62)
        ctx.drawRadialGradient(gradient([c.glint.with(alpha: 0.95), c.glint.with(alpha: 0)]),
                               startCenter: glint, startRadius: 0, endCenter: glint, endRadius: r * 0.42, options: [])
        let rebound = CGPoint(x: center.x + r * 0.7, y: center.y + r * 0.55)
        ctx.drawRadialGradient(gradient([c.bright.with(alpha: 0.6), c.bright.with(alpha: 0)]),
                               startCenter: rebound, startRadius: 0, endCenter: rebound, endRadius: r * 0.3, options: [])
        // A crisp specular streak along the rim, softened by its own glow.
        ctx.setShadow(offset: .zero, blur: r * 0.06, color: c.glint.cg)
        ctx.setStrokeColor(c.glint.with(alpha: 0.85).cg)
        ctx.setLineCap(.round)
        ctx.setLineWidth(r * 0.03)
        ctx.addArc(center: center, radius: (r + inner) / 2, startAngle: .pi * 1.1, endAngle: .pi * 1.38, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

/// Saucepan handle for the copper variant: a tapered, polished bar running from the large bowl
/// towards the upper-left corner, fixed with two rivets.
func drawPanHandle(_ ctx: CGContext, bowlCenter: CGPoint, radius r: CGFloat, palette p: Palette) {
    guard case .copper(let c) = p.bowl else { return }
    let angle: CGFloat = .pi * 1.25 // towards the top-left corner (y points down)
    ctx.saveGState()
    ctx.translateBy(x: bowlCenter.x, y: bowlCenter.y)
    ctx.rotate(by: angle)
    // Local space: x runs along the handle, away from the bowl.
    let start = r * 0.9, end = r * 2.6
    let path = CGMutablePath()
    path.move(to: CGPoint(x: start, y: -r * 0.15))
    path.addLine(to: CGPoint(x: end, y: -r * 0.1))
    path.addArc(center: CGPoint(x: end, y: 0), radius: r * 0.1, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    path.addLine(to: CGPoint(x: start, y: r * 0.15))
    path.closeSubpath()
    // Hanging hole near the end.
    let hole = CGPath(ellipseIn: circle(CGPoint(x: end - r * 0.02, y: 0), r * 0.04), transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: r * 0.07, height: -r * 0.07), blur: r * 0.2, color: p.shadow.cg)
    ctx.addPath(path)
    ctx.setFillColor(c.deep.cg)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.addPath(hole)
    ctx.clip(using: .evenOdd)
    // Rounded bar: bright along its spine, darker towards the edges.
    ctx.drawLinearGradient(gradient([c.deep, c.mid, c.glint, c.bright, c.mid, c.deep], [0, 0.18, 0.4, 0.55, 0.8, 1]),
                           start: CGPoint(x: 0, y: r * 0.15), end: CGPoint(x: 0, y: -r * 0.15), options: [])
    ctx.restoreGState()
    // Rivets.
    for x in [start + r * 0.16, start + r * 0.38] {
        let rivet = circle(CGPoint(x: x, y: 0), r * 0.035)
        ctx.drawRadialGradient(gradient([c.glint, c.mid, c.deep]),
                               startCenter: CGPoint(x: x + r * 0.01, y: r * 0.01), startRadius: 0,
                               endCenter: CGPoint(x: x, y: 0), endRadius: r * 0.035, options: [])
        ctx.setStrokeColor(c.deep.with(alpha: 0.6).cg)
        ctx.setLineWidth(r * 0.006)
        ctx.strokeEllipse(in: rivet)
    }
    ctx.restoreGState()
}

func leafPath(center: CGPoint, length: CGFloat, width: CGFloat, angle: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let half = length / 2
    path.move(to: CGPoint(x: -half, y: 0))
    path.addQuadCurve(to: CGPoint(x: half, y: 0), control: CGPoint(x: 0, y: -width))
    path.addQuadCurve(to: CGPoint(x: -half, y: 0), control: CGPoint(x: 0, y: width))
    path.closeSubpath()
    var t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
    return path.copy(using: &t) ?? path
}

// Finely chopped herbs: a heap with fine flecks of lighter and darker green.
func herbs(_ p: Palette) -> (CGContext, CGPoint, CGFloat) -> Void {
    { ctx, c, r in
        powder(p.herb, p.herbLight)(ctx, c, r)
        let heap = r * 0.78
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, heap))
        ctx.clip()
        var rng = SeededRandom(state: 11)
        for i in 0..<260 {
            let a = rng.next() * .pi * 2
            let d = sqrt(rng.next()) * heap
            let pt = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let len = r * (0.05 + rng.next() * 0.05)
            let color = i % 2 == 0 ? p.herbDark : p.herbLight
            ctx.setFillColor(color.with(alpha: 0.85).cg)
            ctx.addPath(leafPath(center: pt, length: len, width: len * 0.45, angle: rng.next() * .pi))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}

// Ground spice: a smooth heap, lit softly from the top left.
func powder(_ base: RGB, _ light: RGB) -> (CGContext, CGPoint, CGFloat) -> Void {
    { ctx, c, r in
        let heap = r * 0.78
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, heap))
        ctx.clip()
        let hl = CGPoint(x: c.x - heap * 0.30, y: c.y - heap * 0.30)
        ctx.drawRadialGradient(gradient([light, base]), startCenter: hl, startRadius: 0, endCenter: c, endRadius: heap, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }
}

// MARK: - Grounds

/// Smooth value noise in [0, 1].
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

/// An edge-glued cutting board seen from above: strips of wood running across the icon, each with
/// its own tone, long and gently wavering grain lines, fine pores and a hairline glue joint.
func woodImage(base: RGB, light: RGB, dark: RGB) -> CGImage {
    let n = Int(size)
    var pixels = [UInt8](repeating: 255, count: n * n * 4)
    let warp = Noise(seed: 3), tone = Noise(seed: 7), pores = Noise(seed: 11)
    let stripHeight: Float = 205
    let stripTones: [Float] = [0.35, 0.8, 0.15, 0.6, 0.95, 0.3]
    func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    let base3 = [Float(base.r), Float(base.g), Float(base.b)]
    let light3 = [Float(light.r), Float(light.g), Float(light.b)]
    let dark3 = [Float(dark.r), Float(dark.g), Float(dark.b)]
    for py in 0..<n {
        // Strips are offset so no joint runs through the icon's exact center.
        let sy = Float(py) + 60
        let strip = Int(sy / stripHeight)
        let inStrip = sy - Float(strip) * stripHeight
        let seed = Float(strip) * 97.3
        for px in 0..<n {
            let x = Float(px), y = Float(py)
            // Grain coordinate: mostly y, gently pushed around by low-frequency warp along x.
            let w = warp.fbm(x * 0.0011 + seed, y * 0.004 + seed, octaves: 3)
            let g = y * 0.05 + w * 4.5 + seed
            let line = 0.5 + 0.5 * sin(g * 2 * .pi)
            let grain = pow(line, 10)                       // thin late-wood lines
            let streak = pores.fbm(x * 0.006 + seed, y * 0.35, octaves: 2) // fine pores along the grain
            var t = stripTones[strip % stripTones.count] * 0.85 + tone.fbm(x * 0.002 + seed, y * 0.01, octaves: 3) * 0.5
            t = min(max(t, 0), 1)                           // 0 = light, 1 = base
            var rgb = (0..<3).map { lerp(light3[$0], base3[$0], t) }
            var darkAmount = grain * 0.32 + max(0, streak - 0.55) * 0.55
            // Glue joint: a hairline at the strip edge, slightly softened.
            let edge = min(inStrip, stripHeight - inStrip)
            if edge < 2.2 { darkAmount += (1 - edge / 2.2) * 0.35 }
            darkAmount = min(1, darkAmount)
            rgb = (0..<3).map { lerp(rgb[$0], dark3[$0], darkAmount) }
            let i = (py * n + px) * 4
            pixels[i] = UInt8(max(0, min(255, rgb[0] * 255)))
            pixels[i + 1] = UInt8(max(0, min(255, rgb[1] * 255)))
            pixels[i + 2] = UInt8(max(0, min(255, rgb[2] * 255)))
        }
    }
    let data = CFDataCreate(nil, pixels, pixels.count)!
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: sRGB,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func drawGround(_ ctx: CGContext, _ p: Palette) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    switch p.ground {
    case .transparent:
        ctx.clear(full)
    case .linear(let top, let low):
        ctx.drawLinearGradient(gradient([top, low]), start: .zero, end: CGPoint(x: 0, y: size), options: [])
    case .radial(let inner, let outer):
        ctx.setFillColor(outer.cg)
        ctx.fill(full)
        let c = CGPoint(x: size * 0.36, y: size * 0.3)
        ctx.drawRadialGradient(gradient([inner, outer]), startCenter: c, startRadius: 0, endCenter: c, endRadius: size * 0.95,
                               options: [.drawsAfterEndLocation])
    case .wood(let base, let light, let dark):
        // The context is flipped; the grain has no up or down, so drawing it flipped is fine.
        ctx.draw(woodImage(base: base, light: light, dark: dark), in: full)
    }

    if let speck = p.groundSpecks {
        var rng = SeededRandom(state: 42)
        for _ in 0..<70 {
            let pt = CGPoint(x: rng.next() * size, y: rng.next() * size)
            let s = 1.0 + pow(rng.next(), 3) * 2.6
            ctx.setFillColor(speck.with(alpha: 0.12 + rng.next() * 0.3).cg)
            ctx.fillEllipse(in: circle(pt, s))
        }
    }

    if p.vignette > 0 {
        let black = RGB(0x000000)
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient([black.with(alpha: 0), black.with(alpha: p.vignette)], [0.55, 1]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: size * 0.75,
                               options: [.drawsAfterEndLocation])
    }
}

// MARK: - Rendering

func render(_ p: Palette) -> CGImage {
    var hasAlpha = false
    if case .transparent = p.ground { hasAlpha = true }
    let info: UInt32 = hasAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: info)!

    // Flip to a top-left origin.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)

    drawGround(ctx, p)

    // Composition: big bowl upper-left, two small bowls lower-right, balanced around the optical center.
    let big = CGPoint(x: 432, y: 432)
    drawPanHandle(ctx, bowlCenter: big, radius: 250, palette: p)
    drawBowl(ctx, center: big, radius: 250, palette: p, contents: herbs(p))
    drawBowl(ctx, center: CGPoint(x: 770, y: 640), radius: 118, palette: p, contents: powder(p.paprika, p.paprikaLight))
    drawBowl(ctx, center: CGPoint(x: 520, y: 805), radius: 100, palette: p, contents: powder(p.saffron, p.saffronLight))

    return ctx.makeImage()!
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
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
}

func writeJSON(_ json: String, to dir: URL) throws {
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func appIconContents(_ name: String) -> String {
    """
    {
      "images": [
        {
          "filename": "\(name).png",
          "idiom": "universal",
          "platform": "ios",
          "size": "1024x1024"
        },
        {
          "appearances": [
            {
              "appearance": "luminosity",
              "value": "dark"
            }
          ],
          "filename": "\(name)-dark.png",
          "idiom": "universal",
          "platform": "ios",
          "size": "1024x1024"
        },
        {
          "appearances": [
            {
              "appearance": "luminosity",
              "value": "tinted"
            }
          ],
          "filename": "\(name)-tinted.png",
          "idiom": "universal",
          "platform": "ios",
          "size": "1024x1024"
        }
      ],
      "info": {
        "author": "xcode",
        "version": 1
      }
    }
    """
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

let resources = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MealMate/Resources")
let fm = FileManager.default
let alternatesCatalog = resources.appendingPathComponent("AppIcons.xcassets")
try fm.createDirectory(at: alternatesCatalog, withIntermediateDirectories: true)
try writeJSON("{\n  \"info\": {\n    \"author\": \"xcode\",\n    \"version\": 1\n  }\n}\n", to: alternatesCatalog)

for variant in alternates {
    let iconName = "AppIcon" + variant.suffix
    let iconDir = variant.suffix.isEmpty
        ? resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
        : alternatesCatalog.appendingPathComponent("\(iconName).appiconset")
    try fm.createDirectory(at: iconDir, withIntermediateDirectories: true)
    if !variant.suffix.isEmpty { try writeJSON(appIconContents(iconName), to: iconDir) }

    var images: [Appearance: CGImage] = [:]
    for appearance in Appearance.allCases {
        let image = render(variant.palette(appearance))
        images[appearance] = image
        let file = switch appearance {
        case .light: "\(iconName).png"
        case .dark: "\(iconName)-dark.png"
        case .tinted: "\(iconName)-tinted.png"
        }
        try writePNG(image, to: iconDir.appendingPathComponent(file))
    }

    let previewName = "IconPreview" + (variant.suffix.isEmpty ? "Default" : variant.suffix)
    let previewDir = alternatesCatalog.appendingPathComponent("\(previewName).imageset")
    try fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
    try writeJSON(imageSetContents(previewName), to: previewDir)
    try writePNG(preview(images[.light]!), to: previewDir.appendingPathComponent("\(previewName).png"))
    try writePNG(preview(images[.dark]!), to: previewDir.appendingPathComponent("\(previewName)-dark.png"))
    print("wrote \(iconName) + \(previewName)")
}
