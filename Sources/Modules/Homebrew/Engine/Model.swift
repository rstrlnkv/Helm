import Foundation

/// How a package is named once, everywhere.
///
/// A formula and a cask can share a name — `docker` is both — so neither the
/// row identity nor the description cache can be keyed by the name alone. The
/// prefixed form was written out eight times across the module: three
/// `Identifiable` conformances, the description lookup, and four more inside
/// the batch that fills it. Nothing tied them together, and the failure of a
/// disagreement is silent — descriptions arrive under keys the rows do not ask
/// for, so every row simply has no description and no error is raised anywhere.
public enum BrewKey {
    public static func of(name: String, isCask: Bool) -> String {
        (isCask ? "c:" : "f:") + name
    }
}

/// What the UI sends to name one package. It crossed the transport as a struct
/// declared **twice** — privately in the engine and privately again in the view
/// model — so the two could drift apart with nothing to catch it: a renamed
/// field fails the decode, the handler returns `Data()`, and the button does
/// nothing at all. `LeftoversToggle` is the shape this follows.
public struct PackageRef: Codable, Sendable {
    public let name: String
    public let isCask: Bool
    public init(name: String, isCask: Bool) { self.name = name; self.isCask = isCask }
}

/// One `brew desc` batch: a list of names of one kind.
public struct DescriptionsRequest: Codable, Sendable {
    public let names: [String]
    public let isCask: Bool
    public init(names: [String], isCask: Bool) { self.names = names; self.isCask = isCask }
}

public struct BrewPackage: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let version: String
    public let isCask: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    public init(name: String, version: String, isCask: Bool) {
        self.name = name; self.version = version; self.isCask = isCask
    }
}

public struct OutdatedPackage: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let installed: String
    public let latest: String
    public let isCask: Bool
    /// Held at this version on purpose. brew still reports it as outdated and
    /// `brew upgrade` still refuses it, so a row that offers Upgrade offers a
    /// button that answers "…is pinned".
    public let pinned: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
    public init(name: String, installed: String, latest: String, isCask: Bool,
                pinned: Bool = false) {
        self.name = name; self.installed = installed; self.latest = latest
        self.isCask = isCask; self.pinned = pinned
    }
}

public struct SearchHit: Codable, Equatable, Sendable, Identifiable {
    public let name: String
    public let isCask: Bool
    public var id: String { BrewKey.of(name: name, isCask: isCask) }
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
