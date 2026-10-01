// Renders one 1024px Presentools icon: dark stage, spotlight cone, cursor.
//
// ponytail: no icon was designed, so this draws one in code. Replace with
// hand-made art when there is a real brand — only the PNG input changes.
// Not app logic, so it stays out of Sources/ and is not shipped.
//
// Usage: makeicon <out.png>

import AppKit
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Presentools-1024.png"
let px = 1024
let side = CGFloat(px)

guard let ctx = CGContext(
    data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("CGContext") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

let rect = CGRect(x: side * 0.06, y: side * 0.06, width: side * 0.88, height: side * 0.88)
let corner = side * 0.22
let stage = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

// Stage: dark vertical gradient so the icon has depth at large sizes.
stage.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1),
    NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1),
])!.draw(in: rect, angle: -90)

// Spotlight: dim the whole field, then punch one lit circle. The app in one
// shape, and no text so it still reads at 16px.
NSColor.black.withAlphaComponent(0.55).setFill()
rect.fill()

let centre = CGPoint(x: side * 0.5, y: side * 0.52)
let cone = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor.white.withAlphaComponent(0.95).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    cone,
    startCenter: centre, startRadius: 0,
    endCenter: centre, endRadius: side * 0.30,
    options: [.drawsAfterEndLocation]
)

// Cursor glyph on top so it reads as a pointer tool.
let o = CGPoint(x: centre.x - side * 0.075, y: centre.y - side * 0.085)
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: o.x, y: o.y + side * 0.17))
arrow.line(to: CGPoint(x: o.x, y: o.y))
arrow.line(to: CGPoint(x: o.x + side * 0.052, y: o.y + side * 0.048))
arrow.line(to: CGPoint(x: o.x + side * 0.088, y: o.y - side * 0.046))
arrow.line(to: CGPoint(x: o.x + side * 0.062, y: o.y - side * 0.068))
arrow.line(to: CGPoint(x: o.x + side * 0.028, y: o.y + side * 0.022))
arrow.close()
arrow.addClip()
NSColor.white.setFill()
NSRect(x: o.x - side, y: o.y - side, width: side * 2, height: side * 2).fill()
NSGraphicsContext.restoreGraphicsState()

// Outline last, so the glyph keeps a dark edge against the lit circle.
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
NSColor.black.withAlphaComponent(0.5).setStroke()
arrow.lineWidth = side * 0.016
arrow.stroke()
NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage() else { fatalError("makeImage") }
guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("png encode")
}
try data.write(to: URL(fileURLWithPath: outPath))
print(outPath)
