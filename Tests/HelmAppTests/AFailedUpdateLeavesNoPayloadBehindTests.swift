import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **A refused update leaves no unzipped payload in the temporary directory, and every failure
/// path of the check logs a line.** `installZip` unzips into `HelmUpdate-*`, and a throw before the
/// swap script (a version that is not the one expected) would leave the whole bundle there; a
/// failed check or a non-HTTP answer must still leave a line in the log.
@MainActor
final class AFailedUpdateLeavesNoPayloadBehindTests: XCTestCase {

    private func payloads() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []
        return Set(names.filter { $0.hasPrefix("HelmUpdate-") })
    }

    private func zip(declaring version: String) throws -> URL {
        let dir = scratchDirectory("helm-update-zip")
        let contents = dir.appendingPathComponent("Helm.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try (["CFBundleShortVersionString": version, "CFBundleIdentifier": "com.helm.app"] as NSDictionary)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let out = dir.appendingPathComponent("Helm.zip")
        let r = HelmProcess.run("/usr/bin/ditto", ["-c", "-k", "--keepParent",
                                                   dir.appendingPathComponent("Helm.app").path, out.path])
        XCTAssertEqual(r.status, 0, "precondition: the scratch zip was made")
        return out
    }

    private func listeningLog() -> HelmLog {
        let log = HelmLog.shared
        log.setEnabled(true)
        addTeardownBlock { log.setEnabled(false); log.clearTail() }
        log.clearTail()
        return log
    }

    private func service(feed: @escaping UpdateService.Feed) -> UpdateService {
        UpdateService(notices: FakeAutomationNotice(),
                      store: AppSettings.store.over(InMemoryKeyValueStore()),
                      feed: feed,
                      channelBacking: InMemoryKeyValueStore())
    }

    func testARefusedBundleLeavesNothingBehind() async throws {
        let zip = try zip(declaring: "1.0.0")
        let before = payloads()
        do {
            try await Installer.installZip(at: zip, expectedVersion: "9.9.9")
            XCTFail("a bundle of another version was accepted")
        } catch Installer.InstallError.versionMismatch {
        }
        XCTAssertEqual(payloads(), before, "the refused payload is still in the temporary directory")
    }

    func testAFailedCheckSaysSo() async {
        let log = listeningLog()
        let s = service { _ in throw URLError(.notConnectedToInternet) }
        s.checkNow()
        await waitUntil("the failure is logged") {
            log.recentEntries().contains { $0.message.contains("check failed") }
        }
    }

    func testAnAnswerThatIsNotHTTPSaysSo() async {
        let log = listeningLog()
        let s = service { req in
            (Data(), URLResponse(url: req.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
        s.checkNow()
        await waitUntil("the refusal is logged") {
            log.recentEntries().contains { $0.message.contains("no HTTP answer") }
        }
    }
}
