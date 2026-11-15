// make_icon_mac.swift - draws the GJ Materia icon (1024x1024 PNG): a red Meteor hanging in a dark
// sky, a three-barrelled revolver across it (Vincent's colours: gunmetal and gold) with "GJ" on
// the grip, "VII" in the top-left corner, and a red cloak's torn edge along the bottom. An original drawing, nothing from the
// game. tools/make_icon_mac.sh turns it into macos/icon/AppIcon.icns.
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
func fill(_ p: CGPath, _ g: CGGradient, _ a: CGPoint, _ b: CGPoint) {
    ctx.saveGState(); ctx.addPath(p); ctx.clip()
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

// ---- the tile and the sky
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.45))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0.05, 0.03, 0.05)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()   // everything below is inside the tile
ctx.addPath(tilePath); ctx.clip()
ctx.drawLinearGradient(grad([(0, rgb(0.22, 0.05, 0.06)), (0.55, rgb(0.08, 0.03, 0.06)), (1, rgb(0.02, 0.02, 0.04))]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
for (x, y, s) in [(190.0, 860.0, 3.0), (300, 790, 2), (420, 880, 2.5), (250, 700, 1.8), (520, 840, 2), (160, 620, 2)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.addEllipse(in: CGRect(x: x, y: y, width: s * 2, height: s * 2)); ctx.setFillColor(rgb(1, 0.9, 0.85, 0.7)); ctx.fillPath()
}

// the Meteor: a burning red sphere up and right, with its glow
let mc = CGPoint(x: 650, y: 690), mr: CGFloat = 200
ctx.drawRadialGradient(grad([(0, rgb(1, 0.35, 0.1, 0.55)), (1, rgb(1, 0.2, 0.05, 0))]),
                       startCenter: mc, startRadius: mr * 0.8, endCenter: mc, endRadius: mr * 1.9, options: [])
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: mc.x - mr, y: mc.y - mr, width: mr * 2, height: mr * 2)); ctx.clip()
ctx.drawRadialGradient(grad([(0, rgb(1, 0.85, 0.45)), (0.3, rgb(1, 0.45, 0.12)), (0.75, rgb(0.72, 0.1, 0.05)), (1, rgb(0.35, 0.03, 0.03))]),
                       startCenter: CGPoint(x: mc.x - 50, y: mc.y - 40), startRadius: 0, endCenter: mc, endRadius: mr, options: [.drawsAfterEndLocation])
// dark rock patches and a few glowing fissures
for (dx, dy, w, h) in [(-90.0, 60.0, 110.0, 70.0), (40, -90, 130, 80), (70, 70, 80, 60), (-120, -60, 70, 90)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    ctx.addEllipse(in: CGRect(x: mc.x + dx - w / 2, y: mc.y + dy - h / 2, width: w, height: h)); ctx.setFillColor(rgb(0.35, 0.04, 0.03, 0.22)); ctx.fillPath()
}
ctx.setBlendMode(.screen)
for pts in [[(-150.0, 20.0), (-90, 0), (-60, 30), (-10, 10), (40, 40)], [(20, -150), (0, -100), (30, -60), (10, -20)], [(90, 120), (60, 80), (100, 40), (150, 30)]] as [[(CGFloat, CGFloat)]] {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: mc.x + pts[0].0, y: mc.y + pts[0].1))
    for q in pts.dropFirst() { p.addLine(to: CGPoint(x: mc.x + q.0, y: mc.y + q.1)) }
    ctx.addPath(p); ctx.setStrokeColor(rgb(1, 0.82, 0.4, 0.4)); ctx.setLineWidth(3.5); ctx.setLineJoin(.round); ctx.strokePath()
}
ctx.setBlendMode(.normal)
ctx.restoreGState()

