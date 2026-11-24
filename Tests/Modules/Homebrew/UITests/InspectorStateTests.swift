import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

private let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
private let node = BrewPackage(name: "node", version: "26.8.2", isCask: false)
private let nodeOutdated = OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                           isCask: false)
private let pinned = OutdatedPackage(name: "git", installed: "2.54.0", latest: "2.55.0",
                                     isCask: false, pinned: true)
private let helm = SearchHit(name: "helm", isCask: false)
/// `docker` is both a formula and a cask — the defect `BrewKey` exists
/// against (`Model.swift`'s own doc comment). A lookup by name alone
/// would find whichever one comes first.
private let dockerFormula = BrewPackage(name: "docker", version: "1.0.0", isCask: false)
private let dockerCask = BrewPackage(name: "docker", version: "2.0.0", isCask: true)
private func state(_ segment: HomebrewViewModel.Segment, _ selected: String?,
                   installed: [BrewPackage]? = nil,
                   hits: [SearchHit]? = nil,
                   loadedOutdated: Bool = true,
                   descriptions: [String: String] = [:]) -> InspectorState {
    InspectorState.of(segment: segment, selected: selected,
                      installed: installed ?? [openssl, node],
                      outdated: [nodeOutdated, pinned],
                      loadedOutdated: loadedOutdated,
                      hits: hits ?? [helm], descriptions: descriptions)
}

/// The inspector's whole decision, without a view.
///
/// Five things decide it: which segment, what is selected, what the lists
/// hold, whether `brew outdated` has ever answered, and whether the
/// description batch has answered yet. The fourth is `loadedOutdated`, not an
/// absence folded into the reading: `loadIfNeeded` deliberately never asks
/// `brew outdated`, so a freshly opened Installed segment must read as "not
/// asked" and not as "up to date" — `HomebrewManager.statusLine` already
/// carries this rule for the status bar, and the inspector must not disagree
/// with it about the same package. The description is the other one that must
/// not turn into a wait — a package with no description yet is drawn with
/// everything else it has, because `brew desc` is a second process and the
/// inspector is not allowed to be blank while it runs.
final class InspectorStateTests: XCTestCase {

    /// `docker` is both a formula and a cask, and the two must not collide —
    /// this is the exact defect `BrewKey`'s own doc comment names.
    func testLookupIsByIdAndNotByName() {
        guard case let .package(subject) = state(.installed, dockerCask.id,
                                                 installed: [dockerFormula, dockerCask]) else {
            return XCTFail("expected a package")
        }
        XCTAssertTrue(subject.isCask)
        XCTAssertEqual(subject.version, "2.0.0")
    }
}
