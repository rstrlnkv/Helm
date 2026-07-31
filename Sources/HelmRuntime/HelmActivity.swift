import Foundation
import os

/// What the app is doing, while it is doing it.
///
/// The memory trail says what a phase cost once it is over, and that has never
/// been enough: a spike of 75 → 508 → 1066 → 1338 MB across ninety seconds sat
/// in the log with no operation named beside it, and a run of timer samples was
/// read as an idle app while `listApps` and `appSizes` were running between
/// them. A footprint with no phase against it can only be guessed at.
///
/// Written by engines, read by whoever asks — the same shape as `HelmLog`, and
/// for the same reason: a module publishes what it is doing without anyone being
/// able to reach in and command it. Nothing here crosses a transport, because
/// nothing here carries a decision.
///
/// Also emits `os_signpost` intervals, so the same boundaries land on the
/// Instruments timeline beside the allocator's own. One call site, two readers;
/// finer-grained signposts (per file, per chunk) stay direct calls and never
/// enter this registry, which is phase-level only.
public enum HelmActivity {

    public struct Running: Sendable, Equatable {
        public let label: String
        public let started: Date
        public init(label: String, started: Date) {
            self.label = label
            self.started = started
        }
    }

    /// A leaked interval must not grow without bound: this is the mechanism for
    /// finding memory bugs and must not become one. Past the limit a phase runs
    /// unregistered rather than failing — the work matters more than the record.
    public static let liveLimit = 64

    private static let lock = NSLock()
    nonisolated(unsafe) private static var live: [String: Running] = [:]
    private static let signposts = OSLog(subsystem: "com.helm.app", category: .pointsOfInterest)

    /// Runs `body` as a named phase. The `defer` closes the interval on every way
    /// out — return, throw, cancellation — which is the whole reason this is a
    /// scope and not a begin/end pair somebody has to remember to close.
    @discardableResult
    public static func phase<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: signposts)
        begin(label)
        os_signpost(.begin, log: signposts, name: "phase", signpostID: id, "%{public}s", label)
        defer {
            os_signpost(.end, log: signposts, name: "phase", signpostID: id, "%{public}s", label)
            end(label)
        }
        return try body()
    }

    /// The same, for a phase whose body is `async`. Same registry, same
    /// signposts, same `defer`.
    @discardableResult
    public static func phase<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let id = OSSignpostID(log: signposts)
        begin(label)
        os_signpost(.begin, log: signposts, name: "phase", signpostID: id, "%{public}s", label)
        defer {
            os_signpost(.end, log: signposts, name: "phase", signpostID: id, "%{public}s", label)
            end(label)
        }
        return try await body()
    }

    public static func begin(_ label: String) {
        lock.lock(); defer { lock.unlock() }
        guard live.count < liveLimit else { return }
        live[label] = Running(label: label, started: Date())
    }

    public static func end(_ label: String) {
        lock.lock(); defer { lock.unlock() }
        live[label] = nil
    }

    /// Everything a module had open, dropped with the module. `ModuleHost` owns
    /// the lifecycle, so it is the only place with standing to do this: a scan
    /// task can outlive the engine that started it.
    public static func sweep(module: String) {
        lock.lock(); defer { lock.unlock() }
        for key in live.keys where key == module || key.hasPrefix(module + ".") {
            live[key] = nil
        }
    }

    public static var running: [Running] {
        lock.lock(); defer { lock.unlock() }
        return Array(live.values)
    }

    /// For tests, which must not inherit another test's phases.
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        live.removeAll()
    }

    /// The phrase that goes after a memory reading.
    ///
    /// Oldest first, because a phase that has been running for forty minutes is
    /// the finding. Never timed out and never hidden for being too old — that
    /// would hide the one class of defect this exists to surface.
    /// `excluding` is the phase asking. A phase's own line reports what it cost,
    /// and it knows its own name — what it cannot know is what else was running
    /// beside it, which is the only thing worth appending. Without this the line
    /// read `uninstaller.appSizes: 59 MB — nothing running`, which denies the
    /// operation named at the start of the same sentence.
    public static func describe(_ running: [Running], now: Date = Date(),
                                excluding label: String? = nil) -> String {
        let running = running.filter { $0.label != label }
        guard !running.isEmpty else { return label == nil ? "nothing running" : "" }
        return running
            .sorted { $0.started < $1.started }
            .map { "\($0.label) \(Int(now.timeIntervalSince($0.started))) s" }
            .joined(separator: ", ")
    }
}
