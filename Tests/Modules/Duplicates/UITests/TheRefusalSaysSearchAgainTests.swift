import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Duplicates_UI

/// This page's refusal sentences name this page's control.
///
/// Three modules say «Scan again» and draw a «Scan again» button; this page's
/// button is `DupStr.searchAgain` — and here `changedSinceScan` is not an
/// exotic refusal but the ordinary one, raised by the engine itself for every
/// pair that stopped matching. So the failure rows are built with
/// `TrashReasonText.Refresh.search`, and the sentence ends with the verb the
/// toolbar actually carries.
final class TheRefusalSaysSearchAgainTests: XCTestCase {

    /// Read from the page's source, because the claim is about what the page
    /// passes: a verb the sentence supports and the page never asks for fixes
    /// nothing on screen.
    func testThePageBuildsItsFailureRowsWithTheSearchVerb() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        XCTAssertTrue(page.contains("HelmRemovalFailure($0, refresh: .search)"), """
            The failure rows fell back to the default `.scan` wording, which names \
            a button this page does not have.
            """)
        XCTAssertFalse(page.contains("failures.map(HelmRemovalFailure.init)"),
                       "the point-free spelling cannot carry the verb")
    }
}
