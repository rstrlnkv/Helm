// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Two searches in flight, and the slower one wins by arriving last.**
///
/// Homebrew's search field put every press of Return on its own unbounded
/// `Task` and the view model kept no idea of which search a reply belonged to,
/// so whichever `brew` finished last drew its hits — the results of a word the
/// person had already typed over. Duplicates and Leftovers had `LatestRequest`
/// for this; Homebrew did not.
///
/// It is also what made the launch crash reachable: one search is two `brew
/// search` runs of about nine seconds followed by a `brew desc` per kind, so
/// ten presses were twenty-odd children at once
/// (`NoScreenCanHaveTwentyToolsOutTests` is the floor under that).
@MainActor
final class AStaleSearchDoesNotLandOnANewerOneTests: XCTestCase {

    /// A transport that holds each search until the test lets it answer, so two
    /// can genuinely be in flight at once.
    ///
    /// **A fake that answered at once would make this test vacuous**: the first
    /// search would be over before the second was made, and the ordering the
    /// test is about could not happen (CLAUDE.md § a fake that finishes
    /// instantly makes a test of a wait vacuous).
    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        private let lock = NSLock()
        private var replies: [String: Data] = [:]
        private var _searches = 0
        private var _descriptions = 0

        /// The answer a search for `query` will give, once released.
        func answer(_ query: String, with hits: [SearchHit]) {
            lock.lock(); replies[query] = try! JSONEncoder().encode(hits); lock.unlock()
        }
        var searches: Int { lock.lock(); defer { lock.unlock() }; return _searches }
        var descriptions: Int { lock.lock(); defer { lock.unlock() }; return _descriptions }

        /// **A gate per query, so the test chooses which search answers first.**
        ///
        /// One shared semaphore released twice was a coin toss: which of two
        /// parked calls a `DispatchSemaphore` wakes is not the test's to decide,
        /// and the whole subject here is arrival order. Measured with one gate,
        /// the same mutation failed one run and could have passed the next —
        /// which is a guard that stops being able to fail without anybody
        /// touching it.
        private var gates: [String: DispatchSemaphore] = [:]

        private func gate(for query: String) -> DispatchSemaphore {
            lock.lock(); defer { lock.unlock() }
            if let existing = gates[query] { return existing }
            let made = DispatchSemaphore(value: 0)
            gates[query] = made
            return made
        }

        /// Lets the search for `query` answer.
        func release(_ query: String) { gate(for: query).signal() }

        /// Synchronous, and that is not a style choice: Swift 6 makes
        /// `NSLock.lock()` unavailable inside an `async` function outright, and
        /// the reason is the one CLAUDE.md gives — a lock held across an await
        /// is a lock taken on one side of a field.
        private func enteredSearch(_ query: String) -> Data? {
            lock.lock(); defer { lock.unlock() }
            _searches += 1
            return replies[query]
        }

        private func enteredDescriptions() {
            lock.lock(); _descriptions += 1; lock.unlock()
        }

        func send(_ command: EngineCommand) async throws -> Data {
            if command.name == HomebrewCommand.descriptions.rawValue {
                enteredDescriptions()
                return try JSONEncoder().encode([String: String]())
            }
            guard command.name == HomebrewCommand.search.rawValue else { return Data() }
            let query = String(data: command.payload, encoding: .utf8) ?? ""
            let reply = enteredSearch(query)
            let gate = gate(for: query)
            // Off the cooperative pool the way the real wait is: a semaphore
            // parked inside an `async` function would hold one of its threads.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    gate.wait()
                    continuation.resume()
                }
            }
            return reply ?? Data()
        }
    }

    private func hit(_ name: String) -> SearchHit {
        SearchHit(name: name, isCask: false)
    }

    func testTheOlderSearchesHitsAreDroppedWhenItAnswersLast() async {
        let transport = HeldTransport()
        transport.answer("first", with: [hit("aaa-old")])
        transport.answer("second", with: [hit("zzz-new")])
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        // Both pressed before either answers, which is the state the whole
        // thing is about.
        let older = Task { await model.search("first") }
        let newer = Task { await model.search("second") }
        while transport.searches < 2 { await Task.yield() }

        // The newer one answers and is drawn; **then** the older one arrives,
        // which is the order that used to put a stale word's results on the
        // screen. Awaited in between, so the second answer really does land on
        // top of the first rather than racing it.
        transport.release("second")
        _ = await newer.value
        transport.release("first")
        _ = await older.value

        XCTAssertEqual(model.searchHits.map(\.name), ["zzz-new"], """
            the page is showing \(model.searchHits.map(\.name)) — the results of a \
            search the person typed over, because whichever brew answered last won
            """)
    }

    /// And the abandoned search stops spending `brew` runs on descriptions: the
    /// hits it fetched them for are never drawn.
    func testTheAbandonedSearchAsksForNoDescriptions() async {
        let transport = HeldTransport()
        transport.answer("first", with: [hit("aaa-old")])
        transport.answer("second", with: [hit("zzz-new")])
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        let older = Task { await model.search("first") }
        let newer = Task { await model.search("second") }
        while transport.searches < 2 { await Task.yield() }
        transport.release("second")
        _ = await newer.value
        transport.release("first")
        _ = await older.value

        // **Exactly one, and the bound has to be exact.** Written as «at most
        // two» this passed with the token check taken out — each search here
        // has one formula and no cask, so it costs one batch either way and the
        // ceiling was above both answers. A threshold above every real case is
        // a check that cannot fail (CLAUDE.md), and the mutation is what said
        // so rather than a reading of the test.
        XCTAssertEqual(transport.descriptions, 1, """
            \(transport.descriptions) description batches were fetched where one \
            search is on screen — the abandoned one paid for its own, which is a \
            brew run for a word the person has typed over
            """)
    }

    /// The precondition both rest on: a single search still draws its hits.
    /// Without it the two above hold on a view model that draws nothing.
    func testOneSearchStillDrawsItsHits() async {
        let transport = HeldTransport()
        transport.answer("only", with: [hit("wget")])
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))

        let task = Task { await model.search("only") }
        while transport.searches < 1 { await Task.yield() }
        transport.release("only")
        _ = await task.value

        XCTAssertEqual(model.searchHits.map(\.name), ["wget"])
    }
}
