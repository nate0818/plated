import UIKit
import Vision

/// Banner photos are people photos. A wide crop taken from the middle of
/// the frame decapitates a family standing slightly off-centre, so the crop
/// is aimed: at the faces when there are faces, at whatever the image is
/// actually *about* when there aren't.
///
/// The aiming happens once, when the photo is picked, and the already-framed
/// image is what gets stored — no focal point to persist, no schema to
/// migrate, and every later render is a plain `scaledToFill`.
enum BannerFocus {

    /// The banner's shape. Wide enough to read as a mantel photo, tall
    /// enough that a row of people survives the crop.
    static let aspect: CGFloat = 16.0 / 9.0

    /// Crop to `aspect`, centred on the subject, and downscale for storage.
    /// Returns nil only when the data isn't an image at all.
    static func framed(_ raw: Data, aspect: CGFloat = BannerFocus.aspect, maxWidth: CGFloat = 1400) -> Data? {
        guard let source = UIImage(data: raw) else { return nil }
        // Vision reasons in pixels with no notion of a UIImage orientation
        // flag, so the pixels get straightened first and everything after
        // this line is honest .up geometry.
        let image = source.uprighted()
        guard let cgImage = image.cgImage else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let focus = subjectRect(in: cgImage, size: size) ?? CGRect(
            x: size.width / 2, y: size.height / 2, width: 0, height: 0
        )

        let crop = cropRect(containing: focus, in: size, aspect: aspect)
        guard let cropped = cgImage.cropping(to: crop) else { return nil }

        return render(UIImage(cgImage: cropped), maxWidth: maxWidth)
    }

    // MARK: Where to aim

    /// Faces first — the whole point. Salient region second. Nil when the
    /// image gives us nothing to go on and the centre is as good a guess
    /// as any.
    private static func subjectRect(in cgImage: CGImage, size: CGSize) -> CGRect? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        let faces = VNDetectFaceRectanglesRequest()
        try? handler.perform([faces])
        let faceBoxes = (faces.results ?? []).map { denormalize($0.boundingBox, size) }
        if let union = faceBoxes.reduce(nil as CGRect?, { $0?.union($1) ?? $1 }) {
            // Headroom: faces sit slightly above the centre of a good
            // portrait, so bias the aim upward by a third of the face block.
            return union.insetBy(dx: -union.width * 0.15, dy: -union.height * 0.35)
                .offsetBy(dx: 0, dy: -union.height * 0.15)
        }

        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        try? handler.perform([saliency])
        if let observation = saliency.results?.first,
           let salient = observation.salientObjects?.first {
            return denormalize(salient.boundingBox, size)
        }
        return nil
    }

    /// Vision's normalized, bottom-left origin → CoreGraphics image pixels.
    private static func denormalize(_ box: CGRect, _ size: CGSize) -> CGRect {
        CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }

    /// The largest `aspect` rectangle that fits the image and holds the
    /// focus, slid back inside the frame rather than clipped at the edge.
    private static func cropRect(containing focus: CGRect, in size: CGSize, aspect: CGFloat) -> CGRect {
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }

        let centre = focus.isEmpty
            ? CGPoint(x: size.width / 2, y: size.height / 2)
            : CGPoint(x: focus.midX, y: focus.midY)

        let x = min(max(centre.x - width / 2, 0), size.width - width)
        let y = min(max(centre.y - height / 2, 0), size.height - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    // MARK: Storage

    private static func render(_ image: UIImage, maxWidth: CGFloat) -> Data? {
        let scale = min(1, maxWidth / image.size.width)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return drawn.jpegData(compressionQuality: 0.86)
    }
}

private extension UIImage {
    /// The same pixels, with the orientation flag baked in and cleared.
    func uprighted() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