// the cloak along the bottom: torn red cloth
let cloak = CGMutablePath()
cloak.move(to: CGPoint(x: 100, y: 100))
cloak.addLine(to: CGPoint(x: 100, y: 240))
var cx: CGFloat = 100
var up = true
for w in [70, 55, 90, 60, 75, 50, 85, 65, 80, 60, 84] as [CGFloat] {
    cx += w
    cloak.addLine(to: CGPoint(x: min(cx, 924), y: up ? 170 + (w - 50) : 240 - (w - 50) * 0.8))
    up.toggle()
}
cloak.addLine(to: CGPoint(x: 924, y: 210))
cloak.addLine(to: CGPoint(x: 924, y: 100))
cloak.closeSubpath()
fill(cloak, grad([(0, rgb(0.55, 0.03, 0.07)), (1, rgb(0.18, 0.01, 0.03))]), CGPoint(x: 512, y: 240), CGPoint(x: 512, y: 100))

// ---- the revolver: three barrels, drawn pointing right, then turned up about 22 degrees
let barrels: [CGFloat] = [36, 0, -36]                 // centre lines; each 32 high
let barrelLen: CGFloat = 400
let cyl = rr(-150, -64, 160, 128, 30)
let frame = CGMutablePath()                           // from the cylinder back to the grip
frame.move(to: CGPoint(x: -140, y: 62)); frame.addLine(to: CGPoint(x: -250, y: 62))
frame.addQuadCurve(to: CGPoint(x: -280, y: 20), control: CGPoint(x: -280, y: 60))
frame.addLine(to: CGPoint(x: -230, y: -56)); frame.addLine(to: CGPoint(x: -140, y: -56)); frame.closeSubpath()
let grip = CGMutablePath()
grip.move(to: CGPoint(x: -282, y: 22)); grip.addLine(to: CGPoint(x: -200, y: -50))
grip.addQuadCurve(to: CGPoint(x: -250, y: -240), control: CGPoint(x: -205, y: -150))
grip.addQuadCurve(to: CGPoint(x: -345, y: -215), control: CGPoint(x: -300, y: -262))
grip.addQuadCurve(to: CGPoint(x: -282, y: 22), control: CGPoint(x: -330, y: -80))
grip.closeSubpath()
let hammer = CGMutablePath()
hammer.move(to: CGPoint(x: -250, y: 58)); hammer.addLine(to: CGPoint(x: -225, y: 58))
hammer.addQuadCurve(to: CGPoint(x: -300, y: 118), control: CGPoint(x: -250, y: 105)); hammer.closeSubpath()
let sight = rr(barrelLen - 70, 50, 40, 22, 6)

ctx.saveGState()
ctx.translateBy(x: 470, y: 470)
ctx.rotate(by: 0.38)
// shadow from one silhouette
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: rgb(0, 0, 0, 0.8))
let body = CGMutablePath()
for y in barrels { body.addPath(rr(-40, y - 16, barrelLen, 32, 14)) }
body.addPath(cyl); body.addPath(frame); body.addPath(grip); body.addPath(hammer); body.addPath(sight)
ctx.addPath(body); ctx.setFillColor(rgb(0.1, 0.1, 0.12)); ctx.fillPath()
ctx.restoreGState()

