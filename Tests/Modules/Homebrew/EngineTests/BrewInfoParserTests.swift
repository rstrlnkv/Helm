import XCTest
@testable import Module_Homebrew_Engine

/// The document `brew info --json=v2` answers, and the four places a formula
/// and a cask disagree about shape.
///
/// Every fixture here is trimmed from a real document captured on this Mac on
/// 2026-09-14 against Homebrew 7.0.1 — the keys, the nesting and the null are
/// what the tool actually printed, not what a struct would have been convenient
/// to write.
final class BrewInfoParserTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // deprecation_reason and deprecation_replacement_formula carry non-null
    // values here on purpose, on an entry that is not deprecated — a fixture
    // where both are already null cannot tell "read only when deprecated" from
    // "always nil in this document", and a check that cannot fail is not a
    // check. See testAFormulaIsReadWhole below.
    private let formula = """
    {"formulae":[{"name":"openssl@3","desc":"Cryptography and SSL/TLS Toolkit",
    "homepage":"https://openssl-library.org","license":"Apache-2.0","tap":"homebrew/core",
    "deprecated":false,"deprecation_reason":"repo_archived","deprecation_replacement_formula":"openssl@4",
    "versions":{"stable":"3.6.4","head":"HEAD","bottle":true},
    "versioned_formulae":["openssl@4","openssl@3.5"],"dependencies":["ca-certificates"],
    "caveats":"To add additional certificates…",
    "installed":[{"version":"3.6.4","time":1757800000,"installed_on_request":false}]}],"casks":[]}
    """

    // license carries a value here on purpose, though a cask document never
    // actually has this key — a fixture that simply omits the key cannot
    // tell "the parser drops a cask's license" from "there was never one to
    // drop" (JSONSerialization answers the same nil either way).
    private let cask = """
    {"formulae":[],"casks":[{"token":"claude-code","name":["Claude Code"],
    "desc":"Terminal-based AI coding assistant","homepage":"https://claude.com/product/claude-code",
    "tap":"homebrew/cask","license":"MIT","deprecated":false,"deprecation_reason":null,
    "version":"2.1.236","installed":"2.1.236","installed_time":1757800000,"caveats":null}]}
    """

    private let deprecated = """
    {"formulae":[{"name":"periphery","desc":"Identify unused code in Swift projects",
    "homepage":"https://github.com/peripheryapp/periphery","license":"MIT","tap":"homebrew/core",
    "deprecated":true,"deprecation_reason":"repo_archived","deprecation_replacement_formula":null,
    "versions":{"stable":"3.8.0","head":null,"bottle":true},
    "versioned_formulae":[],"dependencies":[],"caveats":null,
    "installed":[{"version":"3.8.0","time":1753500000,"installed_on_request":true}]}],"casks":[]}
    """

    func testAFormulaIsReadWhole() {
        guard let info = BrewInfoParser.parse(data(formula), isCask: false) else {
            return XCTFail("the document was refused")
        }
        XCTAssertEqual(info.name, "openssl@3")
        XCTAssertEqual(info.desc, "Cryptography and SSL/TLS Toolkit")
        XCTAssertEqual(info.homepage, "https://openssl-library.org")
        XCTAssertEqual(info.license, "Apache-2.0")
        XCTAssertEqual(info.installedVersion, "3.6.4")
        XCTAssertEqual(info.latestVersion, "3.6.4",
                       "a formula's current version is `versions.stable`, not a flat key")
        XCTAssertEqual(info.installedOnRequest, false)
        XCTAssertEqual(info.siblings, ["openssl@4", "openssl@3.5"])
        XCTAssertEqual(info.dependencies, ["ca-certificates"])
        XCTAssertNotNil(info.installedAt)
        XCTAssertNil(info.deprecationReason,
                      "not deprecated — a reason present in the document must not surface")
        XCTAssertNil(info.replacement,
                      "not deprecated — a replacement present in the document must not surface")
    }

    /// The three shapes a cask does differently, in one case.
    func testACaskCarriesItsOwnShape() {
        guard let info = BrewInfoParser.parse(data(cask), isCask: true) else {
            return XCTFail("the document was refused")
        }
        XCTAssertEqual(info.name, "claude-code")
        XCTAssertNil(info.license, "a cask has no licence field, and an invented one is worse than none")
        XCTAssertEqual(info.installedVersion, "2.1.236")
        XCTAssertEqual(info.latestVersion, "2.1.236",
                       "a cask's current version is a flat `version`, with no `versions` object")
        XCTAssertNotNil(info.installedAt, "a cask's install time is top-level, not inside an array")
        XCTAssertNil(info.installedOnRequest, "a cask does not record who asked for it")
    }

    /// The reason is the fact that matters: "deprecated" alone tells a person
    /// nothing they can act on.
    func testADeprecatedFormulaCarriesItsReason() {
        guard let info = BrewInfoParser.parse(data(deprecated), isCask: false) else {
            return XCTFail("the document was refused")
        }
        XCTAssertEqual(info.deprecationReason, "repo_archived")
        XCTAssertNil(info.replacement, "nothing was offered, and an empty string would read as one")
        XCTAssertEqual(info.installedOnRequest, true)
    }

    /// A package that is not installed has no install facts — and that is not
    /// the same as a query that failed.
    func testAnUninstalledPackageIsStillAnAnswer() {
        let json = """
        {"formulae":[{"name":"helm","desc":"Kubernetes package manager","homepage":"https://helm.sh",
        "license":"Apache-2.0","tap":"homebrew/core","deprecated":false,"versioned_formulae":[],
        "versions":{"stable":"3.19.1","head":null,"bottle":true},
        "dependencies":[],"caveats":null,"installed":[]}],"casks":[]}
        """
        guard let info = BrewInfoParser.parse(data(json), isCask: false) else {
            return XCTFail("the document was refused")
        }
        XCTAssertNil(info.installedVersion)
        XCTAssertNil(info.installedAt)
        XCTAssertNil(info.installedOnRequest)
        XCTAssertEqual(info.latestVersion, "3.19.1", """
            a package that is not installed has no version anywhere else in this module — \
            the lists carry one only for what is on disk, and `brew search` answers with \
            names alone
            """)
        XCTAssertEqual(info.desc, "Kubernetes package manager")
    }

    /// nil is "this is not the document I was promised", and it must not be
    /// reachable by an empty answer that a caller would draw as facts.
    func testADocumentThisParserDoesNotKnowIsNotAnAnswer() {
        XCTAssertNil(BrewInfoParser.parse(data("not json"), isCask: false))
        XCTAssertNil(BrewInfoParser.parse(Data(), isCask: false))
        XCTAssertNil(BrewInfoParser.parse(data(#"{"formulae":[],"casks":[]}"#), isCask: false),
                     "an empty array is a name brew could not resolve, not a package with no facts")
        XCTAssertNil(BrewInfoParser.parse(data(formula), isCask: true),
                     "a formula document asked about as a cask is not an answer about a cask")
    }
}
