import HelmContract

/// The engine side of `ModuleEngine`, for a test that asks what the host did to an engine
/// and not what an engine does.
///
/// **One fake for the port** — it carries the three calls and the one answer (`standsIn`)
/// a scenario reads. It counts what it is asked
/// and hands each call, in order, to `record` for a test that keeps one journal across several
/// engines (the event is the call's name: `activate`, `willDisable`, `deactivate`).
public final class FakeEngine: ModuleEngine {
    public let standsIn: Bool
    public private(set) var activations = 0
    public private(set) var willDisables = 0
    public private(set) var deactivations = 0
    private let record: (String) -> Void

    public init(standsIn: Bool = false, record: @escaping (String) -> Void = { _ in }) {
        self.standsIn = standsIn
        self.record = record
    }

    public func activate() { activations += 1; record("activate") }
    public func willDisable() { willDisables += 1; record("willDisable") }
    public func deactivate() { deactivations += 1; record("deactivate") }
}
