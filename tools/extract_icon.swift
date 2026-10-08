// Extract the largest AppIcon rendition from the macOS game bundle's Assets.car as a PNG.
// usage: swift tools/extract_icon.swift "<Hades II.app>" <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let bundle = Bundle(path: args[1]),
      let image = bundle.image(forResource: "AppIcon") else { fatalError("no AppIcon in bundle") }
let best = image.representations.max { $0.pixelsWide < $1.pixelsWide }!
let ctx = NSGraphicsContext(bitmapImageRep: NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: best.pixelsWide, pixelsHigh: best.pixelsHigh, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!)!
NSGraphicsContext.current = ctx
best.draw(in: NSRect(x: 0, y: 0, width: best.pixelsWide, height: best.pixelsHigh))
let rep = NSBitmapImageRep(cgImage: ctx.cgContext.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("\(best.pixelsWide)x\(best.pixelsHigh) -> \(args[2])")
