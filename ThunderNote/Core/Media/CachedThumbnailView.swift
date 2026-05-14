import SwiftUI

struct CachedThumbnailView: View {
    let objectName: String?
    let fileRepository: FileRepository?

    @State private var localURL: URL?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        Group {
            if let localURL, !failed {
                if let uiImage = UIImage(contentsOfFile: localURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    thumbnailPlaceholder
                }
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                thumbnailPlaceholder
            }
        }
        .task(id: objectName) {
            await loadFromCache()
        }
    }

    private var thumbnailPlaceholder: some View {
        Color.gray.opacity(0.2)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
            )
    }

    @MainActor
    private func loadFromCache() async {
        guard let objectName, !objectName.isEmpty, let repo = fileRepository else {
            failed = true
            return
        }
        isLoading = true
        failed = false
        do {
            let url = try await repo.download(objectName: objectName)
            localURL = url
            failed = false
        } catch {
            failed = true
        }
        isLoading = false
    }
}
