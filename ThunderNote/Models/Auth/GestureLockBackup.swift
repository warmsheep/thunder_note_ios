import Foundation

public struct GestureLockBackupRequest: Codable, Sendable {
    public let passwordHash: String
}

public struct GestureLockBackupResponse: Codable, Sendable {
    public let passwordHash: String
}
