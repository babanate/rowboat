import AppKit

/// Captures a screen region as an image. Uses CGWindowListCreateImage, which
/// the macOS 26 SDK hides but the system still provides: 13 ms for a window
/// once warm, synchronous, no stream to keep alive. Falls back to nothing
/// (callers degrade gracefully) if the symbol ever disappears.
enum ScreenCapture {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImage? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    static var isAvailable: Bool { createImage != nil }

    /// Whether this process may record the screen. Prompting opens the system dialog once.
    static func hasPermission(prompt: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if prompt { return CGRequestScreenCaptureAccess() }
        return false
    }

    /// `rect` in AX screen coordinates (top-left origin). Returns a Retina-resolution image.
    static func capture(_ rect: CGRect) -> CGImage? {
        guard let createImage else { return nil }
        let onScreenOnly: UInt32 = 1 << 0
        let bestResolution: UInt32 = 1 << 1
        return createImage(rect, onScreenOnly, 0, bestResolution)?.takeRetainedValue()
    }

    /// Downscales by `scale` (0.5 halves each side).
    static func scaled(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let w = Int(CGFloat(image.width) * scale), h = Int(CGFloat(image.height) * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Cheap fingerprint of an image (16x10 grey thumbnail) for change detection.
    static func fingerprint(_ image: CGImage) -> [UInt8] {
        let w = 16, h = 10
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }
}
