import Foundation
public struct EngineCommand: Codable, Sendable { public let name: String; public let payload: Data
    public init(name: String, payload: Data = Data()) { self.name = name; self.payload = payload } }
public struct EngineEvent: Codable, Sendable { public let name: String; public let payload: Data
    public init(name: String, payload: Data = Data()) { self.name = name; self.payload = payload } }
