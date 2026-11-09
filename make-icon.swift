// App icon: Claude orange with a question mark in the menu bar font (Monoplex KR Nerd Text Italic)
// A restrained Liquid Glass look: soft vertical gradient, top light, edge highlight, glassy glyph
// Usage: swift make-icon.swift <output 1024px PNG>
import AppKit

func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "fonts/MonoplexKRNerd-TextItalic.ttf") as CFURL, .process, nil)

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

// macOS icon grid: an 824px rounded square on a 1024 canvas
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185
let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

// 1) Drop shadow (very light)
NSGraphicsContext.saveGraphicsState()
let drop = NSShadow(); drop.shadowOffset = NSSize(width: 0, height: -14); drop.shadowBlurRadius = 30
drop.shadowColor = NSColor.black.withAlphaComponent(0.22); drop.set()
rgb(0xD97757).setFill(); tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

// 2) Base: slightly lighter orange at the top, deeper at the bottom
NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
NSGradient(colors: [rgb(0xE89273), rgb(0xD97757), rgb(0xC9694B)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
    .draw(in: tile, angle: -90)
// 3) Top light: a soft glow fading downward
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0.04),
                    NSColor.white.withAlphaComponent(0)], atLocations: [0, 0.35, 0.6], colorSpace: .sRGB)!
    .draw(in: tile, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// 4) Edge highlight: a thin rim, bright at the top, fading toward the bottom
NSGraphicsContext.saveGraphicsState()
let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 3, dy: 3), xRadius: radius - 3, yRadius: radius - 3)
rim.lineWidth = 6
ctx.saveGState()
ctx.addPath(rim.cgPath); ctx.setLineWidth(6); ctx.replacePathWithStrokedPath(); ctx.clip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0.08),
                    NSColor.white.withAlphaComponent(0.18)], atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
    .draw(in: tile, angle: -90)
ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

// 5) Question mark: larger and bolder, with a subtle porcelain finish
let font = NSFont(name: "MonoplexKRNerd-TextItalic", size: 700)!
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "?", attributes: [.font: font]))
let ink = CTLineGetImageBounds(line, ctx)
let origin = CGPoint(x: tile.midX - ink.midX, y: tile.midY - ink.midY + 4)
// glyph outline as a path
var glyphPath = CGMutablePath()
let runs = CTLineGetGlyphRuns(line) as! [CTRun]
for run in runs {
    let attrs = CTRunGetAttributes(run) as! [CFString: Any]
    let runFont = attrs[kCTFontAttributeName] as! CTFont
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n); var pos = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs); CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
    for i in 0..<n {
        if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
            glyphPath.addPath(g, transform: CGAffineTransform(translationX: origin.x + pos[i].x, y: origin.y + pos[i].y))
        }
    }
}
// Separate the dot from the hook a little more: split the outline into its pieces,
// move the lowest piece (the dot) down, then re-center the whole mark in the tile.
let dotGap: CGFloat = 15
var pieces: [CGMutablePath] = []
glyphPath.applyWithBlock { el in
    let p = el.pointee.points
    switch el.pointee.type {
    case .moveToPoint: let m = CGMutablePath(); m.move(to: p[0]); pieces.append(m)
    case .addLineToPoint: pieces.last?.addLine(to: p[0])
    case .addQuadCurveToPoint: pieces.last?.addQuadCurve(to: p[1], control: p[0])
    case .addCurveToPoint: pieces.last?.addCurve(to: p[2], control1: p[0], control2: p[1])
    case .closeSubpath: pieces.last?.closeSubpath()
    @unknown default: break
    }
}
let dotTop = pieces.map { $0.boundingBox.maxY }.min() ?? 0
let moved = CGMutablePath()
for piece in pieces {
    let isDot = piece.boundingBox.maxY <= dotTop + 1   // the dot sits entirely below the hook
    moved.addPath(piece, transform: isDot ? CGAffineTransform(translationX: 0, y: -dotGap) : .identity)
}
let mb = moved.boundingBox
let recenter = CGAffineTransform(translationX: 0, y: (tile.midY - mb.midY) + 4)
glyphPath = CGMutablePath(); glyphPath.addPath(moved, transform: recenter)

// Bolder: the glyph plus a rounded outline stroke, rendered into a mask
let boldStroke = glyphPath.copy(strokingWithWidth: 26, lineCap: .round, lineJoin: .round, miterLimit: 10)
let W = Int(S)
let maskCtx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
maskCtx.setFillColor(gray: 0, alpha: 1); maskCtx.fill(CGRect(x: 0, y: 0, width: W, height: W))
maskCtx.setFillColor(gray: 1, alpha: 1)
maskCtx.addPath(glyphPath); maskCtx.fillPath()
maskCtx.addPath(boldStroke); maskCtx.fillPath()
let mask = maskCtx.makeImage()!
let shape = CGRect(x: 0, y: 0, width: S, height: S)
let gb = glyphPath.boundingBox.insetBy(dx: -13, dy: -13)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// soft shadow under the glyph
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: rgb(0x7A3A24, 0.38).cgColor)
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.clip(to: shape, mask: mask)
ctx.setFillColor(rgb(0xFAF6EF).cgColor); ctx.fill(shape)
ctx.endTransparencyLayer()
ctx.restoreGState()

ctx.saveGState()
ctx.clip(to: shape, mask: mask)
// porcelain body: warm white, a touch cooler at the top
let body = CGGradient(colorsSpace: srgb, colors: [rgb(0xFFFFFF).cgColor, rgb(0xFBF6EF).cgColor, rgb(0xEFE4D6).cgColor] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawLinearGradient(body, start: CGPoint(x: gb.midX, y: gb.maxY), end: CGPoint(x: gb.midX, y: gb.minY), options: [])
// glaze highlight: a soft specular glow toward the upper left
let glaze = CGGradient(colorsSpace: srgb, colors: [rgb(0xFFFFFF, 0.9).cgColor, rgb(0xFFFFFF, 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glaze, startCenter: CGPoint(x: gb.minX + gb.width * 0.38, y: gb.maxY - gb.height * 0.18), startRadius: 0,
                       endCenter: CGPoint(x: gb.minX + gb.width * 0.38, y: gb.maxY - gb.height * 0.18), endRadius: gb.width * 0.55, options: [])
// soft inner shading along the edges, like light on a glazed rounded form:
// the area OUTSIDE the letter casts a shadow that only shows INSIDE it
let invCtx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGImageAlphaInfo.none.rawValue)!
invCtx.setFillColor(gray: 1, alpha: 1); invCtx.fill(CGRect(x: 0, y: 0, width: W, height: W))
invCtx.clip(to: CGRect(x: 0, y: 0, width: W, height: W), mask: mask)
invCtx.setFillColor(gray: 0, alpha: 1); invCtx.fill(CGRect(x: 0, y: 0, width: W, height: W))
let inverse = invCtx.makeImage()!
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: rgb(0x9C6B52, 0.32).cgColor)
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.clip(to: shape, mask: inverse)
ctx.setFillColor(rgb(0x9C6B52).cgColor); ctx.fill(shape)
ctx.endTransparencyLayer()
ctx.restoreGState()
// faint fired-clay speckle (very light, fixed seed so the icon is reproducible)
var seed: UInt64 = 42
func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<1400 {
    let p = CGPoint(x: gb.minX + rnd() * gb.width, y: gb.minY + rnd() * gb.height)
    let r = 0.6 + rnd() * 1.3
    ctx.setFillColor(rgb(0x8A6A55, 0.035 + rnd() * 0.045).cgColor)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
