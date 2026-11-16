import Foundation
import Vision
import CoreGraphics
import ImageIO

/// Text recognition for windows that expose no accessibility content.
///
/// Teams and other web-view apps hand back a 12-node AX tree, so the only readable
/// signal is the pixels. This runs the system Vision recogniser on the screenshot and
/// returns lines with their centres in *screenshot pixel* coordinates, which is the
/// same space the click tool uses.
enum OCR {

    struct Line {
        let text: String
        let center: CGPoint
        let box: CGRect
        let confidence: Float
    }

    static func lines(in image: CGImage, minConfidence: Float = 0.25, limit: Int = 160) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "bg-BG"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observations = request.results else { return [] }

        let width = CGFloat(image.width), height = CGFloat(image.height)
        var out: [Line] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first, candidate.confidence >= minConfidence else { continue }
            let b = obs.boundingBox
            let rect = CGRect(x: b.minX * width,
                              y: (1 - b.maxY) * height,
                              width: b.width * width,
                              height: b.height * height)
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            out.append(Line(text: text,
                            center: CGPoint(x: rect.midX, y: rect.midY),
                            box: rect,
                            confidence: candidate.confidence))
        }
        out.sort { a, b in
            if abs(a.center.y - b.center.y) > 6 { return a.center.y < b.center.y }
            return a.center.x < b.center.x
        }
        return Array(out.prefix(limit))
    }

    static func lines(inPNG data: Data, minConfidence: Float = 0.25, limit: Int = 160) -> [Line] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return lines(in: image, minConfidence: minConfidence, limit: limit)
    }

    static func render(_ lines: [Line]) -> String {
        var out = "ocr: \(lines.count) lines (screenshot pixel coordinates)\n"
        for line in lines {
            let x = Int(line.center.x), y = Int(line.center.y)
            out += "[\(x),\(y)] \(line.text)\n"
        }
        return out
    }
}
