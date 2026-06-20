import UIKit
import CoreImage

/// 공유 CIContext — 호출마다 새로 만들면(전형적 성능 함정) 스티커 생성이 느려진다.
private let sharedCIContext = CIContext()

extension UIImage {
    /// 알파 가장자리를 부드럽게(블러 후 다시 샤프닝) — 누끼가 울퉁불퉁해도 외곽선이 깔끔.
    func alphaSmoothed(blur: CGFloat) -> UIImage {
        guard blur > 0, let cg = cgImage else { return self }
        let ci = CIImage(cgImage: cg)
        let extent = ci.extent
        let blurred = ci.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(blur))
            .cropped(to: extent)
        // 알파 ramp를 0.5 중심으로 가파르게 → 매끈한 경계 유지(작은 들쭉날쭉 제거).
        let sharp = blurred.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 6),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: -2.5)
        ])
        guard let out = sharedCIContext.createCGImage(sharp, from: extent) else { return self }
        return UIImage(cgImage: out, scale: scale, orientation: .up)
    }

    /// imageOrientation(카메라 EXIF 회전)을 픽셀에 베이크해 `.up` 방향 이미지를 만든다.
    /// `SKTexture(image:)`가 imageOrientation을 무시하는 문제를 방지한다.
    func orientationNormalized() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 투명한 바깥 여백을 잘라내 불투명 피사체 영역으로 크롭한다.
    /// 풀프레임 누끼(배경 투명)를 스티커로 저장할 때 타이트한 경계로 만든다.
    func trimmingTransparentPixels(alphaThreshold: UInt8 = 8) -> UIImage {
        guard let cg = cgImage, cg.width > 0, cg.height > 0 else { return self }
        let w = cg.width, h = cg.height
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return self }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * bytesPerRow
            for x in 0..<w where data[row + x * 4 + 3] >= alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return self }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cg.cropping(to: rect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    /// 알파를 유지한 채 단색으로 칠한 실루엣.
    func tinted(_ color: UIColor) -> UIImage {
        guard let mask = cgImage else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale; format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            let rect = CGRect(origin: .zero, size: size)
            cg.clip(to: rect, mask: mask)
            color.setFill()
            cg.fill(rect)
        }
    }

    /// 누끼 둘레에 스티커 테두리(림)를 두른다. width = px.
    func stickerBordered(color: UIColor, width: CGFloat, steps: Int = 18) -> UIImage {
        let pad = width + 1
        let newSize = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale; format.opaque = false
        // 외곽선용 실루엣은 알파를 매끈하게 다듬어 들쭉날쭉함 제거.
        let silhouette = alphaSmoothed(blur: max(1, width * 0.7)).tinted(color)
        let center = CGRect(x: pad, y: pad, width: size.width, height: size.height)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            for i in 0..<steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                silhouette.draw(in: center.offsetBy(dx: cos(a) * width, dy: sin(a) * width))
            }
            draw(in: center)
        }
    }

    /// 스티커 표시용으로 누끼에 흰색 테두리(림)를 두른다(스캔 완료·물리 씬·포커스 프리뷰 공통).
    /// - Returns: `working`(테두리 전, 물리 바디 비율 계산용)과 `bordered`(표시용).
    func whiteStickerBordered() -> (working: UIImage, bordered: UIImage) {
        let working = resized(maxDimension: 420)
        let borderW = max(working.size.width, working.size.height) * 0.045
        return (working, working.stickerBordered(color: .white, width: borderW))
    }

    /// 원형으로 크롭 + 흰 링을 두른 아바타(물리 서클용). 정사각 캔버스.
    func circularRinged(size: CGFloat = 200, ring: CGFloat = 10, ringColor: UIColor = .white) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false; fmt.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt).image { _ in
            ringColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()
            let inner = CGRect(x: ring, y: ring, width: size - ring * 2, height: size - ring * 2)
            let clip = UIBezierPath(ovalIn: inner); clip.addClip()
            let img = squareCropped()
            img.draw(in: inner)
        }
    }

    /// 가운데 정사각형으로 크롭(아바타용).
    func squareCropped() -> UIImage {
        guard let cg = cgImage else { return self }
        let w = cg.width, h = cg.height
        let side = min(w, h)
        let rect = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
        guard let cropped = cg.cropping(to: rect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }

    /// 긴 변이 maxDimension(pt) 이하가 되도록 비율 유지 리사이즈. 이미 작으면 그대로 반환.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
