import AppKit
import CoreText

// AYFM icon — textless concepts. Terminal theme: amber on near-black.
// Usage: swift make_icon2.swift <concept> <out.png>
//   bubble        speech bubble outline with a solid block cursor inside
//   prompt        terminal prompt chevron ">" + block cursor
//   bubblePrompt  speech bubble outline containing ">_" prompt
//   dotbubble     filled speech bubble with three "unread" dots
//   cursorbubble  filled amber bubble, cursor knocked out (negative space)

let S: CGFloat = 1024
let bg    = NSColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1)  // #0B0B0D
let amber = NSColor(red: 0.961, green: 0.651, blue: 0.137, alpha: 1)  // #F5A623

let concept = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "bubble"
let out     = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon_1024.png"

// Render into an explicit 1024x1024 bitmap at 1:1 pixel scale (no Retina 2x scaling).
// CoreGraphics needs an alpha channel to back the context; we flatten it away on output.
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

func roundRect(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

// The tail triangle, hanging off the bottom-right with the apex pointing down-right.
// The base sits on the FLAT part of the bottom edge (clear of the rounded corner) and
// overlaps slightly into the body.
func tailPath(_ rect: CGRect, _ rad: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let flatRight = rect.maxX - rad          // rightmost x of the flat bottom edge
    let bw = min(rect.width * 0.30, (rect.width - 2 * rad) * 0.92)  // base width
    let br = flatRight - rect.width * 0.03   // base right edge, just inside the flat run
    p.move(to: CGPoint(x: br - bw, y: rect.minY + 10))
    p.addLine(to: CGPoint(x: br, y: rect.minY + 10))
    p.addLine(to: CGPoint(x: br + rect.width * 0.05, y: rect.minY - rect.height * 0.24))
    p.closeSubpath()
    return p
}

// Fill a speech bubble (rounded body + tail) in the current fill color, as two separate
// fills — combining them into one path lets their overlap cancel via the winding rule,
// which leaves a thin seam between body and tail.
func fillBubble(_ rect: CGRect, _ rad: CGFloat) {
    ctx.addPath(roundRect(rect, rad)); ctx.fillPath()
    ctx.addPath(tailPath(rect, rad));  ctx.fillPath()
}

func blockCursor(center: CGPoint, w: CGFloat, h: CGFloat, color: NSColor) {
    ctx.setFillColor(color.cgColor)
    ctx.addPath(roundRect(CGRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h), w * 0.22))
    ctx.fillPath()
}

func chevron(tip: CGPoint, half: CGFloat, reach: CGFloat, width: CGFloat) {
    ctx.setStrokeColor(amber.cgColor)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: tip.x - reach, y: tip.y + half))
    p.addLine(to: tip)
    p.addLine(to: CGPoint(x: tip.x - reach, y: tip.y - half))
    ctx.addPath(p)
    ctx.strokePath()
}

switch concept {
case "bubble":
    let outer = CGRect(x: 188, y: 330, width: 648, height: 470)
    ctx.setFillColor(amber.cgColor)
    fillBubble(outer, 104)
    let inset: CGFloat = 40
    let inner = outer.insetBy(dx: inset, dy: inset)
    ctx.setFillColor(bg.cgColor)
    ctx.addPath(roundRect(inner, 104 - inset))
    ctx.fillPath()
    blockCursor(center: CGPoint(x: outer.midX, y: outer.midY), w: 92, h: 300, color: amber)

case "prompt":
    chevron(tip: CGPoint(x: 540, y: 512), half: 188, reach: 196, width: 78)
    blockCursor(center: CGPoint(x: 660, y: 430), w: 96, h: 300, color: amber)

case "bubblePrompt":
    let outer = CGRect(x: 188, y: 330, width: 648, height: 470)
    ctx.setFillColor(amber.cgColor)
    fillBubble(outer, 104)
    let inset: CGFloat = 40
    let inner = outer.insetBy(dx: inset, dy: inset)
    ctx.setFillColor(bg.cgColor)
    ctx.addPath(roundRect(inner, 104 - inset))
    ctx.fillPath()
    chevron(tip: CGPoint(x: 520, y: outer.midY + 30), half: 96, reach: 100, width: 52)
    // underscore cursor
    ctx.setFillColor(amber.cgColor)
    ctx.addPath(roundRect(CGRect(x: 560, y: outer.midY - 110, width: 170, height: 50), 24))
    ctx.fillPath()

case "dotbubble":
    // A round blob, a touch wider than tall so it doesn't read as a square.
    let outer = CGRect(x: 192, y: 322, width: 640, height: 500)
    ctx.setFillColor(amber.cgColor)
    fillBubble(outer, 210)
    ctx.setFillColor(bg.cgColor)
    for i in 0..<3 {
        let cx = outer.midX + CGFloat(i - 1) * 138
        ctx.addEllipse(in: CGRect(x: cx - 38, y: outer.midY - 38, width: 76, height: 76))
    }
    ctx.fillPath()

case "cursorbubble":
    let outer = CGRect(x: 188, y: 330, width: 648, height: 470)
    ctx.setFillColor(amber.cgColor)
    fillBubble(outer, 104)
    blockCursor(center: CGPoint(x: outer.midX, y: outer.midY), w: 92, h: 300, color: bg)

default:
    fatalError("unknown concept \(concept)")
}

NSGraphicsContext.restoreGraphicsState()

// Flatten to an opaque (no-alpha) image — iOS app icons must not carry an alpha channel.
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
print("wrote \(out) [\(concept)]")
