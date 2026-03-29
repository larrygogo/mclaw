import UIKit

func compressImage(_ data: Data, maxBytes: Int) -> Data {
    guard let uiImage = UIImage(data: data) else { return data }
    if data.count <= maxBytes { return data }

    // Step 1: Lower JPEG quality
    for quality in stride(from: 0.8, through: 0.1, by: -0.1) {
        if let compressed = uiImage.jpegData(compressionQuality: quality),
           compressed.count <= maxBytes {
            return compressed
        }
    }

    // Step 2: Resize + quality sweep
    var image = uiImage
    for maxDim: CGFloat in [2048, 1280, 800, 480] {
        if image.size.width > maxDim || image.size.height > maxDim {
            let ratio = min(maxDim / image.size.width, maxDim / image.size.height)
            let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            image = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
        for quality in stride(from: 0.6, through: 0.1, by: -0.1) {
            if let compressed = image.jpegData(compressionQuality: quality),
               compressed.count <= maxBytes {
                return compressed
            }
        }
    }

    // Step 3: Final fallback — always returns something
    return image.jpegData(compressionQuality: 0.1) ?? data
}
