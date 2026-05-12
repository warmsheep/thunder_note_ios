import Foundation

public protocol AuthRepository: Sendable {
    func login(username: String, password: String) async throws -> LoginResponse
    func register(username: String, email: String, password: String) async throws
    func logout() async throws
    func changePassword(currentPassword: String, newPassword: String) async throws
    
    // D2-I6-19 手势锁云端备份
    func updateGestureLock(passwordHash: String) async throws
    func clearGestureLock() async throws
    func getGestureLock() async throws -> GestureLockBackupResponse
}

public final class AuthRepositoryImpl: AuthRepository, @unchecked Sendable {
    public enum ValidationError: Error, Equatable {
        case usernameLength
        case emailFormat
        case passwordLength
        case currentPasswordEmpty
        case newPasswordLength
        case newPasswordSameAsOld
    }

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func login(username: String, password: String) async throws -> LoginResponse {
        let body = try JSONEncoder.tnDefault.encode(LoginRequest(username: username, password: password))
        let endpoint = Endpoint<LoginResponse>(
            method: .post,
            path: "/api/auth/login",
            body: body,
            requiresAuth: false,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func register(username: String, email: String, password: String) async throws {
        try Self.validateUsername(username)
        try Self.validateEmail(email)
        try Self.validatePassword(password)
        let body = try JSONEncoder.tnDefault.encode(RegisterRequest(username: username, email: email, password: password))
        let endpoint = Endpoint<EmptyResponse>(
            method: .post,
            path: "/api/auth/register",
            body: body,
            requiresAuth: false,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        _ = try await apiClient.send(endpoint)
    }

    public func logout() async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .post,
            path: "/api/auth/logout",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }

    public func changePassword(currentPassword: String, newPassword: String) async throws {
        guard !currentPassword.isEmpty else { throw ValidationError.currentPasswordEmpty }
        try Self.validatePassword(newPassword, validationError: .newPasswordLength)
        guard currentPassword != newPassword else { throw ValidationError.newPasswordSameAsOld }
        let body = try JSONEncoder.tnDefault.encode(
            ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword)
        )
        let endpoint = Endpoint<EmptyResponse>(
            method: .put,
            path: "/api/auth/password",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        _ = try await apiClient.send(endpoint)
    }

    // MARK: - Gesture Lock (D2-I6-19)

    public func updateGestureLock(passwordHash: String) async throws {
        let request = GestureLockBackupRequest(passwordHash: passwordHash)
        let endpoint = try Endpoint<EmptyResponse>.json(.put, "/api/auth/gesture-lock", body: request)
        _ = try await apiClient.send(endpoint)
    }

    public func clearGestureLock() async throws {
        let endpoint = Endpoint<EmptyResponse>(method: .delete, path: "/api/auth/gesture-lock")
        _ = try await apiClient.send(endpoint)
    }

    public func getGestureLock() async throws -> GestureLockBackupResponse {
        let endpoint = Endpoint<GestureLockBackupResponse>(method: .get, path: "/api/auth/gesture-lock")
        return try await apiClient.send(endpoint)
    }

    // MARK: - Local Validation (与 Android 校验规则对齐)

    static func validateUsername(_ username: String) throws {
        let count = username.count
        guard count >= 3, count <= 32 else { throw ValidationError.usernameLength }
    }

    static func validateEmail(_ email: String) throws {
        // 后端要求"必须符合邮箱格式"。这里采用 Android 端等价的轻量正则：
        // 至少包含一个 @ 与一个 .，避免空格与控制字符。
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: email.utf16.count)
        if regex.firstMatch(in: email, options: [], range: range) == nil {
            throw ValidationError.emailFormat
        }
    }

    static func validatePassword(_ password: String, validationError: ValidationError = .passwordLength) throws {
        let count = password.count
        guard count >= 6, count <= 128 else { throw validationError }
    }
}
