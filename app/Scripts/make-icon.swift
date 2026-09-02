// Renders the app icon: a half-color / half-gray disc on a dark rounded tile.
// Usage: swift make-icon.swift <output.iconset dir>
import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let s = size / 1024

    // Tile (macOS icon grid: 824pt square centered in 1024, radius ~185).
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let tileGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
                 CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(tileGradient, start: CGPoint(x: 0, y: tile.maxY),
                           end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // Disc.
    let disc = CGRect(x: 262 * s, y: 262 * s, width: 500 * s, height: 500 * s)
    ctx.saveGState()
    ctx.addEllipse(in: disc)
    ctx.clip()
    // Right half: gray.
    ctx.setFillColor(CGColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1))
    ctx.fill(CGRect(x: disc.midX, y: disc.minY, width: disc.width / 2, height: disc.height))
    // Left half: warm color gradient.
    ctx.saveGState()
    ctx.clip(to: CGRect(x: disc.minX, y: disc.minY, width: disc.width / 2, height: disc.height))
    let warm = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 1.0, green: 0.62, blue: 0.16, alpha: 1),
                 CGColor(red: 1.0, green: 0.27, blue: 0.36, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(warm, start: CGPoint(x: disc.minX, y: disc.maxY),
                           end: CGPoint(x: disc.midX, y: disc.minY), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    // Thin ring for definition.
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(6 * s)
    ctx.strokeEllipse(in: disc.insetBy(dx: 3 * s, dy: 3 * s))

    image.unlockFocus()
    return image
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = CGFloat(points * scale)
    let image = render(size: pixels)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { continue }
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try? png.write(to: outputDir.appendingPathComponent(name))
}
print("iconset written to \(outputDir.path)")
