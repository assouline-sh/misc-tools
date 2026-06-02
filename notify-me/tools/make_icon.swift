import AppKit
import CoreText

// AYFM app icon generator.
// Terminal theme: amber glyphs on near-black, SF Mono. A return/enter arrow (↵)
// runs down the right edge and across the bottom; the AYFM acronym nests into the
// corner the arrow forms.

let S: CGFloat = 1024

let bg     = NSColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1)  // #0B0B0D
let amber  = NSColor(red: 0.961, green: 0.651, blue: 0.137, alpha: 1)  // #F5A623

// ---- tunables ----
let stroke: CGFloat   = 70          // arrow line thickness
let rightX: CGFloat   = 752         // centerline x of the vertical segment (right side)
let bottomY: CGFloat  = 286         // centerline y of the horizontal segment (bottom)
let topY: CGFloat     = 792         // top of the vertical segment
let headTipX: CGFloat = 300         // x of the arrowhead tip (pointing left)
let headHalf: CGFloat = 96          // arrowhead half-height
let headLen: CGFloat  = 120         // arrowhead length

let fontSize: CGFloat = 264
let letterTracking: CGFloat = 0
let lettersCenterX: CGFloat = 420   // center of the 2x2 letter block
let lettersCenterY: CGFloat = 612

// ---- canvas ----
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }

// background
ctx.setFillColor(bg.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// ---- return arrow ----
// Body: vertical (right) + horizontal (bottom), drawn as a stroked path with a
// rounded outer corner. Arrowhead is a filled triangle pointing left.
ctx.setStrokeColor(amber.cgColor)
ctx.setLineWidth(stroke)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let path = CGMutablePath()
path.move(to: CGPoint(x: rightX, y: topY))
path.addLine(to: CGPoint(x: rightX, y: bottomY))
path.addLine(to: CGPoint(x: headTipX + headLen, y: bottomY))  // stop short for the head
ctx.addPath(path)
ctx.strokePath()

// arrowhead (filled triangle, tip at headTipX)
let head = CGMutablePath()
head.move(to: CGPoint(x: headTipX, y: bottomY))
head.addLine(to: CGPoint(x: headTipX + headLen, y: bottomY + headHalf))
head.addLine(to: CGPoint(x: headTipX + headLen, y: bottomY - headHalf))
head.closeSubpath()
ctx.addPath(head)
ctx.setFillColor(amber.cgColor)
ctx.fillPath()

// ---- AYFM letters (2x2, SF Mono bold) ----
let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: amber,
    .kern: letterTracking,
]

func draw(_ s: String, cx: CGFloat, cy: CGFloat) {
    let str = NSAttributedString(string: s, attributes: attrs)
    let line = CTLineCreateWithAttributedString(str)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let x = cx - w / 2
    let y = cy - (ascent - descent) / 2   // visually center the glyphs
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

let rowGap: CGFloat = fontSize * 0.92
draw("AY", cx: lettersCenterX, cy: lettersCenterY + rowGap / 2)
draw("FM", cx: lettersCenterX, cy: lettersCenterY - rowGap / 2)

img.unlockFocus()

// ---- write PNG ----
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("encode failed")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
