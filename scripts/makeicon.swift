// Draws the app icon from code: a white centre column between two grey brackets.
// Run with `swift scripts/makeicon.swift <out.png>`; bundle.sh then builds .icns.
import AppKit
import CoreGraphics

let side: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("context") }

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

// macOS icons sit inside a rounded square with breathing room.
let inset = side * 0.09
let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let plateRadius = plate.width * 0.2237

let platePath = CGPath(
    roundedRect: plate,
    cornerWidth: plateRadius,
    cornerHeight: plateRadius,
    transform: nil
)
ctx.addPath(platePath)
ctx.setFillColor(CGColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1))
ctx.fillPath()

// The brackets and the centre column share the same top and bottom.
let margin = plate.width * 0.18
let top = plate.maxY - margin
let bottom = plate.minY + margin
let height = top - bottom

let stroke = plate.width * 0.075
let gap = plate.width * 0.055
let centreWidth = plate.width * 0.235
let centreX = plate.midX - centreWidth / 2

let centre = CGRect(x: centreX, y: bottom, width: centreWidth, height: height)
let centrePath = CGPath(
    roundedRect: centre,
    cornerWidth: centreWidth * 0.30,
    cornerHeight: centreWidth * 0.30,
    transform: nil
)
ctx.addPath(centrePath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()

// A bracket is three strokes: vertical bar plus two horizontal arms that point
// away from the centre column, the way a square bracket encloses what is inside.
func bracket(towardRight: Bool) {
    let x = towardRight ? centre.minX - gap - stroke : centre.maxX + gap
    let armLength = plate.width * 0.100
    let radius = stroke / 2

    ctx.setFillColor(CGColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1))

    let bar = CGRect(x: x, y: bottom, width: stroke, height: height)
    let barPath = CGPath(
        roundedRect: bar,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
    ctx.addPath(barPath)
    ctx.fillPath()

    for y in [top - stroke, bottom] {
        let startX = towardRight ? x - armLength + radius : x + stroke - radius
        let arm = CGRect(x: startX, y: y, width: armLength, height: stroke)
        let armPath = CGPath(
            roundedRect: arm,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        ctx.addPath(armPath)
        ctx.fillPath()
    }
}

bracket(towardRight: true)
bracket(towardRight: false)

guard let image = ctx.makeImage() else { fatalError("image") }
let url = URL(fileURLWithPath: out)
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try data.write(to: url)
print("wrote \(out)")
