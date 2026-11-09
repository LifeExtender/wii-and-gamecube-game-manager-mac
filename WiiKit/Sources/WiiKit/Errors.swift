import Foundation

public struct ToolFailure: LocalizedError, Sendable {
    public let exitCode: Int32
    public let detail: String
    public var errorDescription: String? { detail }
}

public struct OperationCancelled: LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "Cancelled" }
}

public struct PreflightFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct DiskRefused: LocalizedError, Sendable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { reason }
}

public struct VerificationFailed: LocalizedError, Sendable {
    public let detail: String
    public var errorDescription: String? { detail }
}
