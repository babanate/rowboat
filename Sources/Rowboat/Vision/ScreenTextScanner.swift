import AppKit
import Vision
import RowboatCore

/// Finds text on screen with Vision OCR and turns phrases into click targets.
/// Used where the accessibility tree has nothing to offer (Warp, canvases,
/// custom-drawn apps). Results are cached by a fingerprint of the capture so
/// an unchanged screen costs one 13 ms capture, not a 240 ms OCR pass.
final class ScreenTextScanner {
    static let shared = ScreenTextScanner()

    struct Result {
        var targets: [HintTarget]
        var elapsed: TimeInterval
        var fromCache: Bool
        var error: String?
    }

    private let lock = NSLock()
    /// Apps where a press needed screen text this session; pre-warmed on activation.
    private(set) var appsNeedingText: Set<String> = []
    func noteNeedsText(_ bundleID: String?) {
        guard let id = bundleID else { return }
        lock.lock(); appsNeedingText.insert(id); lock.unlock()
    }
    private var lastFingerprint: [UInt8] = []
    private var lastRect = CGRect.zero
    private var lastTargets: [HintTarget] = []
    private let scale: CGFloat = 0.5

    func scan(_ rect: CGRect) -> Result {
        lock.lock(); defer { lock.unlock() }
        let start = Date()
        guard ScreenCapture.isAvailable else { return Result(targets: [], elapsed: 0, fromCache: false, error: "capture unavailable") }
        guard ScreenCapture.hasPermission(prompt: false) else { return Result(targets: [], elapsed: 0, fromCache: false, error: "no screen recording permission") }
        guard let image = ScreenCapture.capture(rect) else { return Result(targets: [], elapsed: 0, fromCache: false, error: "capture failed") }

        let fingerprint = ScreenCapture.fingerprint(image)
        if fingerprint == lastFingerprint, rect == lastRect {
            return Result(targets: lastTargets, elapsed: Date().timeIntervalSince(start), fromCache: true, error: nil)
        }
        guard let small = ScreenCapture.scaled(image, by: scale) else { return Result(targets: [], elapsed: 0, fromCache: false, error: "scale failed") }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: small, options: [:]).perform([request]) } catch {
            return Result(targets: [], elapsed: 0, fromCache: false, error: "ocr: \(error.localizedDescription)")
        }

        let width = CGFloat(small.width), height = CGFloat(small.height)
        // Points per scaled pixel: the capture is Retina (2x) and then halved, so ~1 point per pixel.
        let pointsPerPixel = rect.width / width
        var targets: [HintTarget] = []
        for line in request.results ?? [] {
            guard let candidate = line.topCandidates(1).first else { continue }
            let text = candidate.string
            var words: [WordBox] = []
            var cursor = text.startIndex
            for piece in text.split(separator: " ") {
                guard let range = text.range(of: String(piece), range: cursor..<text.endIndex),
                      let box = try? candidate.boundingBox(for: range) else { continue }
                cursor = range.upperBound
                let b = box.boundingBox  // normalised, bottom-left origin
                let frame = CGRect(x: rect.minX + b.minX * width * pointsPerPixel,
                                   y: rect.minY + (1 - b.maxY) * height * pointsPerPixel,
                                   width: b.width * width * pointsPerPixel,
                                   height: b.height * height * pointsPerPixel)
                words.append(WordBox(text: String(piece), frame: frame))
            }
            for phrase in TextChunker.phrases(from: words) where phrase.frame.width >= 4 && phrase.frame.height >= 4 {
                targets.append(HintTarget(element: nil, frame: phrase.frame.integral, role: "Text",
                                          title: phrase.text, description: "", value: "", supportsPress: false))
            }
            // A URL or path inside a sentence deserves its own label.
            for word in words where TextChunker.looksLikeLink(word.text) && word.text.count > 3 {
                targets.append(HintTarget(element: nil, frame: word.frame.integral, role: "Link",
                                          title: word.text, description: "", value: "", supportsPress: false))
            }
        }
        lastFingerprint = fingerprint
        lastRect = rect
        lastTargets = targets
        return Result(targets: targets, elapsed: Date().timeIntervalSince(start), fromCache: false, error: nil)
    }
}
