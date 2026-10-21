// Standard macOS SF Symbols, rendered at 2× for the dependency-free WebKit UI.
import AppKit
let names = ["circle.lefthalf.filled", "plus", "xmark", "chevron.down", "magnifyingglass", "arrow.down.right.and.arrow.up.left", "slider.horizontal.3", "arrow.clockwise", "checkmark.circle.fill", "circle.fill", "exclamationmark.circle.fill", "doc.text"]
let image = NSImage(size: NSSize(width: names.count * 20, height: 20))
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: names.count * 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = image.size
image.addRepresentation(rep)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.clear.setFill()
NSRect(origin: .zero, size: image.size).fill()
for (index, name) in names.enumerated() {
    let pointSize: CGFloat = name == "circle.fill" ? 5 : name == "checkmark.circle.fill" ? 12 : 13
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))!
    let width = min(16, symbol.size.width), height = min(16, symbol.size.height)
    symbol.draw(in: NSRect(x: CGFloat(index * 20) + (20 - width)/2, y: (20 - height)/2, width: width, height: height))
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
