import Foundation

public struct BrewPackage: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let isCask: Bool
    public init(name: String, version: String, isCask: Bool) {
        self.name = name; self.version = version; self.isCask = isCask
    }
}

public struct OutdatedPackage: Codable, Equatable, Sendable {
    public let name: String
    public let installed: String
    public let latest: String
    public let isCask: Bool
    public init(name: String, installed: String, latest: String, isCask: Bool) {
        self.name = name; self.installed = installed; self.latest = latest; self.isCask = isCask
    }
}

public struct SearchHit: Codable, Equatable, Sendable {
    public let name: String
    public let isCask: Bool
    public init(name: String, isCask: Bool) { self.name = name; self.isCask = isCask }
}

public struct BrewStatus: Codable, Equatable, Sendable {
    public let installed: Bool
    public let brewPath: String?
    public init(installed: Bool, brewPath: String?) { self.installed = installed; self.brewPath = brewPath }
}

public enum OpPhase: String, Codable, Sendable { case idle, running, done, failed }

public struct OpState: Codable, Equatable, Sendable {
    public let phase: OpPhase
    public let label: String
    public let exitCode: Int?
    public init(phase: OpPhase, label: String, exitCode: Int? = nil) {
        self.phase = phase; self.label = label; self.exitCode = exitCode
    }
    public static let idle = OpState(phase: .idle, label: "")
}
