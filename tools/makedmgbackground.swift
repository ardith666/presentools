import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let width = 540 * 2  // @2x Retina
let height = 380 * 2

guard let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("CGContext failed") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

let fullRect = CGRect(x: 0, y: 0, width: width, height: height)

// 1. Background Gradient
let bgGrad = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 1.0),
    NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1.0)
])!
bgGrad.draw(in: fullRect, angle: -90)

// 2. Ambient radial glow di tengah
let centre = CGPoint(x: CGFloat(width) * 0.5, y: CGFloat(height) * 0.5)
let radial = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.22, green: 0.44, blue: 0.75, alpha: 0.18).cgColor,
        NSColor.clear.cgColor
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    radial,
    startCenter: centre, startRadius: 0,
    endCenter: centre, endRadius: CGFloat(width) * 0.5,
    options: [.drawsAfterEndLocation]
)

// 3. Title Text "Presentools"
let titleFont = NSFont.systemFont(ofSize: 42, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor.white
]
let titleStr = "Presentools" as NSString
let titleSize = titleStr.size(withAttributes: titleAttrs)
let titleRect = CGRect(
    x: (CGFloat(width) - titleSize.width) / 2,
    y: CGFloat(height) - titleSize.height - 50,
    width: titleSize.width,
    height: titleSize.height
)
titleStr.draw(in: titleRect, withAttributes: titleAttrs)

// 4. Subtitle / Instruction Text "Drag to Applications"
let subFont = NSFont.systemFont(ofSize: 22, weight: .medium)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1.0)
]
let subStr = "Drag to Applications" as NSString
let subSize = subStr.size(withAttributes: subAttrs)
let subRect = CGRect(
    x: (CGFloat(width) - subSize.width) / 2,
    y: 80,
    width: subSize.width,
    height: subSize.height
)
subStr.draw(in: subRect, withAttributes: subAttrs)

// 5. Stylized Directional Arrow (Animasi/Grafis Drag)
// Dari X: 370 ke X: 710, Y tengah: 370
let arrowPath = NSBezierPath()
let arrowY: CGFloat = 370
let startX: CGFloat = 430
let endX: CGFloat = 650

arrowPath.move(to: CGPoint(x: startX, y: arrowY))
arrowPath.line(to: CGPoint(x: endX, y: arrowY))

// Kepala Panah
arrowPath.line(to: CGPoint(x: endX - 28, y: arrowY + 20))
arrowPath.move(to: CGPoint(x: endX, y: arrowY))
arrowPath.line(to: CGPoint(x: endX - 28, y: arrowY - 20))

arrowPath.lineWidth = 8
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round

NSColor(calibratedRed: 0.25, green: 0.70, blue: 0.98, alpha: 0.85).setStroke()
arrowPath.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
guard let pngData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("PNG encoding failed")
}

try pngData.write(to: URL(fileURLWithPath: outPath))
print("Generated DMG background at \(outPath)")
