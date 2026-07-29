import Foundation
import ImageIO
import Vision

enum ImageAutoRecognitionPolicy {
    static let maximumPixelDimension = 1_600
    static let maximumPixelCount = 2_000_000

    static func shouldRecognize(imageData: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(
            imageData as CFData,
            nil
        ),
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let width = pixelValue(properties[kCGImagePropertyPixelWidth]),
        let height = pixelValue(properties[kCGImagePropertyPixelHeight]),
        width > 0,
        height > 0 else {
            return false
        }

        let pixelCount = width.multipliedReportingOverflow(by: height)
        return !pixelCount.overflow &&
            max(width, height) <= maximumPixelDimension &&
            pixelCount.partialValue <= maximumPixelCount
    }

    private static func pixelValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }
}

struct ImageRecognitionResult: Equatable {
    let text: String
    let qrCodes: [String]
}

protocol ImageRecognizing {
    func recognize(
        imageData: Data,
        completion: @escaping (ImageRecognitionResult) -> Void
    )
}

final class VisionImageRecognizer: ImageRecognizing {
    private let queue = DispatchQueue(
        label: "com.test.clib.image-recognition",
        qos: .userInitiated
    )

    func recognize(
        imageData: Data,
        completion: @escaping (ImageRecognitionResult) -> Void
    ) {
        queue.async {
            let result = Self.performRecognition(imageData: imageData)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func performRecognition(imageData: Data) -> ImageRecognitionResult {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true

        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.qr]

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([textRequest, barcodeRequest])
        } catch {
            print("图片识别失败：\(error)")
            return ImageRecognitionResult(text: "", qrCodes: [])
        }

        let observations = textRequest.results ?? []
        let text = observations
            .sorted(by: readingOrder)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var seenCodes = Set<String>()
        let qrCodes = (barcodeRequest.results ?? []).compactMap {
            observation -> String? in
            guard let value = observation.payloadStringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seenCodes.insert(value).inserted else {
                return nil
            }
            return value
        }
        return ImageRecognitionResult(text: text, qrCodes: qrCodes)
    }

    private static func readingOrder(
        _ lhs: VNRecognizedTextObservation,
        _ rhs: VNRecognizedTextObservation
    ) -> Bool {
        let verticalDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        if verticalDifference > 0.02 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
}
