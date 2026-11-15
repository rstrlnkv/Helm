// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The settings page writes `vpnAppRules` and `noticeBook` only through the
/// model. Defect class kept: a write that never reaches the store, that applies
/// a change to a book read earlier (so a second card's write undoes the first),
/// or that a stopped model drops.
@MainActor
final class TheModelIsTheOnlyWriterOfStoredVPNKeysTests: XCTestCase {

    func testSavedRulesReachTheStoreAndTheEngine() {
        let s = VPNSettings.inMemory()
        let work = FakeVPNWork()
        let model = VPNViewModel(work: work, settings: s)
        let rules = ["com.example.app": VPNAppRule(vpnName: "Office", connectOnLaunch: false)]
        model.saveRules(rules)
        XCTAssertEqual(VPNRules.decode(s.rulesJSON), rules, "the rules did not reach the store")
        XCTAssertTrue(work.calls.contains("reloadRules"), "the engine was not told")
        model.stop()
    }

    /// The write is not the model's to withhold once it is stopped: a page still
    /// on screen saved the rule before; only the engine is left alone.
    func testRulesSavedAfterStopAreStoredButTheEngineIsLeftAlone() {
        let s = VPNSettings.inMemory()
        let work = FakeVPNWork()
        let model = VPNViewModel(work: work, settings: s)
        model.stop()
        let rules = ["com.example.app": VPNAppRule(vpnName: "Home")]
        model.saveRules(rules)
        XCTAssertEqual(VPNRules.decode(s.rulesJSON), rules, "a stopped model dropped the write")
        XCTAssertFalse(work.calls.contains("reloadRules"), "a stopped model reached the engine")
    }

    /// Two writes, the second made after the store changed under the first: the
    /// second reads the book as it is now.
    func testTheBookIsReadFreshAndOtherEntriesSurvive() {
        let s = VPNSettings.inMemory()
        let model = VPNViewModel(work: FakeVPNWork(), settings: s)
        model.updateNoticeBook { $0.setting("id-A", drop: .silent) }
        // Somebody else wrote an entry after the page took its copy.
        s.setNoticeBook(s.noticeBook.setting("id-B", drop: .system))
        let returned = model.updateNoticeBook { $0.setting("id-C", spin: true) }
        for book in [returned, s.noticeBook] {
            XCTAssertEqual(book.shown(for: "id-A", rules: .system, drop: .menuBar).drop, .silent)
            XCTAssertEqual(book.shown(for: "id-B", rules: .system, drop: .menuBar).drop, .system,
                           "the change was applied to a stale book")
        }
        XCTAssertEqual(returned, s.noticeBook, "the returned book is not what was stored")
        model.stop()
    }

    /// The page cannot bypass the model: no UI file but the model's writes either
    /// key to the store, and the page's book is only ever assigned what the model
    /// returned. A bypass keeps the screen right and loses the write.
    func testNoPageWritesAStoredKeyButThroughTheModel() throws {
        let files = try RepoSource.swiftFiles(under: "Sources/Modules/VPN/UI")
        XCTAssertFalse(files.isEmpty, "the scan found no UI files")
        for path in files where !path.hasSuffix("/VPNViewModel.swift") {
            for (n, raw) in try RepoSource.lines(of: path).enumerated() {
                let line = RepoSource.code(raw)
                for token in ["setRulesJSON", "setNoticeBook"] {
                    XCTAssertFalse(line.contains(token), "\(path):\(n + 1) writes the store, not the model")
                }
                // `_noticeBook = State(...)` is the page seeding itself from the store, a read.
                if !line.contains("_noticeBook"), let r = line.range(of: "noticeBook = ") {
                    let rhs = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                    XCTAssertTrue(rhs.hasPrefix("vm."),
                                  "\(path):\(n + 1) assigns the book something the model did not return")
                }
            }
        }
        XCTAssertTrue(try RepoSource.text(of: "Sources/Modules/VPN/UI/VPNAppRules.swift")
            .contains("vm.saveRules(rules)"), "persist() no longer saves through the model")
    }
}
