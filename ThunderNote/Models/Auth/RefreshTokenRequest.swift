import Foundation

public struct RefreshTokenRequest: Encodable, Sendable {
    public let refreshToken: String

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}
