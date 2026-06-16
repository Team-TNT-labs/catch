import Vision
import CoreImage
import UIKit

enum BackgroundRemovalError: Error { case noSubject, processingFailed }

/// Vision 온디바이스 피사체 마스킹(누끼). iOS 17+.
final class BackgroundRemovalService {
    private let ciContext = CIContext()

    /// 입력 이미지에서 전경 피사체를 추출해 투명 배경 UIImage를 반환한다.
    /// 피사체가 없으면 `.noSubject`를 throw.
    func removeBackground(from input: UIImage) async throws -> UIImage {
        guard let cgImage = input.orientationNormalized().cgImage else {
            throw BackgroundRemovalError.processingFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.process(cgImage: cgImage)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func process(cgImage: CGImage) throws -> UIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw BackgroundRemovalError.noSubject
        }

        // 스캔 연출에서 원본과 픽셀 단위로 정렬돼야 하므로 크롭하지 않은 풀프레임 마스크를 만든다.
        // (스티커로 저장할 때 StickerStore가 투명 여백을 트림한다.)
        let maskedBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
        guard let outputCG = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw BackgroundRemovalError.processingFailed
        }
        return UIImage(cgImage: outputCG)
    }
}
