import AppKit

// Questlog's mark: a three-quarter progress ring around a check, drawn once and exported for macOS.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/render_app_icon.swift <output-directory>\n", stderr)
    exit(1)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = FileManager.default
try files.createDirectory(at: root, withIntermediateDirectories: true)
func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func bitmap(_ size: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
// Apple's continuous-corner tile approximated with a squircle path.
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath(), r = radius, k: CGFloat = 1.28
    let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: x0 + r * k, y: y1))
    path.addLine(to: CGPoint(x: x1 - r * k, y: y1))
    path.addCurve(to: CGPoint(x: x1, y: y1 - r * k), control1: CGPoint(x: x1 - r * 0.36, y: y1), control2: CGPoint(x: x1, y: y1 - r * 0.36))
    path.addLine(to: CGPoint(x: x1, y: y0 + r * k))
    path.addCurve(to: CGPoint(x: x1 - r * k, y: y0), control1: CGPoint(x: x1, y: y0 + r * 0.36), control2: CGPoint(x: x1 - r * 0.36, y: y0))
    path.addLine(to: CGPoint(x: x0 + r * k, y: y0))
    path.addCurve(to: CGPoint(x: x0, y: y0 + r * k), control1: CGPoint(x: x0 + r * 0.36, y: y0), control2: CGPoint(x: x0, y: y0 + r * 0.36))
    path.addLine(to: CGPoint(x: x0, y: y1 - r * k))
    path.addCurve(to: CGPoint(x: x0 + r * k, y: y1), control1: CGPoint(x: x0, y: y1 - r * 0.36), control2: CGPoint(x: x0 + r * 0.36, y: y1))
    path.closeSubpath()
    return path
}

let master = bitmap(1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)
let cg = NSGraphicsContext.current!.cgContext
cg.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = squircle(tileRect, radius: 185)

// Tile: a quiet off-white surface with the standard soft lift and a hairline edge.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x1C1F2A, 0.18))
cg.addPath(tile); cg.setFillColor(color(0xFAFAFC)); cg.fillPath()
cg.restoreGState()
cg.addPath(tile); cg.setLineWidth(3); cg.setStrokeColor(color(0x1C1F2A, 0.08)); cg.strokePath()

// Ring: a flat track, then one solid arc covering three quarters from twelve o'clock.
let center = CGPoint(x: 512, y: 512), radius: CGFloat = 236, lineWidth: CGFloat = 52
cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
cg.setLineWidth(lineWidth); cg.setStrokeColor(color(0xE6E8EE)); cg.strokePath()
let start = CGFloat.pi / 2
cg.addArc(center: center, radius: radius, startAngle: start, endAngle: start - .pi * 1.5, clockwise: true)
cg.setLineWidth(lineWidth); cg.setLineCap(.round); cg.setStrokeColor(color(0x4A62A8)); cg.strokePath()

// Check: the same stroke weight in ink.
cg.move(to: CGPoint(x: 422, y: 516))
cg.addLine(to: CGPoint(x: 490, y: 448))
cg.addLine(to: CGPoint(x: 612, y: 574))
cg.setLineWidth(48); cg.setLineCap(.round); cg.setLineJoin(.round)
cg.setStrokeColor(color(0x23262F)); cg.strokePath()
NSGraphicsContext.restoreGraphicsState()
try master.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("AppIcon.png"))

let source = NSImage(size: NSSize(width: 1024, height: 1024))
source.addRepresentation(master)
func png(_ pixels: Int) -> Data {
    let target = bitmap(pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return target.representation(using: .png, properties: [:])!
}
try png(256).write(to: root.appendingPathComponent("AppIcon-preview.png"))
let iconset = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try files.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try png(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", root.appendingPathComponent("AppIcon.icns").path, iconset.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil could not export the iconset. Run with access to macOS Icon Services.\n", stderr)
    exit(1)
}
try files.removeItem(at: iconset)
print(root.appendingPathComponent("AppIcon.icns").path)
