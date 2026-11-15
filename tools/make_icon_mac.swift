// make_icon_mac.swift - draws the GJ Materia icon (1024x1024 PNG): a crimson Materia orb (Vincent's
// colours) in a gold setting on a dark tile, "GJ" (Good JOE) in gold inside it. An original drawing,
// nothing from the game. tools/make_icon_mac.sh turns it into macos/icon/AppIcon.icns.
//   swift tools/make_icon_mac.swift out.png
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

// the tile (macOS icon grid: 824 px rounded square, centred)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.45))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0.07, 0.05, 0.06)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
ctx.drawLinearGradient(grad([(0, rgb(0.16, 0.08, 0.09)), (1, rgb(0.03, 0.02, 0.03))]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// a crimson glow behind the orb
ctx.drawRadialGradient(grad([(0, rgb(0.75, 0.05, 0.1, 0.55)), (1, rgb(0.75, 0.05, 0.1, 0))]),
                       startCenter: CGPoint(x: 512, y: 500), startRadius: 0, endCenter: CGPoint(x: 512, y: 500), endRadius: 430, options: [])
// a cloak's folds sweeping up from the bottom (Vincent's cape)
for i in 0..<3 {
    let p = CGMutablePath()
    let lift = CGFloat(i) * 70
    p.move(to: CGPoint(x: 100, y: 100))
    p.addCurve(to: CGPoint(x: 924, y: 330 - lift), control1: CGPoint(x: 360, y: 300 - lift), control2: CGPoint(x: 640, y: 120))
    p.addLine(to: CGPoint(x: 924, y: 100))
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(rgb(0.5, 0.02, 0.07, 0.22 + CGFloat(i) * 0.08)); ctx.fillPath()
}
ctx.restoreGState()

let c = CGPoint(x: 512, y: 520), r: CGFloat = 268
// the gold setting: a ring with four claws
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.6))
let ring = CGMutablePath()
ring.addEllipse(in: CGRect(x: c.x - r - 34, y: c.y - r - 34, width: (r + 34) * 2, height: (r + 34) * 2))
for k in 0..<4 {
    let a = CGFloat(k) * .pi / 2 + .pi / 4
    let tip = CGPoint(x: c.x + cos(a) * (r + 66), y: c.y + sin(a) * (r + 66))
    let l = CGPoint(x: c.x + cos(a - 0.09) * (r + 26), y: c.y + sin(a - 0.09) * (r + 26))
    let rr = CGPoint(x: c.x + cos(a + 0.09) * (r + 26), y: c.y + sin(a + 0.09) * (r + 26))
    ring.move(to: l); ring.addLine(to: tip); ring.addLine(to: rr); ring.closeSubpath()
}
ctx.addPath(ring); ctx.setFillColor(rgb(0.85, 0.65, 0.25)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(ring); ctx.clip()
ctx.drawLinearGradient(grad([(0, rgb(1.0, 0.9, 0.55)), (0.45, rgb(0.86, 0.62, 0.2)), (1, rgb(0.45, 0.28, 0.06))]),
                       start: CGPoint(x: 300, y: 860), end: CGPoint(x: 720, y: 180), options: [])
ctx.restoreGState()

// the orb
let orb = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
ctx.saveGState()
ctx.addEllipse(in: orb); ctx.clip()
ctx.drawRadialGradient(grad([(0, rgb(1.0, 0.42, 0.42)), (0.35, rgb(0.86, 0.06, 0.12)), (0.8, rgb(0.42, 0.0, 0.04)), (1, rgb(0.2, 0.0, 0.02))]),
                       startCenter: CGPoint(x: c.x - 80, y: c.y + 90), startRadius: 0,
                       endCenter: c, endRadius: r, options: [.drawsAfterEndLocation])
// light swirling inside
ctx.setBlendMode(.screen)
for k in 0..<3 {
    let p = CGMutablePath()
    let rot = CGFloat(k) * 2.1
    p.addArc(center: c, radius: r * (0.55 + CGFloat(k) * 0.12), startAngle: rot, endAngle: rot + 1.9, clockwise: false)
    ctx.addPath(p); ctx.setStrokeColor(rgb(1, 0.45, 0.4, 0.22)); ctx.setLineWidth(18 - CGFloat(k) * 4); ctx.strokePath()
}
ctx.setBlendMode(.normal)
// rim shadow
ctx.drawRadialGradient(grad([(0.75, rgb(0, 0, 0, 0)), (1, rgb(0, 0, 0, 0.55))]),
                       startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
ctx.restoreGState()

// "GJ" in gold
let font = CTFontCreateWithName("Didot-Bold" as CFString, 250, nil)
let attr = NSAttributedString(string: "GJ", attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(1, 1, 1)])
let line = CTLineCreateWithAttributedString(attr)
let b = CTLineGetImageBounds(line, ctx)
let origin = CGPoint(x: c.x - b.width / 2 - b.minX, y: c.y - b.height / 2 - b.minY - 6)
// text as a mask, filled with a gold gradient, with a dark engraving shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 10, color: rgb(0.15, 0, 0.02, 0.85))
ctx.textPosition = origin
ctx.setTextDrawingMode(.fill)
ctx.setFillColor(rgb(0.9, 0.68, 0.28))
CTLineDraw(line, ctx)
ctx.restoreGState()
ctx.saveGState()
ctx.textPosition = origin
ctx.setTextDrawingMode(.clip)
CTLineDraw(line, ctx)
ctx.drawLinearGradient(grad([(0, rgb(1.0, 0.94, 0.66)), (0.5, rgb(0.93, 0.7, 0.27)), (1, rgb(0.6, 0.38, 0.1))]),
                       start: CGPoint(x: c.x, y: c.y + 130), end: CGPoint(x: c.x, y: c.y - 130), options: [])
ctx.restoreGState()

// the glass highlight
ctx.saveGState()
ctx.addEllipse(in: orb); ctx.clip()
let hl = CGRect(x: c.x - 200, y: c.y + 120, width: 210, height: 110)
ctx.addEllipse(in: hl); ctx.clip()
ctx.drawLinearGradient(grad([(0, rgb(1, 1, 1, 0.6)), (1, rgb(1, 1, 1, 0))]),
                       start: CGPoint(x: hl.midX, y: hl.maxY), end: CGPoint(x: hl.midX, y: hl.minY), options: [])
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x + 120, y: c.y - 170, width: 46, height: 30)); ctx.setFillColor(rgb(1, 0.8, 0.8, 0.35)); ctx.fillPath()
ctx.restoreGState()

let img = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
