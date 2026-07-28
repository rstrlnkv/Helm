import XCTest
@testable import HelmRuntime

/// Where an update offer is allowed to point.
///
/// `UpdateService` hands the page URL to `NSWorkspace.open`, which is a scheme
/// handler and not a browser: `file:`, `x-apple-…` or any registered custom
/// scheme is a different action entirely, and the string comes from a network
/// response. The zip is checked by `ReleaseDigest` before anything is run; the
/// page and the manual download had nothing checking them at all.
final class UpdateCheckSchemeTests: XCTestCase {

    private func release(tag: String, page: String, assets: [(String, String)] = []) -> Data {
        let assetsJSON = assets.map {
            #"{"name":"\#($0.0)","browser_download_url":"\#($0.1)"}"#
        }.joined(separator: ",")
        return #"{"tag_name":"\#(tag)","html_url":"\#(page)","body":"n","assets":[\#(assetsJSON)]}"#
            .data(using: .utf8)!
    }

    func testAPageURLThatIsNotHTTPSIsNotAnOffer() {
        for page in ["file:///Applications/Calculator.app", "javascript:alert(1)",
                     "http://example.com/r", "x-helm://install", "not a url at all"] {
            XCTAssertEqual(
                UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v9.0.0", page: page),
                                     currentVersion: "1.0.0"),
                .error, page)
        }
    }

    /// The positive control: the rule has to still let a real release through,
    /// or every assertion above is satisfied by refusing everything.
    func testAnHTTPSPageURLIsStillAnOffer() {
        guard case .available(let release) = UpdateCheck.evaluate(
            statusCode: 200,
            data: release(tag: "v9.0.0", page: "https://github.com/x/y/releases/tag/v9.0.0"),
            currentVersion: "1.0.0")
        else { return XCTFail("a plain https release stopped being an offer") }
        XCTAssertEqual(release.pageURL, "https://github.com/x/y/releases/tag/v9.0.0")
    }

    /// The list response the dev channel reads goes through the same door.
    func testTheListEndpointIsHeldToTheSameRule() {
        let list = "[" + String(data: release(tag: "v9.0.0", page: "file:///tmp/x"), encoding: .utf8)! + "]"
        XCTAssertEqual(
            UpdateCheck.evaluateList(statusCode: 200, data: Data(list.utf8),
                                     currentVersion: "1.0.0", channel: .dev),
            .error)
    }

    /// An asset URL is opened the same way the page is — the dmg through a
    /// `Link`, the zip by the updater before its digest is checked.
    func testAnAssetThatIsNotHTTPSIsDropped() {
        let data = release(tag: "v9.0.0", page: "https://example.com/r", assets: [
            ("Helm.zip", "file:///tmp/evil.zip"),
            ("Helm.dmg", "http://example.com/d.dmg"),
        ])
        guard case .available(let release) = UpdateCheck.evaluate(
            statusCode: 200, data: data, currentVersion: "1.0.0")
        else { return XCTFail("expected .available") }
        XCTAssertNil(release.zipURL)
        XCTAssertNil(release.downloadURL)
    }
}
