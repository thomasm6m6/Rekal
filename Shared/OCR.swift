import Foundation
import CoreGraphics
import Vision

struct OCRResult: Codable, Identifiable {
    var text: String
    var normalizedRect: CGRect
    var uuid: UUID
    var id: UUID { uuid }

    init(text: String, normalizedRect: CGRect, uuid: UUID) {
        self.text = text
        self.normalizedRect = normalizedRect
        self.uuid = uuid
    }
}

enum OCRError: Error {
    case error(String)
}

func performOCR(on image: CGImage) async throws -> String {
    var request = RecognizeTextRequest()
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
    request.recognitionLevel = .accurate

    let results = try await request.perform(on: image)
    var data: [OCRResult] = []

    for observation in results {
        data.append(
            OCRResult(
                text: observation.topCandidates(1)[0].string,
                normalizedRect: observation.boundingBox.cgRect,
                uuid: observation.uuid
            ))
    }

    let encoder = JSONEncoder()
    let jsonData = try encoder.encode(data)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw OCRError.error("Cannot encode OCR data as JSON")
    }
    return jsonString
}
