import XCTest
@testable import Module_Homebrew_Engine

final class BrewListParserTests: XCTestCase {
    func testParsesNameVersionSkipsBlanksAndTakesFirstVersion() {
        let out = "ada-url 3.4.4\nbrotli 1.2.0\n\nc-ares 1.34.8\nmulti 1.0 1.1\nnoversion\n"
        let pkgs = BrewListParser.parse(out, isCask: false)
        XCTAssertEqual(pkgs.count, 5)
        XCTAssertEqual(pkgs[0], BrewPackage(name: "ada-url", version: "3.4.4", isCask: false))
        XCTAssertEqual(pkgs.first { $0.name == "multi" }?.version, "1.0")
        XCTAssertEqual(pkgs.first { $0.name == "noversion" }?.version, "")
    }
    func testCaskFlag() {
        XCTAssertTrue(BrewListParser.parse("figma 1.0\n", isCask: true).allSatisfy(\.isCask))
    }
}

final class BrewOutdatedParserTests: XCTestCase {
    func testParsesFormulaeAndCasks() {
        let json = """
        {"formulae":[{"name":"deno","installed_versions":["2.9.3"],"current_version":"2.9.4"}],
         "casks":[{"name":"figma","installed_versions":["1.2.3"],"current_version":"1.2.4"}]}
        """.data(using: .utf8)!
        let out = BrewOutdatedParser.parse(json)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.first { $0.name == "deno" },
                       OutdatedPackage(name: "deno", installed: "2.9.3", latest: "2.9.4", isCask: false))
        XCTAssertEqual(out.first { $0.name == "figma" }?.isCask, true)
    }
    func testEmpty() {
        XCTAssertTrue(BrewOutdatedParser.parse(#"{"formulae":[],"casks":[]}"#.data(using: .utf8)!).isEmpty)
        XCTAssertTrue(BrewOutdatedParser.parse(Data()).isEmpty)
    }
    func testMissingInstalledVersions() {
        let json = #"{"formulae":[{"name":"x","current_version":"2.0"}]}"#.data(using: .utf8)!
        XCTAssertEqual(BrewOutdatedParser.parse(json).first?.installed, "")
    }
}

final class BrewSearchParserTests: XCTestCase {
    func testSectionedOutput() {
        let out = "==> Formulae\nwget\nwget2\n\n==> Casks\nwget-gui\n"
        let hits = BrewSearchParser.parse(out)
        XCTAssertEqual(hits, [SearchHit(name: "wget", isCask: false),
                              SearchHit(name: "wget2", isCask: false),
                              SearchHit(name: "wget-gui", isCask: true)])
    }
    func testFlatListIsFormulae() {
        XCTAssertEqual(BrewSearchParser.parse("wget\nwget2\n"),
                       [SearchHit(name: "wget", isCask: false), SearchHit(name: "wget2", isCask: false)])
    }
    func testNoResults() {
        XCTAssertTrue(BrewSearchParser.parse("No formulae or casks found for \"zzz\".\n").isEmpty)
        XCTAssertTrue(BrewSearchParser.parse("").isEmpty)
    }
}
