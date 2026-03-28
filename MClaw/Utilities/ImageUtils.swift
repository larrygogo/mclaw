import UIKit

func compressImage(_ data: Data, maxBytes: Int) -> Data? {
    guard let uiImage = UIImage(data: data) else { return data }
    if data.count <= maxBytes { return data }
    for quality in stride(from: 0.8, through: 0.1, by: -0.1) {
        if let compressed = uiImage.jpegData(compressionQuality: quality),
           compressed.count <= maxBytes {
            return compressed
        }
    }
    let scale = sqrt(Double(maxBytes) / Double(data.count))
    let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
    return resized.jpegData(compressionQuality: 0.7)
}
