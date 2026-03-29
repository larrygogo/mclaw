import SwiftUI
import PhotosUI

struct AttachmentSheet: View {
    @Binding var selectedPhotos: [PhotosPickerItem]
    var onCamera: () -> Void
    var onFile: () -> Void
    @Environment(\.dismiss) var dismiss

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 24) {
            LazyVGrid(columns: columns, spacing: 16) {
                PhotosPicker(selection: $selectedPhotos, matching: .images) {
                    attachItem(icon: "photo", label: "照片")
                }
                .onChange(of: selectedPhotos) { dismiss() }

                Button { onCamera() } label: {
                    attachItem(icon: "camera", label: "拍照")
                }

                Button { onFile() } label: {
                    attachItem(icon: "doc", label: "文件")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 16)
    }

    func attachItem(icon: String, label: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusL)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 70)
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
