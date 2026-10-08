#!/usr/bin/env swift
// MealMate app icon generator.
//
// Usage:  swift Design/make-icon.swift [output-dir]
// Default output dir: MealMate/Resources/Assets.xcassets/AppIcon.appiconset
//
// Run from the repo root. Writes three 1024x1024 PNGs:
//   AppIcon.png         default (light) icon, opaque, no alpha channel
//   AppIcon-dark.png    dark appearance (transparent background, the system supplies the dark backdrop)
//   AppIcon-tinted.png  tinted appearance (grayscale mark on black, the system tints it)
//
// The mark: ingredients prepped before cooking, seen from above. One larger prep bowl and two small ones,
// each holding a single prepared ingredient (herbs, paprika, saffron), on a soft oat ground.

import AppKit
import CoreGraphics

let size: CGFloat = 1024

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
    private init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) { self.r = r; self.g = g; self.b = b; self.a = a }
}

enum Appearance { case light, dark, tinted }

struct Palette {
    let background: RGB?        // nil = transparent
    let backgroundLow: RGB?     // bottom of the very soft vertical tone shift
    let bowlRim: RGB
    let bowlInside: RGB
    let shadow: RGB
    let herb: RGB
    let herbDark: RGB
    let herbLight: RGB
    let paprika: RGB
    let paprikaLight: RGB
    let saffron: RGB
    let saffronLight: RGB

    static func forAppearance(_ appearance: Appearance) -> Palette {
        switch appearance {
        case .light:
            return Palette(
                background: RGB(0xEFE9DC), backgroundLow: RGB(0xE6DECD),
                bowlRim: RGB(0xFCFAF6), bowlInside: RGB(0xF1ECE2),
                shadow: RGB(0x5A4A30, alpha: 0.24),
                herb: RGB(0x6E9A5A), herbDark: RGB(0x557D47), herbLight: RGB(0x8DB477),
                paprika: RGB(0xB95E40), paprikaLight: RGB(0xD9845F),
                saffron: RGB(0xE0AE4F), saffronLight: RGB(0xEEC877))
        case .dark:
            return Palette(
                background: nil, backgroundLow: nil,
                bowlRim: RGB(0x45423C), bowlInside: RGB(0x2F2D29),
                shadow: RGB(0x000000, alpha: 0.35),
                herb: RGB(0x86B070), herbDark: RGB(0x6A9658), herbLight: RGB(0xA6CA8E),
                paprika: RGB(0xD06E4C), paprikaLight: RGB(0xE8946E),
                saffron: RGB(0xE8B85A), saffronLight: RGB(0xF4D284))
        case .tinted:
            return Palette(
                background: RGB(0x000000), backgroundLow: RGB(0x000000),
                bowlRim: RGB(0x5C5C5C), bowlInside: RGB(0x3A3A3A),
                shadow: RGB(0x000000, alpha: 0.0),
                herb: RGB(0xE6E6E6), herbDark: RGB(0xBDBDBD), herbLight: RGB(0xFFFFFF),
                paprika: RGB(0xB8B8B8), paprikaLight: RGB(0xDADADA),
                saffron: RGB(0xD4D4D4), saffronLight: RGB(0xF2F2F2))
        }
    }
}

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

func drawBowl(_ ctx: CGContext, center: CGPoint, radius r: CGFloat, palette p: Palette, contents: (CGContext, CGPoint, CGFloat) -> Void) {
    // Soft contact shadow, light from the top.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: r * 0.10), blur: r * 0.24, color: p.shadow.cg)
    ctx.setFillColor(p.bowlRim.cg)
    ctx.fillEllipse(in: circle(center, r))
    ctx.restoreGState()

    // Rim + inside of the bowl.
    ctx.setFillColor(p.bowlRim.cg)
    ctx.fillEllipse(in: circle(center, r))
    let inner = r * 0.82
    ctx.setFillColor(p.bowlInside.cg)
    ctx.fillEllipse(in: circle(center, inner))

    // Contents, clipped to the bowl's inside.
    ctx.saveGState()
    ctx.addEllipse(in: circle(center, inner))
    ctx.clip()
    contents(ctx, center, inner)
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
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let gradient = CGGradient(colorsSpace: space, colors: [light.cg, base.cg] as CFArray, locations: [0, 1])!
        let hl = CGPoint(x: c.x - heap * 0.30, y: c.y - heap * 0.30)
        ctx.drawRadialGradient(gradient, startCenter: hl, startRadius: 0, endCenter: c, endRadius: heap, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }
}

func render(_ appearance: Appearance) -> CGImage {
    let p = Palette.forAppearance(appearance)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let hasAlpha = p.background == nil
    let info: UInt32 = hasAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!

    // Flip to a top-left origin.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)

    if let top = p.background, let low = p.backgroundLow {
        let gradient = CGGradient(colorsSpace: space, colors: [top.cg, low.cg] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    } else {
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // Composition: big bowl upper-left, two small bowls lower-right, balanced around the optical center.
    drawBowl(ctx, center: CGPoint(x: 432, y: 432), radius: 250, palette: p, contents: herbs(p))
    drawBowl(ctx, center: CGPoint(x: 770, y: 640), radius: 118, palette: p, contents: powder(p.paprika, p.paprikaLight))
    drawBowl(ctx, center: CGPoint(x: 520, y: 805), radius: 100, palette: p, contents: powder(p.saffron, p.saffronLight))

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "MealMate/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (appearance, name) in [(Appearance.light, "AppIcon.png"), (.dark, "AppIcon-dark.png"), (.tinted, "AppIcon-tinted.png")] {
    let url = outDir.appendingPathComponent(name)
    try writePNG(render(appearance), to: url)
    print("wrote \(url.path)")
}
