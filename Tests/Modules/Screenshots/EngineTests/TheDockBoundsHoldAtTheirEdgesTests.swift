import CoreGraphics
import HelmTestSupport
import XCTest

/// The Dock bounds port reads trust with `AXIsProcessTrusted` and never the prompting `…WithOptions` anywhere in the
/// module, logs nothing itself, and its one timeout line is a fixed sentence under the module's category.
final class TheDockBoundsHoldAtTheirEdgesTests: XCTestCase {

    // MARK: - Optional by design: never prompts, never logs the absence

    func testTheRealPortReadsTrustWithoutPromptingAndLogsNothing() throws {
        let path = "Sources/Modules/Screenshots/Engine/SystemPorts.swift"
        let code = SwiftSource.code(try RepoSource.text(of: path))
        guard let start = code.range(of: "struct SystemDockBounds") else {
            return XCTFail("SystemDockBounds is not in \(path)")
        }
        let rest = code[start.upperBound...]
        let end = rest.range(of: "\n}")?.lowerBound ?? rest.endIndex
        let body = rest[..<end]
        // The subject first: the non-prompting trust reading is there and is the guard.
        XCTAssertTrue(body.contains("guard AXIsProcessTrusted() else { return .notTrusted }"),
                      "the trust reading moved; re-read this check")
        XCTAssertFalse(body.contains("HelmLog"), "the Dock bounds port logs")
        XCTAssertFalse(body.contains("print("), "the Dock bounds port prints")
        // The one reading that is logged is logged where the port's answer is placed:
        // under the module's own category, as a fixed sentence that can name nothing.
        // This proves the callback the real path passes is a log.
        // Literals kept here: the subject is the sentence itself.
        let kept = SwiftSource.uncommented(try RepoSource.text(of: path))
        guard let placing = kept.range(of: "func dockPlacement(") else {
            return XCTFail("dockPlacement is not in \(path); re-read this check")
        }
        let after = kept[placing.upperBound...]
        let placingBody = after[..<(after.range(of: "\n    }\n")?.lowerBound ?? after.endIndex)]
        guard let call = placingBody.range(of: "DockStrip.placement(entries:") else {
            return XCTFail("the real path no longer places through DockStrip.placement(entries:)")
        }
        let callback = placingBody[call.upperBound...]
        XCTAssertTrue(callback.contains("HelmLog.shared.warn(ScreenshotsEngine.moduleID, \""),
                      "a Dock that did not answer is not logged under the module's category")
        XCTAssertFalse(callback.contains("\\("), "the timeout line interpolates something")
        for read in try SwiftSource.code(under: "Sources/Modules/Screenshots") {
            XCTAssertFalse(read.text.contains("AXIsProcessTrustedWithOptions"),
                           "\(read.path) calls the prompting trust reading")
        }
    }
}
