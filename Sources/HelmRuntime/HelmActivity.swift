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
/// a finer-grained signpost (per file, per chunk), if one is added, stays a
/// direct call and does not enter this registry, which is phase-level only.
public enum HelmActivity {

    /// One open phase. Two phases may carry the same label — two scans running at
    /// once both say `disk.scan` — and each is its own `Running` with its own
    /// start.
    public struct Running: Sendable, Equatable {
        public let label: String
        public let started: Date
        public init(label: String, started: Date) {
            self.label = label
            self.started = started
        }
    }

    /// A leaked interval must not grow without bound: this is the mechanism for
    /// finding memory bugs and must not become one. The limit counts open phases,
    /// not labels. Past it a phase runs unregistered rather than failing — the
    /// work matters more than the record.
    public static let liveLimit = 64

    private static let lock = NSLock()
    /// Every registered phase, in the order it began.
    nonisolated(unsafe) private static var live: [Running] = []
    /// Phases that began past the limit, counted by label, so that an end can be
    /// spent on them rather than on a registered phase; which end is spent on
    /// which is `end`'s to say.
    nonisolated(unsafe) private static var unregistered: [String: Int] = [:]
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
        guard live.count < liveLimit else {
            unregistered[label, default: 0] += 1
            return
        }
        live.append(Running(label: label, started: Date()))
    }

    /// Closes one phase of this label. An end carries nothing but the label, so
    /// which phase it closes is decided here, not known. Past the limit the
    /// unregistered phases of the label are spent first: the first ends of the
    /// label to arrive go to them, whosever ends they are, so a registered phase
    /// begun after an unregistered one can stay listed past its own end, until
    /// the label's next end or the module's sweep takes it. Otherwise the newest
    /// registered phase of the label goes: phases under one label that nest end
    /// newest first, so the entry left is the one still running. Two that overlap
    /// without nesting — two scans that end in the order they began —
    /// leave the label listed as often as it is open, but with the start of the
    /// one that ended. With nothing open under the label this does nothing.
    public static func end(_ label: String) {
        lock.lock(); defer { lock.unlock() }
        if let spilled = unregistered[label] {
            unregistered[label] = spilled > 1 ? spilled - 1 : nil
        } else if let index = live.lastIndex(where: { $0.label == label }) {
            live.remove(at: index)
        }
    }

    /// Everything a module had open, dropped with the module, every phase of
    /// each of its labels. `ModuleHost` owns the lifecycle, so it is the only
    /// place with standing to do this: a scan task can outlive the engine that
    /// started it.
    public static func sweep(module: String) {
        lock.lock(); defer { lock.unlock() }
        func owned(_ key: String) -> Bool { key == module || key.hasPrefix(module + ".") }
        live.removeAll { owned($0.label) }
        unregistered = unregistered.filter { !owned($0.key) }
    }

    /// One entry per open phase, so two phases under one label are two entries.
    public static var running: [Running] {
        lock.lock(); defer { lock.unlock() }
        return live
    }

    /// For tests, which must not inherit another test's phases.
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        live.removeAll()
        unregistered.removeAll()
    }

    /// The phrase that goes after a memory reading.
    ///
    /// Oldest first, because a phase that has been running for forty minutes is
    /// the finding. Never timed out and never hidden for being too old — that
    /// would hide the one class of defect this exists to surface.
    /// `excluding` is the phase asking. A phase's own line reports what it cost,
    /// and it knows its own name — what it cannot know is what else was running
    /// beside it, which is the only thing worth appending. It drops one phase,
    /// the newest of that label, so a second phase under the same label is still
    /// named. Nothing tells it which phase is asking: when the older of two asks,
    /// the entry it drops is the newer one's and the age on the line is the
    /// asker's own. Without this the line read
    /// `uninstaller.appSizes: 59 MB — nothing running`, which denies the
    /// operation named at the start of the same sentence.
    ///
    /// «No phases running», not «nothing running»: an empty registry means no
    /// *named phase* is open, and that is all it means. The SwiftUI render, a
    /// VPN refresh, the Layout tap, the update check and the trash sweep all
    /// run outside this registry — a reading taken beside any of them is not a
    /// reading of an idle app, and the line must not say it is.
    public static func describe(_ running: [Running], now: Date = Date(),
                                excluding label: String? = nil) -> String {
        var running = running
        if let asking = running.indices.filter({ running[$0].label == label })
            .max(by: { running[$0].started < running[$1].started }) {
            running.remove(at: asking)
        }
        guard !running.isEmpty else { return label == nil ? "no phases running" : "" }
        return running
            .sorted { $0.started < $1.started }
            .map { "\($0.label) \(Int(now.timeIntervalSince($0.started))) s" }
            .joined(separator: ", ")
    }
}
