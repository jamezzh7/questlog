import AppKit

// The app's existing progress-bar mark, drawn once and exported for macOS.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/render_app_icon.swift <output-directory>\n", stderr)
    exit(1)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = FileManager.default
try files.createDirectory(at: root, withIntermediateDirectories: true)
func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func bitmap(_ size: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
let master = bitmap(1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 187, yRadius: 187)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x2F4668, 0.20)
shadow.shadowOffset = NSSize(width: 0, height: -15)
shadow.shadowBlurRadius = 25
shadow.set()
color(0xF5F8FE).setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0xEAF0FA), ending: color(0xFEFEFF))!.draw(in: tile, angle: 90)
color(0xFFFFFF, 0.95).setStroke(); tile.lineWidth = 3; tile.stroke()
let inset = NSBezierPath(roundedRect: NSRect(x: 101, y: 101, width: 822, height: 822), xRadius: 182, yRadius: 182)
color(0xB9C9E1, 0.36).setStroke(); inset.lineWidth = 2; inset.stroke()

let track = NSBezierPath(roundedRect: NSRect(x: 226, y: 430, width: 572, height: 164), xRadius: 82, yRadius: 82)
NSGradient(starting: color(0xE0E8F4), ending: color(0xCEDBED))!.draw(in: track, angle: 90)
color(0xB7C8E1, 0.35).setStroke(); track.lineWidth = 2; track.stroke()
let fill = NSBezierPath(roundedRect: NSRect(x: 226, y: 430, width: 350, height: 164), xRadius: 82, yRadius: 82)
NSGraphicsContext.saveGraphicsState()
let barShadow = NSShadow()
barShadow.shadowColor = color(0x4C6494, 0.22)
barShadow.shadowOffset = NSSize(width: 0, height: -5)
barShadow.shadowBlurRadius = 9
barShadow.set()
color(0x728DC0).setFill(); fill.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x5C79B0), ending: color(0x91A9D4))!.draw(in: fill, angle: 90)
NSGraphicsContext.saveGraphicsState()
fill.addClip()
let highlight = NSBezierPath(roundedRect: NSRect(x: 237, y: 444, width: 328, height: 138), xRadius: 69, yRadius: 69)
color(0xFFFFFF, 0.20).setStroke(); highlight.lineWidth = 2; highlight.stroke()
NSGraphicsContext.restoreGraphicsState()
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
