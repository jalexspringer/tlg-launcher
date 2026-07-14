// Renders the app icon: the TLG artwork aspect-fitted onto a dark rounded
// tile on the standard macOS 1024pt icon grid (832pt tile, 96pt margins).
// Run via Scripts/make-icon.sh, which turns the PNG into an .icns.
//
// Usage: swift Scripts/MakeIcon.swift <artwork.png> <out-1024.png>
import AppKit

guard CommandLine.arguments.count == 3,
      let art = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
else {
    FileHandle.standardError.write(Data("usage: MakeIcon.swift <artwork.png> <out.png>\n".utf8))
    exit(1)
}

let canvasSize = NSSize(width: 1024, height: 1024)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = canvasSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 96, y: 96, width: 832, height: 832)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.17, alpha: 1),
    ending: NSColor(calibratedRed: 0.07, green: 0.06, blue: 0.08, alpha: 1)
)!.draw(in: tilePath, angle: -90)

tilePath.addClip()
let inset = tile.insetBy(dx: 36, dy: 36)
let scale = min(inset.width / art.size.width, inset.height / art.size.height)
let drawSize = NSSize(width: art.size.width * scale, height: art.size.height * scale)
art.draw(
    in: NSRect(
        x: tile.midX - drawSize.width / 2,
        y: tile.midY - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    ),
    from: .zero, operation: .sourceOver, fraction: 1
)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
