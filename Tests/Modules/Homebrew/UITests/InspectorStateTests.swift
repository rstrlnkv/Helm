import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// The inspector's whole decision, without a view.
///
/// Five things decide it: which segment, what is selected, what the lists
/// hold, whether `brew outdated` has ever answered, and whether the
/// description batch has answered yet. The fourth is `loadedOutdated`, not an
/// absence folded into the reading: `loadIfNeeded` deliberately never asks
/// `brew outdated`, so a freshly opened Installed segment must read as "not
/// asked" and not as "up to date" — `HomebrewSettingsPage.statusLine` already
/// carries this rule for the status bar, and the inspector must not disagree
/// with it about the same package. The description is the other one that must
/// not turn into a wait — a package with no description yet is drawn with
/// everything else it has, because `brew desc` is a second process and the
/// inspector is not allowed to be blank while it runs.
final class InspectorStateTests: XCTestCase {

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
    /// A `brew doctor` finding, with the fix the engine judged runnable. The
    /// body is the real one from this Mac's own output, heading and all, because
    /// that is what `DoctorFixCandidate` reads — a reconstruction would let the
    /// fixture and the extractor drift.
    private let deprecated = DoctorIssue(
        severity: .caution, title: "Some installed formulae are deprecated or disabled.",
        body: "You should find replacements for the following formulae:\n\n  periphery",
        fix: DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable))

    private func state(_ segment: HomebrewViewModel.Segment, _ selected: String?,
                       installed: [BrewPackage]? = nil,
                       hits: [SearchHit]? = nil,
                       loadedOutdated: Bool = true,
                       issues: [DoctorIssue]? = nil,
                       descriptions: [String: String] = [:]) -> InspectorState {
        InspectorState.of(segment: segment, selected: selected,
                          installed: installed ?? [openssl, node],
                          outdated: [nodeOutdated, pinned],
                          loadedOutdated: loadedOutdated,
                          hits: hits ?? [helm], issues: issues ?? [deprecated],
                          descriptions: descriptions)
    }

    func testNothingSelectedIsItsOwnState() {
        XCTAssertEqual(state(.installed, nil), .nothingSelected)
    }

    func testAnInstalledPackageOffersItsRemoval() {
        guard case let .package(subject) = state(.installed, openssl.id) else {
            return XCTFail("expected a package")
        }
        XCTAssertEqual(subject.id, openssl.id)
        XCTAssertEqual(subject.name, "openssl@3")
        XCTAssertEqual(subject.version, "3.6.4")
        XCTAssertEqual(subject.action, .uninstall)
        XCTAssertEqual(subject.updates, .upToDate)
    }

    /// `loadIfNeeded` never asks `brew outdated` on first open — the state
    /// must say "not asked" rather than invent "up to date" about a question
    /// nobody put.
    func testAnInstalledPackageWithNoOutdatedReadingIsNotAsked() {
        guard case let .package(subject) = state(.installed, openssl.id, loadedOutdated: false) else {
            return XCTFail("expected a package")
        }
        XCTAssertEqual(subject.updates, .notAsked)
    }

    /// An installed package that also shows up in the outdated list carries
    /// the update it is offering — the same reading the Updates segment shows
    /// under a different door.
    func testAnInstalledPackageThatIsOutdatedNamesTheUpdate() {
        guard case let .package(subject) = state(.installed, node.id) else {
            return XCTFail("expected a package")
        }
        XCTAssertEqual(subject.updates, .available("26.9.0"))
    }

    /// The one place the version is two versions.
    func testAnOutdatedPackageCarriesBothVersions() {
        guard case let .package(subject) = state(.updates, nodeOutdated.id) else {
            return XCTFail("expected a package")
        }
        XCTAssertEqual(subject.version, "26.8.2 → 26.9.0")
        XCTAssertEqual(subject.action, .upgrade)
        XCTAssertEqual(subject.updates, .notApplicable)
    }

    /// `brew upgrade` answers a pinned formula with "…is pinned", so the
    /// inspector must not offer a button that can only fail — the row list
    /// already learned this.
    func testAPinnedPackageIsNotOfferedAnUpgrade() {
        guard case let .package(subject) = state(.updates, pinned.id) else {
            return XCTFail("expected a package")
        }
        XCTAssertEqual(subject.action, .pinned)
    }

    func testASearchHitThatIsNotInstalledOffersInstallation() {
        guard case let .package(subject) = state(.search, helm.id) else {
            return XCTFail("expected a package")
        }
        XCTAssertEqual(subject.action, .install)
        XCTAssertEqual(subject.version, "")
    }

    /// The approved prototype marks an installed hit in the search list —
    /// the row draws a badge for it (`design/Main.dc.html:400`) and the
    /// inspector has to agree with the row: a hit already on this Mac offers
    /// its removal, not a second install.
    func testASearchHitThatIsAlreadyInstalledOffersRemoval() {
        let hit = SearchHit(name: "openssl@3", isCask: false)
        guard case let .package(subject) = state(.search, hit.id, installed: [openssl], hits: [hit])
        else {
            return XCTFail("expected a package")
        }
        XCTAssertEqual(subject.action, .uninstall)
        XCTAssertEqual(subject.version, "3.6.4")
    }

    /// A selection into a list that no longer holds it is nothing selected —
    /// belt and braces beside the view model's own reconcile.
    func testASelectionTheListDoesNotHoldIsNothing() {
        XCTAssertEqual(state(.installed, "f:gone"), .nothingSelected)
    }

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

    func testADescriptionIsUsedWhenItHasArrivedAndOmittedWhenItHasNot() {
        guard case let .package(without) = state(.installed, openssl.id) else {
            return XCTFail("expected a package")
        }
        XCTAssertNil(without.desc, "a description that has not arrived must not be an empty string")

        guard case let .package(with) = state(.installed, openssl.id,
                                              descriptions: [openssl.id: "Cryptography and SSL/TLS Toolkit"])
        else { return XCTFail("expected a package") }
        XCTAssertEqual(with.desc, "Cryptography and SSL/TLS Toolkit")
    }

    // MARK: - The health segment

    /// A finding is its own kind of subject: nothing about it is composed from
    /// two containers, and nothing about it is waited on.
    func testASelectedFindingIsTheIssueItself() {
        XCTAssertEqual(state(.health, deprecated.id), .issue(deprecated))
    }

    /// The same rule the other three segments carry, and it has to be the same
    /// rule: a finding the last `brew doctor` no longer names is a stale
    /// sentence about the machine with a live button under it.
    func testASelectionTheIssueListNoLongerHoldsIsNothing() {
        // A *different* finding rather than an empty list: with nothing in the
        // list at all, a lookup that ignored the id and took whatever was first
        // would answer nil by accident and this would pass over it.
        let other = DoctorIssue(severity: .danger, title: "Something else", body: "", fix: nil)
        XCTAssertEqual(state(.health, deprecated.id, issues: [other]), .nothingSelected)
        XCTAssertEqual(state(.health, deprecated.id, issues: []), .nothingSelected)
    }

    /// **A finding is never read as a package, and a package never as a
    /// finding.** The two lists are keyed differently — a `BrewKey` id against
    /// `DoctorIssue`'s content-built one — but nothing stops a lookup that
    /// ignored the segment from finding one in the other's list, and the
    /// inspector would then offer Uninstall for a `brew doctor` warning.
    func testTheSegmentDecidesWhichListIsSearched() {
        XCTAssertEqual(state(.health, openssl.id), .nothingSelected,
                       "a package id selected in the health segment found a package")
        XCTAssertEqual(state(.installed, deprecated.id), .nothingSelected,
                       "a finding's id selected in the installed segment found a finding")
    }
}
