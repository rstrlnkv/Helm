// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// Stands for the engine on the model's side of `HomebrewWork`: the port's
/// members and nothing the engine has beyond them.
///
/// A call is written down by its member's name (`calls`), with the one thing it
/// was asked about after a space where it has one (`find wget`); a press is
/// kept whole in `acts` and noted in `calls` as `perform`. `say(_:)` is what the
/// engine would emit; the last line and the last state are replayed to a stream
/// taken afterwards in the order the two kinds first appeared, after where brew
/// is, which activation says before any operation — `LocalTransport` keeps the
/// same order for the engine. A stream the
/// consumer let go of is counted (`finishedStreams`), so «the loop was
/// cancelled» is read from the work and not assumed from the model.
///
/// `park(_:)` holds the next reads of one member (`find`, `readDependents`, ...)
/// open until `release(_:)`: an order of events that a fake answering at once
/// cannot show. `completed` is what has been answered, so a test can tell «still
/// out» from «answered and nothing followed». Every test that parks releases.
final class FakeHomebrewWork: HomebrewWork, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var answered: [String] = []
    private var performed: [HomebrewAct] = []
    private var dependentsRefs: [PackageRef] = []
    private var parkedMembers: Set<String> = []
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var lastLine: HomebrewNews?
    private var lastState: HomebrewNews?
    private var lastBrew: HomebrewNews?
    private var order: [Bool] = []          // true: the line kind appeared first
    private var live: [UUID: AsyncStream<HomebrewNews>.Continuation] = [:]
    private var finished = 0

    // What the engine answers. Written by a test before the model reads.
    var status = BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew")
    var installed: [BrewPackage]? = []
    var outdated: [OutdatedPackage]? = []
    var hits: [SearchHit]? = []
    var dependents: [String]? = []
    var doctor: [DoctorIssue]? = []
    var config: BrewConfig?
    var info: PackageInfo?
    var bytes: Int?
    var described: [String: String] = [:]

    /// Every call, in order: `stream`, `readStatus`, `readInstalled`,
    /// `readOutdated`, `readDescriptions`, `find <q>`, `readDependents <name>`,
    /// `readInfo <name>`, `measure <name>`, `readDoctor`, `readConfig`,
    /// `perform`.
    var calls: [String] { lock.withLock { recorded } }
    /// The calls that came back with their answer.
    var completed: [String] { lock.withLock { answered } }
    var acts: [HomebrewAct] { lock.withLock { performed } }
    /// The package each `readDependents` was asked about, kind included.
    var dependentsAsked: [PackageRef] { lock.withLock { dependentsRefs } }
    var finishedStreams: Int { lock.withLock { finished } }
    var subscribers: Int { lock.withLock { live.count } }

    // MARK: - What the engine says

    func say(_ news: HomebrewNews) {
        let open = lock.withLock { () -> [AsyncStream<HomebrewNews>.Continuation] in
            switch news {
            case .line:
                if lastLine == nil { order.append(true) }
                lastLine = news
            case .state:
                if lastState == nil { order.append(false) }
                lastState = news
            case .brew:
                lastBrew = news
            }
            return Array(live.values)
        }
        for continuation in open { continuation.yield(news) }
    }

    func stream() -> AsyncStream<HomebrewNews> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                recorded.append("stream")
                // Where brew is is said at activation, before any operation speaks.
                if let news = lastBrew { continuation.yield(news) }
                for lineFirst in order {
                    if let news = lineFirst ? lastLine : lastState { continuation.yield(news) }
                }
                live[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.live[id] = nil; self?.finished += 1 }
            }
        }
    }

    // MARK: - Holding a read open

    /// The next reads of `member` wait until `release(_:)`.
    func park(_ member: String) { lock.withLock { _ = parkedMembers.insert(member) } }

    /// Lets every waiting read of `member` answer, and the later ones too.
    func release(_ member: String) {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            parkedMembers.remove(member)
            return waiting.removeValue(forKey: member) ?? []
        }
        for waiter in waiters { waiter.resume() }
    }

    private func hold(_ member: String) async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let mustWait = lock.withLock { () -> Bool in
                guard parkedMembers.contains(member) else { return false }
                waiting[member, default: []].append(waiter)
                return true
            }
            if !mustWait { waiter.resume() }
        }
    }

    private func read<T>(_ call: String, member: String, _ answer: () -> T) async -> T {
        lock.withLock { recorded.append(call) }
        await hold(member)
        lock.withLock { answered.append(call) }
        return answer()
    }

    // MARK: - The port

    func readStatus() async -> BrewStatus {
        await read("readStatus", member: "readStatus") { status }
    }
    func readInstalled() async -> [BrewPackage]? {
        await read("readInstalled", member: "readInstalled") { installed }
    }
    func readOutdated() async -> [OutdatedPackage]? {
        await read("readOutdated", member: "readOutdated") { outdated }
    }
    func readDescriptions(of names: [String], isCask: Bool) async -> [String: String] {
        await read("readDescriptions", member: "readDescriptions") { described }
    }
    func find(_ query: String) async -> [SearchHit]? {
        await read("find \(query)", member: "find") { hits }
    }
    func readDependents(of package: PackageRef) async -> [String]? {
        lock.withLock { dependentsRefs.append(package) }
        return await read("readDependents \(package.name)", member: "readDependents") { dependents }
    }
    func readInfo(about package: PackageRef) async -> PackageInfo? {
        await read("readInfo \(package.name)", member: "readInfo") { info }
    }
    func measure(_ package: PackageRef, version: String) async -> Int? {
        await read("measure \(package.name)", member: "measure") { bytes }
    }
    func readDoctor() async -> [DoctorIssue]? {
        await read("readDoctor", member: "readDoctor") { doctor }
    }
    func readConfig() async -> BrewConfig? {
        await read("readConfig", member: "readConfig") { config }
    }

    func perform(_ act: HomebrewAct) {
        lock.withLock { recorded.append("perform"); performed.append(act) }
    }
}

extension XCTestCase {

    /// Waits for something another task will do, by the clock and not by turns
    /// on the cooperative pool, and fails naming what never happened. For a
    /// condition that must come true; an absence is read after one of these has
    /// proved the subject happened, then `grace()`.
    @MainActor
    func eventually(_ what: String, timeout: TimeInterval = 5,
                    file: StaticString = #filePath, line: UInt = #line,
                    _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "never reached: \(what)", file: file, line: line)
    }
}
