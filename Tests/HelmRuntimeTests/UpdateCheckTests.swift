import XCTest
@testable import HelmRuntime

final class UpdateCheckTests: XCTestCase {
    private func release(tag: String, assets: [(String, String)] = []) -> Data {
        let assetsJSON = assets.map {
            #"{"name":"\#($0.0)","browser_download_url":"\#($0.1)"}"#
        }.joined(separator: ",")
        return #"{"tag_name":"\#(tag)","html_url":"https://example.com/r","body":"notes","assets":[\#(assetsJSON)]}"#
            .data(using: .utf8)!
    }

    func testNoReleasesReadsAsUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 404, data: Data(), currentVersion: "1.0.0"), .upToDate)
    }

    func testHTTPErrorIsError() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 500, data: Data(), currentVersion: "1.0.0"), .error)
    }

    func testGarbageBodyIsError() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: Data("nope".utf8), currentVersion: "1.0.0"), .error)
    }

    func testSameOrOlderVersionIsUpToDate() {
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v1.0.0"), currentVersion: "1.0.0"), .upToDate)
        XCTAssertEqual(UpdateCheck.evaluate(statusCode: 200, data: release(tag: "v0.9.0"), currentVersion: "1.0.0"), .upToDate)
    }

    func testNewerVersionPicksZipAndDmgAssets() {
        let data = release(tag: "v1.1.0", assets: [
            ("Helm-1.1.0.dmg", "https://example.com/d.dmg"),
            ("Helm-1.1.0.zip", "https://example.com/d.zip"),
        ])
        guard case .available(let r) = UpdateCheck.evaluate(statusCode: 200, data: data, currentVersion: "1.0.0") else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(r.version, "v1.1.0")
        XCTAssertEqual(r.zipURL, "https://example.com/d.zip")
        XCTAssertEqual(r.downloadURL, "https://example.com/d.dmg")   // dmg preferred for manual
        XCTAssertEqual(r.notes, "notes")
    }

    func testNewerVersionWithoutZipFallsBackForManualDownload() {
        let data = release(tag: "v2.0.0", assets: [("Helm.dmg", "https://example.com/only.dmg")])
        guard case .available(let r) = UpdateCheck.evaluate(statusCode: 200, data: data, currentVersion: "1.0.0") else {
            return XCTFail("expected .available")
        }
        XCTAssertNil(r.zipURL)
        XCTAssertEqual(r.downloadURL, "https://example.com/only.dmg")
    }
}
