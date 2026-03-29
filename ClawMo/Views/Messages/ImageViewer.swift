import SwiftUI
import UIKit

extension UIImage: @retroactive Identifiable {
    public var id: Int { hash }
}

struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var showSaveToast = false
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { dismiss() }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * gestureScale)
                .offset(CGSize(
                    width: offset.width + dragOffset.width,
                    height: offset.height + dragOffset.height
                ))
                .gesture(
                    MagnifyGesture()
                        .updating($gestureScale) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            scale = max(scale * value.magnification, 1)
                            if scale <= 1 { offset = .zero }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            if scale > 1 { state = value.translation }
                        }
                        .onEnded { value in
                            if scale > 1 {
                                offset.width += value.translation.width
                                offset.height += value.translation.height
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if scale > 1 { scale = 1; offset = .zero
                        } else { scale = 3 }
                    }
                }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    Spacer()
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        Haptics.success()
                        showSaveToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSaveToast = false }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }

            if showSaveToast {
                VStack {
                    Spacer()
                    Text("已保存到相册")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                        .padding(.bottom, 60)
                }
            }
        }
    }
}
