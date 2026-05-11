import Foundation
import SwiftUI

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public var username: String = ""
    @Published public var password: String = ""
    @Published public var registerEmail: String = ""

    @Published public private(set) var isWorking: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let authRepository: AuthRepository
    private let session: AuthSession

    public init(authRepository: AuthRepository, session: AuthSession) {
        self.authRepository = authRepository
        self.session = session
    }

    public func login() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else {
            errorMessage = "请输入用户名"
            return
        }
        guard !password.isEmpty else {
            errorMessage = "请输入密码"
            return
        }

        do {
            let response = try await authRepository.login(username: user, password: password)
            session.signIn(response)
            password = ""
        } catch let api as APIError {
            errorMessage = api.displayMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func register() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = registerEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try AuthRepositoryImpl.validateUsername(user)
        } catch {
            errorMessage = "用户名长度需为 3-32 字符"
            return false
        }
        do {
            try AuthRepositoryImpl.validateEmail(email)
        } catch {
            errorMessage = "请输入有效的邮箱地址"
            return false
        }
        do {
            try AuthRepositoryImpl.validatePassword(password)
        } catch {
            errorMessage = "密码长度需为 6-128 字符"
            return false
        }

        do {
            try await authRepository.register(username: user, email: email, password: password)
            return true
        } catch let api as APIError {
            errorMessage = api.displayMessage
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func logout() async {
        do {
            try await authRepository.logout()
        } catch {
            // 即使后端登出失败，也清本地态。
        }
        session.signOut()
    }

    public func clearError() {
        errorMessage = nil
    }
}
