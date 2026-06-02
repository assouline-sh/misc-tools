import AppKit
import CoreText

// AYFM icon — sunburst variations. A striped "sun" radiates toward the center where
// the speech bubble sits: notifications from everywhere collecting into one place.
// Terminal theme: amber on near-black, matching make_icon2.swift.
//
// Usage: swift make_sunburst.swift <style> <out.png>
//   converge   wedges with apex AT the center (rays point inward / collect in)
//   sun        alternating long/short rays around the bubble (classic sun)
//   fine       many thin slivers converging to center
//   emanate    rays start at a ring just outside the bubble and shoot outward

let S: CGFloat = 1024
let bg    = NSColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1)  // #0B0B0D
let amber = NSColor(red: 0.961, green: 0.651, blue: 0.137, alpha: 1)  // #F5A623

let style = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "converge"
let out   = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon_1024.png"

// 1024x1024 bitmap at 1:1 (no Retina scaling); alpha flattened on output.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("no bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }
ctx.setFillColor(bg.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

let cx: CGFloat = 512, cy: CGFloat = 512

func roundRect(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

// One ray = a quad from an inner arc to an outer arc, angular half-width `half`.
func ray(angle: CGFloat, half: CGFloat, innerR: CGFloat, outerR: CGFloat) {
    let a0 = angle - half, a1 = angle + half
    let p = CGMutablePath()
    p.move(to:    CGPoint(x: cx + innerR * cos(a0), y: cy + innerR * sin(a0)))
    p.addLine(to: CGPoint(x: cx + outerR * cos(a0), y: cy + outerR * sin(a0)))
    p.addLine(to: CGPoint(x: cx + outerR * cos(a1), y: cy + outerR * sin(a1)))
    p.addLine(to: CGPoint(x: cx + innerR * cos(a1), y: cy + innerR * sin(a1)))
    p.closeSubpath()
    ctx.addPath(p); ctx.fillPath()
}

// The bubble silhouette (rounded body + tail) filled in one color.
func bubbleShape(_ rect: CGRect, _ rad: CGFloat, _ color: NSColor) {
    ctx.setFillColor(color.cgColor)
    ctx.addPath(roundRect(rect, rad)); ctx.fillPath()
    let flatRight = rect.maxX - rad
    let bw = min(rect.width * 0.30, (rect.width - 2 * rad) * 0.92)
    let br = flatRight - rect.width * 0.03
    let t = CGMutablePath()
    t.move(to:    CGPoint(x: br - bw, y: rect.minY + 10))
    t.addLine(to: CGPoint(x: br,      y: rect.minY + 10))
    t.addLine(to: CGPoint(x: br + rect.width * 0.05, y: rect.minY - rect.height * 0.24))
    t.closeSubpath()
    ctx.addPath(t); ctx.fillPath()
}

// Speech bubble + three "unread" dots, centered on (cx,cy). A `keyline` > 0 draws a thin
// dark outline (a slightly larger bg-colored silhouette behind) so the amber bubble stays
// crisp when it sits directly on top of the amber sun — without a full black halo.
func dotBubble(rect: CGRect, rad: CGFloat, keyline: CGFloat = 0) {
    if keyline > 0 {
        bubbleShape(rect.insetBy(dx: -keyline, dy: -keyline), rad + keyline, bg)
    }
    bubbleShape(rect, rad, amber)
    ctx.setFillColor(bg.cgColor)
    for i in 0..<3 {
        let dx = rect.midX + CGFloat(i - 1) * (rect.width * 0.215)
        let r: CGFloat = rect.width * 0.06
        ctx.addEllipse(in: CGRect(x: dx - r, y: rect.midY - r, width: 2 * r, height: 2 * r))
    }
    ctx.fillPath()
}

let outerR: CGFloat = 800   // past the corners (corner dist ≈ 724) so rays bleed to the edge
ctx.setFillColor(amber.cgColor)

// Bubble geometry, centered on the canvas. The halo (a black disc) clears a clean
// gap so the bubble reads cleanly over the rays.
let bubble = CGRect(x: 232, y: 292, width: 560, height: 440)
let bubbleRad: CGFloat = 190

func drawHalo(_ r: CGFloat) {
    ctx.setFillColor(bg.cgColor)
    ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    ctx.fillPath()
}

switch style {
case "converge":
    // 24 wedges, apex exactly at the center → everything funnels in.
    let n = 24
    let slot = 2 * CGFloat.pi / CGFloat(n)
    for i in 0..<n {
        ray(angle: CGFloat(i) * slot, half: slot * 0.30, innerR: 0, outerR: outerR)
    }
    drawHalo(312)
    dotBubble(rect: bubble, rad: bubbleRad)

case "sun":
    // Alternating long/short rays radiating from a ring just outside the bubble.
    let n = 28
    let slot = 2 * CGFloat.pi / CGFloat(n)
    for i in 0..<n {
        let long = i % 2 == 0
        ray(angle: CGFloat(i) * slot, half: slot * 0.26,
            innerR: 300, outerR: long ? outerR : 560)
    }
    dotBubble(rect: bubble, rad: bubbleRad)

case "fine":
    // Many thin slivers converging to the center — a denser "streams collecting in" feel.
    let n = 48
    let slot = 2 * CGFloat.pi / CGFloat(n)
    for i in 0..<n {
        ray(angle: CGFloat(i) * slot, half: slot * 0.22, innerR: 0, outerR: outerR)
    }
    drawHalo(312)
    dotBubble(rect: bubble, rad: bubbleRad)

case "emanate":
    // Fewer, thicker rays running all the way to the center (behind the bubble) — no
    // halo gap, so the bubble sits directly on top of the sun.
    let n = 8
    let slot = 2 * CGFloat.pi / CGFloat(n)
    for i in 0..<n {
        ray(angle: CGFloat(i) * slot, half: slot * 0.34, innerR: 0, outerR: outerR)
    }
    dotBubble(rect: bubble, rad: bubbleRad, keyline: 36)

default:
    fatalError("unknown style \(style)")
}

NSGraphicsContext.restoreGraphicsState()

// Flatten to opaque (iOS app icons must not carry alpha).
guard let cg = rep.cgImage,
      let cs = CGColorSpace(name: CGColorSpace.sRGB),
      let octx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                           bytesPerRow: 0, space: cs,
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("no opaque ctx") }
octx.setFillColor(bg.cgColor)
octx.fill(CGRect(x: 0, y: 0, width: S, height: S))
octx.draw(cg, in: CGRect(x: 0, y: 0, width: S, height: S))
guard let flat = octx.makeImage(),
      let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:])
else { fatalError("encode failed") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) [\(style)]")
