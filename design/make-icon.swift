// Builds AppIcon.icns from a square source image of an icon tile.
// Usage: swift design/make-icon.swift <source.png> <cropX> <cropY> <cropSize> <out.icns>
// The crop selects the tile; it is scaled to Apple's 824 pt body on a 1024
// canvas and masked to a continuous-corner rounded rectangle.
import AppKit

let a = CommandLine.arguments
guard a.count == 6, let src = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let cx = Double(a[2]), let cy = Double(a[3]), let cs = Double(a[4]) else {
    print("usage: make-icon.swift <source.png> <cropX> <cropY> <cropSize> <out.icns>"); exit(2)
}
let crop = src.cropping(to: CGRect(x: cx, y: cy, width: cs, height: cs))!

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let inset = s * 100 / 1024, body = s * 824 / 1024
    let rect = CGRect(x: inset, y: inset, width: body, height: body)
    let path = NSBezierPath(roundedRect: rect, xRadius: body * 0.2237, yRadius: body * 0.2237).cgPath
    ctx.addPath(path); ctx.clip()
    ctx.draw(crop, in: rect)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: a[5]).deletingPathExtension().appendingPathExtension("png"))
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", a[5]]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(a[5])" : "iconutil failed")
