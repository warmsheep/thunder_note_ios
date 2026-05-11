import SwiftUI

/// 图片 Lightbox：双指缩放 + 拖动关闭（与 Android `ImageViewerActivity` 行为对齐）。
struct ImageLightboxView: View {
    let imageURL: URL
    let onClose: () -> Void
    let onShare: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dismissProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - dismissProgress)
                .ignoresSafeArea()

            image
                .scaleEffect(scale * (1 - dismissProgress * 0.2))
                .offset(offset)
                .gesture(magnificationGesture)
                .gesture(dragGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = scale > 1.0 ? 1.0 : 2.0
                        lastScale = scale
                    }
                }

            topBar
        }
        .accessibilityIdentifier("imageLightbox")
    }

    private var image: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .empty:
                ProgressView().tint(.white)
            case .success(let img):
                img.resizable().scaledToFit()
            case .failure:
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.7))
            @unknown default:
                EmptyView()
            }
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(10)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("imageLightboxCloseButton")
                Spacer()
                Button {
                    onShare()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(10)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("imageLightboxShareButton")
            }
            .padding()
            Spacer()
        }
        .opacity(1 - dismissProgress)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1.0, min(lastScale * value, 4.0))
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation { scale = 1.0; lastScale = 1.0 }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // 缩放 > 1 时允许平移；=1 时做 drag-to-dismiss
                if scale > 1.0 {
                    offset = value.translation
                } else {
                    offset = CGSize(width: value.translation.width * 0.4, height: value.translation.height)
                    dismissProgress = min(abs(value.translation.height) / 250.0, 1.0)
                }
            }
            .onEnded { value in
                if scale <= 1.0 && abs(value.translation.height) > 150 {
                    onClose()
                } else {
                    withAnimation {
                        offset = .zero
                        dismissProgress = 0
                    }
                }
            }
    }
}
