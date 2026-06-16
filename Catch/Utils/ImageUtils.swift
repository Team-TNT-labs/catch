import UIKit

extension UIImage {
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
