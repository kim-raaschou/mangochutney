// The app's icon from mango's logo (Resources/mango.svg, mango's assets/mango.svg): an asset
// catalog for actool (`make icon`). The logo inside Apple's icon grid (824 of 1024 points).
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: app-icon.swift <logo.svg> <out.xcassets>\n".data(using: .utf8)!)
    exit(1)
}
let catalog = URL(fileURLWithPath: args[2])
let out = catalog.appendingPathComponent("AppIcon.appiconset")
try? FileManager.default.removeItem(at: catalog)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let info = #""info":{"version":1,"author":"xcode"}"#
try! "{\(info)}".write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let side = CGFloat(px) * 824 / 1024
        let inset = (CGFloat(px) - side) / 2
        logo.draw(in: NSRect(x: inset, y: inset, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
        images.append(#"{"idiom":"mac","size":"\#(points)x\#(points)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
try! "{\"images\":[\(images.joined(separator: ","))],\(info)}"
    .write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
