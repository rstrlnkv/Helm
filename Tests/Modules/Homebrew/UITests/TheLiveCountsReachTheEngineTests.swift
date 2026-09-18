import XCTest
import HelmTestSupport

/// **The whole feature can ship inert with every other test green.**
///
/// `HomebrewEngine`'s `popularity` defaults to `NoPopularity` — deliberately,
/// because a forgetful construction must never reach the network — and
/// `SearchRanking` leaves the order alone when it has no counts. So a
/// `makeEngine` that never names the real store produces an app that fetches
/// nothing, ranks nothing, and passes every unit test in the tree, including
/// the ones that prove the counts reach the ranking: those hand the engine a
/// store themselves.
///
/// Nothing at runtime can see this from inside a test — the descriptor is what
/// the host calls, and the host is the thing under nobody's test here — so the
/// wiring is read as text. `SwiftSource.code` blanks comments and the insides
/// of string literals, so a doc comment naming `ports.popularity` cannot keep
/// this green.
final class TheLiveCountsReachTheEngineTests: XCTestCase {

    private func code(_ path: String) throws -> String {
        SwiftSource.code(try RepoSource.text(of: path))
    }

    func testTheDescriptorHandsTheEngineTheLiveStore() throws {
        let path = "Sources/Modules/Homebrew/UI/HomebrewDescriptor.swift"
        // The subject first: a `makeEngine` that has been renamed away would
        // otherwise leave this passing over a file it no longer reads.
        guard let body = SwiftSource.body(of: "makeEngine", in: try code(path)) else {
            return XCTFail("\(path) has no makeEngine — this scan is reading the wrong thing")
        }
        XCTAssertTrue(body.contains("popularity: ports.popularity"),
                      "makeEngine does not hand the engine the install-count store, so the module "
                      + "ranks search with `NoPopularity` and fetches nothing — invisible at "
                      + "runtime, because that is exactly what it used to do")
    }

    func testThePortsFactoryBuildsTheStoreThatReallyFetches() throws {
        let path = "Sources/Modules/Homebrew/Engine/SystemPorts.swift"
        let text = try code(path)
        guard let factory = SwiftSource.typeBodies(in: text).first(where: {
            $0.name == "HomebrewSystemPorts"
        }) else {
            return XCTFail("\(path) has no HomebrewSystemPorts — this scan is reading the wrong thing")
        }
        let body = String(Array(text)[(factory.open + 1)..<factory.close])
        XCTAssertTrue(body.contains("popularity = FilePopularityStore()"),
                      "HomebrewSystemPorts does not build the store that fetches, so what the "
                      + "descriptor hands over answers with no readings for ever")
    }
}
