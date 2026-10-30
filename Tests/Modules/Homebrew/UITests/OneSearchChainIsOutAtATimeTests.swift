// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// One `brew search` chain is out at a time, whatever is typed behind it.
///
/// Typing is a control a person presses repeatedly, and a `search` is two
/// `brew search` runs and a `brew desc` per kind: CLAUDE.md's «never an
/// unbounded launch behind a control pressable repeatedly». A word typed while a
/// chain is out waits as the newest only, and is asked after the chain only if
/// the field still holds it. Defect class kept: a second chain launched beside
/// the first, an older word asked in between, or a word nobody is looking at any
/// more asked after all.
@MainActor
final class OneSearchChainIsOutAtATimeTests: XCTestCase {

    private func model(_ work: FakeHomebrewWork) -> HomebrewViewModel {
        let model = HomebrewViewModel(work: work)
        // The pause is the owner's 700 ms; a test that wants only Return's door
        // must not have the other one fire in the middle of it.
        model.searchPause = .seconds(3600)
        return model
    }

    private func finds(_ work: FakeHomebrewWork) -> [String] {
        work.calls.filter { $0.hasPrefix("find") }
    }

    func testASecondWordWaitsForTheFirstChain() async {
        let work = FakeHomebrewWork()
        work.park("find")
        let model = model(work)

        model.query = "ab"
        model.searchNow()
        await eventually("the first chain is out") { self.finds(work) == ["find ab"] }

        model.query = "abc"
        model.searchNow()
        await grace()
        XCTAssertEqual(finds(work), ["find ab"],
                       "a second chain went out beside the first: \(finds(work))")
        XCTAssertEqual(model.searchReading, .waiting)
        XCTAssertEqual(model.searchedQuery, "abc", "the section does not name the word that is next")

        work.release("find")
        await eventually("the queued word is asked after the first chain") {
            self.finds(work) == ["find ab", "find abc"]
        }
        await eventually("the second chain answers") { work.completed.contains("find abc") }
        await grace()
        XCTAssertEqual(finds(work), ["find ab", "find abc"], "a third chain went out")
        XCTAssertEqual(model.searchReading, .answered)
    }

    func testOnlyTheNewestWordTypedBehindAChainIsAsked() async {
        let work = FakeHomebrewWork()
        work.park("find")
        let model = model(work)

        model.query = "ab"
        model.searchNow()
        await eventually("the first chain is out") { self.finds(work) == ["find ab"] }
        for word in ["abc", "abcd", "abcde"] {
            model.query = word
            model.searchNow()
        }
        work.release("find")
        await eventually("the newest word is asked") { self.finds(work).count == 2 }
        await eventually("it answers") { work.completed.contains("find abcde") }
        await grace()
        XCTAssertEqual(finds(work), ["find ab", "find abcde"],
                       "an older word typed in between was asked: \(finds(work))")
    }

    func testAWordErasedWhileQueuedIsNeverAsked() async {
        let work = FakeHomebrewWork()
        work.park("find")
        let model = model(work)

        model.query = "ab"
        model.searchNow()
        await eventually("the first chain is out") { self.finds(work) == ["find ab"] }
        model.query = "abc"
        model.searchNow()
        model.query = ""
        work.release("find")
        await eventually("the first chain answers") { work.completed.contains("find ab") }
        await grace()
        XCTAssertEqual(finds(work), ["find ab"], "an erased word was asked: \(finds(work))")
        XCTAssertNil(model.searchedQuery)
        XCTAssertEqual(model.searchReading, .notAsked)
    }

    /// The field is re-read when the chain ends: another word in it is not the
    /// queued one, and the claim queuing made for the queued word is taken back.
    func testAWordRetypedWhileQueuedIsNotAskedAndItsClaimIsTakenBack() async {
        let work = FakeHomebrewWork()
        work.park("find")
        let model = model(work)

        model.query = "ab"
        model.searchNow()
        await eventually("the first chain is out") { self.finds(work) == ["find ab"] }
        model.query = "abc"
        model.searchNow()
        XCTAssertEqual(model.searchReading, .waiting, "control: queuing claimed the word")
        model.query = "zz"
        work.release("find")
        await eventually("the first chain answers") { work.completed.contains("find ab") }
        await eventually("the claim for the queued word is taken back") {
            model.searchedQuery == nil
        }
        await grace()
        XCTAssertEqual(finds(work), ["find ab"], "a word no longer in the field was asked")
        XCTAssertEqual(model.searchReading, .notAsked,
                       "«Searching…» stayed over a question nobody will put")
    }
}
