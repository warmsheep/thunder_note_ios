import SwiftUI

struct FavoriteRowView: View {
    let item: FavoriteItem
    let fileRepository: FileRepository?

    init(item: FavoriteItem, fileRepository: FileRepository? = nil) {
        self.item = item
        self.fileRepository = fileRepository
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 10) {
                Text(item.displayIcon)
                    .font(.system(size: 24))
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.body.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    contentArea

                    if let time = item.favoritedAt ?? item.messageCreatedAt, !time.isEmpty {
                        Text(time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("favoriteRow-\(item.id)")
    }

    @ViewBuilder
    private var contentArea: some View {
        let mt = item.resolvedMediaType

        if mt == .composite, let payload = item.payload {
            cardPreview(payload)
        } else if mt == .image {
            mediaPreview(showPlayIcon: false)
        } else if mt == .video {
            mediaPreview(showPlayIcon: true)
        } else if mt == .audio {
            voiceInfo
        } else if mt == .file {
            fileInfo
        } else {
            if let content = item.content, !content.isEmpty {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func mediaPreview(showPlayIcon: Bool) -> some View {
        if let objectName = item.mediaUrl, !objectName.isEmpty {
            ZStack {
                CachedThumbnailView(
                    objectName: objectName,
                    fileRepository: fileRepository,
                    isVideo: showPlayIcon
                )
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if showPlayIcon {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: showPlayIcon ? "video.fill" : "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(showPlayIcon ? "[视频]" : "[图片]")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var fileInfo: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIconName)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(item.fileName ?? "文件")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var voiceInfo: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray4))
                .frame(width: 40, height: 12)
            Text("\(item.mediaDuration ?? 0)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func cardPreview(_ payload: CardPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = payload.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            if let summary = cardSummary(payload), !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let mediaUrls = cardMediaObjectNames(payload), !mediaUrls.isEmpty {
                cardGrid(mediaUrls: mediaUrls)
            }

            Divider()

            Text("闪记卡片消息")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cardSummary(_ payload: CardPayload) -> String? {
        if let summary = payload.summary, !summary.isEmpty { return summary }
        guard let items = payload.items, !items.isEmpty else { return nil }
        var lines: [String] = []
        for item in items.prefix(3) {
            if let content = item.content, !content.isEmpty {
                lines.append(content)
            } else {
                let t = item.resolvedMediaType
                if t == .image { lines.append("[图片]") }
                else if t == .video { lines.append("[视频]") }
                else if t == .file { lines.append("[文件]") }
                else if t == .audio { lines.append("[语音]") }
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func cardMediaObjectNames(_ payload: CardPayload) -> [String]? {
        guard let items = payload.items, !items.isEmpty else { return nil }
        var urls: [String] = []
        for cardItem in items {
            let t = cardItem.resolvedMediaType
            if t == .image, let url = cardItem.mediaUrl, !url.isEmpty {
                urls.append(url)
            } else if t == .video {
                if let url = cardItem.mediaUrl, !url.isEmpty {
                    urls.append(url)
                }
            }
        }
        return urls.isEmpty ? nil : Array(urls.prefix(9))
    }

    @ViewBuilder
    private func cardGrid(mediaUrls: [String]) -> some View {
        let count = min(mediaUrls.count, 9)
        let cols = count == 1 ? 1 : (count <= 2 || count == 4 ? 2 : 3)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: cols), spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                CachedThumbnailView(
                    objectName: mediaUrls[index],
                    fileRepository: fileRepository
                )
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var fileIconName: String {
        let ext = (item.fileName ?? "").components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx": return "chart.bar.fill"
        case "ppt", "pptx": return "doc.text.image.fill"
        default: return "doc.fill"
        }
    }
}
