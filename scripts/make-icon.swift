// Draws the app icon (original artwork) into an .iconset directory.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(colors: [NSColor(red: 0.07, green: 0.09, blue: 0.20, alpha: 1),
                        NSColor(red: 0.18, green: 0.12, blue: 0.42, alpha: 1)])!.draw(in: shape, angle: -70)
    // Light bar glow across the top.
    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()
    let bar = NSBezierPath(roundedRect: NSRect(x: s * 0.22, y: s * 0.70, width: s * 0.56, height: s * 0.045),
                           xRadius: s * 0.02, yRadius: s * 0.02)
    NSGradient(colors: [NSColor.systemCyan, NSColor.systemPurple, NSColor.systemPink])!.draw(in: bar, angle: 0)
    NSGraphicsContext.current?.restoreGraphicsState()
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2 - s * 0.04,
                               width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