let steel = grad([(0, rgb(0.86, 0.87, 0.92)), (0.3, rgb(0.55, 0.57, 0.63)), (0.62, rgb(0.2, 0.21, 0.25)), (1, rgb(0.42, 0.44, 0.5))])
let gold = grad([(0, rgb(1, 0.9, 0.55)), (0.5, rgb(0.86, 0.6, 0.18)), (1, rgb(0.5, 0.3, 0.06))])
let goldLine = rgb(0.84, 0.6, 0.2)
// grip: black with a gold edge
fill(grip, grad([(0, rgb(0.2, 0.17, 0.18)), (1, rgb(0.05, 0.04, 0.05))]), CGPoint(x: -260, y: 0), CGPoint(x: -300, y: -240))
ctx.addPath(grip); ctx.setStrokeColor(goldLine); ctx.setLineWidth(7); ctx.strokePath()
fill(hammer, steel, CGPoint(x: -260, y: 118), CGPoint(x: -260, y: 58))
fill(frame, steel, CGPoint(x: -200, y: 62), CGPoint(x: -200, y: -56))
ctx.addPath(frame); ctx.setStrokeColor(rgb(0.1, 0.1, 0.12, 0.6)); ctx.setLineWidth(3); ctx.strokePath()
// trigger guard and trigger
let guardPath = CGMutablePath()
guardPath.addArc(center: CGPoint(x: -185, y: -70), radius: 46, startAngle: .pi * 0.05, endAngle: .pi * 1.0, clockwise: true)
ctx.addPath(guardPath); ctx.setStrokeColor(goldLine); ctx.setLineWidth(12); ctx.setLineCap(.round); ctx.strokePath()
let trig = CGMutablePath(); trig.move(to: CGPoint(x: -180, y: -56)); trig.addQuadCurve(to: CGPoint(x: -200, y: -100), control: CGPoint(x: -175, y: -85))
ctx.addPath(trig); ctx.setStrokeColor(rgb(0.15, 0.15, 0.17)); ctx.setLineWidth(9); ctx.strokePath()
// barrels, bottom one first; gold bands and dark muzzles
for y in barrels.reversed() {
    fill(rr(-40, y - 16, barrelLen, 32, 14), steel, CGPoint(x: 0, y: y + 16), CGPoint(x: 0, y: y - 16))
    fill(rr(barrelLen - 70, y - 17, 26, 34, 6), gold, CGPoint(x: 0, y: y + 17), CGPoint(x: 0, y: y - 17))
    ctx.addEllipse(in: CGRect(x: barrelLen - 54, y: y - 8, width: 12, height: 16)); ctx.setFillColor(rgb(0.03, 0.03, 0.04)); ctx.fillPath()
}
fill(sight, gold, CGPoint(x: 0, y: 72), CGPoint(x: 0, y: 50))
// cylinder: steel with flutes, a gold rim
fill(cyl, steel, CGPoint(x: -70, y: 64), CGPoint(x: -70, y: -64))
for k in 0..<3 {
    ctx.addPath(rr(-132, -44 + CGFloat(k) * 34, 124, 18, 9)); ctx.setFillColor(rgb(0.08, 0.08, 0.1, 0.55)); ctx.fillPath()
}
ctx.addPath(cyl); ctx.setStrokeColor(goldLine); ctx.setLineWidth(7); ctx.strokePath()
// "GJ" on the grip, in gold
let font = CTFontCreateWithName("Didot-Bold" as CFString, 66, nil)
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "GJ", attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0.97, 0.8, 0.4)]))
ctx.saveGState()
ctx.translateBy(x: -268, y: -125)
ctx.rotate(by: 1.33)
let tb = CTLineGetImageBounds(line, ctx)
ctx.textPosition = CGPoint(x: -tb.width / 2 - tb.minX, y: -tb.height / 2 - tb.minY)
ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: rgb(0, 0, 0, 0.9))
CTLineDraw(line, ctx)
ctx.restoreGState()
ctx.restoreGState()   // the revolver's frame of reference

// "VII" in the top-left corner: silver with a gold edge, engraved
do {
    let f = CTFontCreateWithName("Didot-Bold" as CFString, 128, nil)
    let l = CTLineCreateWithAttributedString(NSAttributedString(string: "VII", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(1, 1, 1)]))
    let b = CTLineGetImageBounds(l, ctx)
    let o = CGPoint(x: 228 - b.minX, y: 812 - b.maxY)
    ctx.saveGState()   // gold outline under it, with a shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: rgb(0, 0, 0, 0.85))
    ctx.textPosition = o
    ctx.setTextDrawingMode(.fillStroke)
    ctx.setLineWidth(8); ctx.setLineJoin(.round)
    ctx.setStrokeColor(rgb(0.86, 0.6, 0.2)); ctx.setFillColor(rgb(0.86, 0.6, 0.2))
    CTLineDraw(l, ctx)
    ctx.restoreGState()
    ctx.saveGState()   // the letters: a silver gradient
    ctx.textPosition = o
    ctx.setTextDrawingMode(.clip)
    CTLineDraw(l, ctx)
    ctx.drawLinearGradient(grad([(0, rgb(0.98, 0.98, 1)), (0.5, rgb(0.72, 0.74, 0.8)), (1, rgb(0.42, 0.44, 0.5))]),
                           start: CGPoint(x: 0, y: o.y + b.maxY), end: CGPoint(x: 0, y: o.y + b.minY), options: [])
    ctx.restoreGState()
}

ctx.restoreGState()   // the tile

let img = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
