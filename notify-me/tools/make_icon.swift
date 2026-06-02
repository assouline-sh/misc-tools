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
let stroke: CGFloat   = 42          // arrow line thickness
let rightX: CGFloat   = 840         // centerline x of the vertical segment (right side)
let bottomY: CGFloat  = 196         // centerline y of the horizontal segment (bottom)
let headTipX: CGFloat = 196         // x of the arrowhead tip (pointing left)
let headHalf: CGFloat = 62          // arrowhead half-height
let headLen: CGFloat  = 82          // arrowhead length

let fontSize: CGFloat = 360
let rowGapFactor: CGFloat = 0.86    // vertical spacing between the two letter rows
let letterTracking: CGFloat = 0
let lettersCenterX: CGFloat = 500   // center of the 2x2 letter block
let lettersCenterY: CGFloat = 512

// ---- font + metrics ----
// Derive the row baselines and the M's cap-top up front so the arrow's vertical
// segment can start exactly at the top of the bottom-row letters.
let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: amber,
    .kern: letterTracking,
]
let rowGap = fontSize * rowGapFactor
let topRowCY = lettersCenterY + rowGap / 2     // AY
let botRowCY = lettersCenterY - rowGap / 2     // FM
// Baseline of a row visually centered at cy (descender is negative).
func baseline(_ cy: CGFloat) -> CGFloat { cy - (font.ascender + font.descender) / 2 }
let topY = baseline(botRowCY) + font.capHeight  // cap-top of the FM row = top of "M"

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
func draw(_ s: String, cx: CGFloat, cy: CGFloat) {
    let str = NSAttributedString(string: s, attributes: attrs)
    let line = CTLineCreateWithAttributedString(str)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    ctx.textPosition = CGPoint(x: cx - w / 2, y: baseline(cy))
    CTLineDraw(line, ctx)
}

draw("AY", cx: lettersCenterX, cy: topRowCY)
draw("FM", cx: lettersCenterX, cy: botRowCY)

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
