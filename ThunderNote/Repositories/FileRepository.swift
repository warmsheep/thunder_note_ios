import Foundation

public protocol FileRepository: Sendable {
    /// 上传本地 file URL 指向的文件，返回服务端 `objectName`。
    /// 进度回调在主线程触发（0.0 ~ 1.0）。
    func upload(
        fileURL: URL,
        mimeType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> FileUploadResult

    /// 把 `objectName` 解析为完整下载 URL（不发起请求）。
    func resolveDownloadURL(objectName: String?) -> URL?

    /// 下载到本地缓存目录；若已存在则直接返回缓存文件 URL。
    /// 缓存按 `objectName` SHA256 分桶到 `Caches/tn.media/<2>/<rest>`。
    func download(objectName: String) async throws -> URL
}

public enum FileRepositoryError: Error, Equatable {
    case fileNotFound(URL)
    case unsupportedScheme
    case invalidResponse
    case transport(message: String)
    case http(status: Int)
}

public final class FileRepositoryImpl: NSObject, FileRepository, @unchecked Sendable {
    private let session: URLSession
    private let serverConfigStore: ServerConfigStoreProviding
    private let tokenAccessor: APIClient.TokenAccessor
    private let mediaUrlResolver: MediaUrlResolver
    private let decoder: JSONDecoder
    private let userAgent: String
    private let acceptLanguage: String
    private let cacheRoot: URL

    public init(
        session: URLSession,
        serverConfigStore: ServerConfigStoreProviding,
        tokenAccessor: APIClient.TokenAccessor,
        mediaUrlResolver: MediaUrlResolver,
        decoder: JSONDecoder = .tnDefault,
        userAgent: String = APIClient.defaultUserAgent(),
        acceptLanguage: String = APIClient.defaultAcceptLanguage(),
        cachesDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    ) {
        self.session = session
        self.serverConfigStore = serverConfigStore
        self.tokenAccessor = tokenAccessor
        self.mediaUrlResolver = mediaUrlResolver
        self.decoder = decoder
        self.userAgent = userAgent
        self.acceptLanguage = acceptLanguage
        let base = cachesDirectory ?? FileManager.default.temporaryDirectory
        self.cacheRoot = base.appendingPathComponent("tn.media", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    public func resolveDownloadURL(objectName: String?) -> URL? {
        mediaUrlResolver.resolve(objectName)
    }

    // MARK: - Upload

    public func upload(
        fileURL: URL,
        mimeType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> FileUploadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FileRepositoryError.fileNotFound(fileURL)
        }
        let boundary = "tn-boundary-\(UUID().uuidString)"
        let request = try await buildUploadRequest(targetPath: "/api/files/upload", boundary: boundary)

        // 把本地文件包装成 multipart 临时文件，避免一次性 load 大文件内存。
        let bodyFile = try makeMultipartBodyFile(
            sourceFileURL: fileURL,
            mimeType: mimeType,
            boundary: boundary
        )
        defer {
            try? FileManager.default.removeItem(at: bodyFile)
        }

        // 用 `URLSession.upload(for:fromFile:)` 走流式上传。
        // 进度通过自定义 delegate 上报。
        let progressObserver = UploadProgressObserver(progress: progress)
        let delegateBox = UploadDelegateBox(observer: progressObserver)
        let uploadSession = URLSession(
            configuration: session.configuration,
            delegate: delegateBox,
            delegateQueue: nil
        )
        defer { uploadSession.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await uploadSession.upload(for: request, fromFile: bodyFile)
        } catch {
            throw FileRepositoryError.transport(message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FileRepositoryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FileRepositoryError.http(status: http.statusCode)
        }

        // 后端 ApiResponse<FileUploadResult> 解包
        if let api = try? decoder.decode(ApiResponse<FileUploadResult>.self, from: data),
           api.isSuccess, let value = api.data {
            return value
        }
        throw FileRepositoryError.invalidResponse
    }

    private func buildUploadRequest(targetPath: String, boundary: String) async throws -> URLRequest {
        let baseURL = serverConfigStore.currentBaseURL
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest(reason: "BaseURL 非法")
        }
        let trimmed = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = trimmed + targetPath
        guard let url = components.url else {
            throw APIError.invalidRequest(reason: "无法拼接上传 URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if let token = await tokenAccessor.currentAccessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// 把 multipart body 写到一个临时文件，避免在内存里持有大文件副本。
    private func makeMultipartBodyFile(
        sourceFileURL: URL,
        mimeType: String,
        boundary: String
    ) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let bodyURL = tmpDir.appendingPathComponent("tn-upload-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: bodyURL)
        defer { try? handle.close() }

        let filename = sourceFileURL.lastPathComponent
        var header = ""
        header += "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n\r\n"
        try handle.write(contentsOf: Data(header.utf8))

        // 流式写入本地文件
        let readHandle = try FileHandle(forReadingFrom: sourceFileURL)
        defer { try? readHandle.close() }
        while true {
            let chunk = try readHandle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
        }

        let footer = "\r\n--\(boundary)--\r\n"
        try handle.write(contentsOf: Data(footer.utf8))
        return bodyURL
    }

    // MARK: - Download

    public func download(objectName: String) async throws -> URL {
        let cached = cacheURL(for: objectName)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        guard let url = mediaUrlResolver.resolve(objectName) else {
            throw FileRepositoryError.unsupportedScheme
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        if let token = await tokenAccessor.currentAccessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw FileRepositoryError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FileRepositoryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FileRepositoryError.http(status: http.statusCode)
        }

        try FileManager.default.createDirectory(
            at: cached.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: cached.path) {
            try? FileManager.default.removeItem(at: cached)
        }
        try FileManager.default.moveItem(at: tempURL, to: cached)
        return cached
    }

    private func cacheURL(for objectName: String) -> URL {
        let hash = Self.simpleHash(objectName)
        let prefix = String(hash.prefix(2))
        let rest = String(hash.dropFirst(2))
        return cacheRoot
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(rest)
    }

    /// 内置稳定哈希：避免引入 CryptoKit 依赖；与 Android 行为不要求完全一致，
    /// 只需稳定 + 分桶。
    static func simpleHash(_ source: String) -> String {
        var hasher = Hasher()
        hasher.combine(source)
        let value = hasher.finalize()
        return String(UInt64(bitPattern: Int64(value)), radix: 16)
            + String(source.utf8.count, radix: 16)
    }
}

// MARK: - Upload progress

private final class UploadProgressObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: (@Sendable (Double) -> Void)?

    init(progress: (@Sendable (Double) -> Void)?) {
        self.progress = progress
    }

    func report(_ value: Double) {
        guard let progress else { return }
        lock.lock(); defer { lock.unlock() }
        DispatchQueue.main.async {
            progress(max(0, min(1, value)))
        }
    }
}

private final class UploadDelegateBox: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let observer: UploadProgressObserver

    init(observer: UploadProgressObserver) {
        self.observer = observer
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        observer.report(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
