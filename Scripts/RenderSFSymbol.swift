import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 5 else {
    FileHandle.standardError.write("Usage: RenderSFSymbol <symbolName> <canvasSize> <hexColor> <outputPath>\n".data(using: .utf8)!)
    exit(1)
}
let symbolName = args[1]
let canvasSize = CGFloat(Double(args[2])!)
let hexColor = args[3]
let outputPath = args[4]

func nsColor(fromHex hex: String) -> NSColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let value = UInt32(s, radix: 16)!
    let r = CGFloat((value >> 16) & 0xFF) / 255
    let g = CGFloat((value >> 8) & 0xFF) / 255
    let b = CGFloat(value & 0xFF) / 255
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    FileHandle.standardError.write("Unknown SF Symbol: \(symbolName)\n".data(using: .utf8)!)
    exit(1)
}

let tint = nsColor(fromHex: hexColor)
// Render at ~80% of the canvas so the glyph has breathing room, matching
// how SF Symbols look inset within a filled circle/square button elsewhere
// on Apple platforms -- a glyph drawn edge-to-edge in its own bounding box
// reads as cramped once placed inside RailButton/ToolbarPill's padding.
let glyphPointSize = canvasSize * 0.8
let sizeConfig = NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .regular)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [tint])
let config = sizeConfig.applying(colorConfig)

guard let configured = symbol.withSymbolConfiguration(config) else {
    FileHandle.standardError.write("Failed to configure symbol: \(symbolName)\n".data(using: .utf8)!)
    exit(1)
}

let glyphSize = configured.size
guard glyphSize.width > 0, glyphSize.height > 0 else {
    FileHandle.standardError.write("Symbol \(symbolName) has zero size\n".data(using: .utf8)!)
    exit(1)
}

// SF Symbols report a tight bounding box that varies per glyph -- scale-to-fit
// and center within a fixed square canvas so every icon this script produces
// has identical pixel dimensions, regardless of the source glyph's aspect ratio.
let fitScale = min(canvasSize / glyphSize.width, canvasSize / glyphSize.height)
let drawWidth = glyphSize.width * fitScale
let drawHeight = glyphSize.height * fitScale
let drawOrigin = NSPoint(x: (canvasSize - drawWidth) / 2, y: (canvasSize - drawHeight) / 2)

let pixelsPerSide = Int(canvasSize.rounded(.up))
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelsPerSide,
    pixelsHigh: pixelsPerSide,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
configured.draw(in: NSRect(origin: drawOrigin, size: NSSize(width: drawWidth, height: drawHeight)))
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to encode PNG for \(symbolName)\n".data(using: .utf8)!)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath) (\(pixelsPerSide)x\(pixelsPerSide) canvas, glyph \(Int(drawWidth))x\(Int(drawHeight)))")
