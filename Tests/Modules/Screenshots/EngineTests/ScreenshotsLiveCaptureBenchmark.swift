import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **The real ScreenCaptureKit port, against the Mac running the suite.** Silent
/// without `HELM_BENCH=1`, because it needs the grant for the process at the top
/// of the launch chain and reads whatever is on the screen. It keeps everything
/// in memory and in a scratch folder: the picture is never written anywhere
/// else, and nothing is put on the clipboard.
///
/// What it is for is the figures the fakes cannot give: how long a freeze takes,
/// whether a display comes back at the size the frame says it is, and whether the
/// window list holds windows at all. (Its order — front to back — is
/// `CGWindowListCopyWindowInfo`'s documented behaviour and is not checked here.) With the
/// variable set and **no grant it fails** rather than skipping — a benchmark that
/// quietly skips is the one that stops being run.
final class ScreenshotsLiveCaptureBenchmark: XCTestCase {

    private func live() throws -> SCKCapture {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let capture = SCKCapture(store: NamespacedStoreForTests.make())
        XCTAssertEqual(capture.access(), .granted,
                       "HELM_BENCH is set and this process cannot read the screen — grant Screen & System Audio Recording to the process at the top of the launch chain")
        return capture
    }

    func testAFreezeCostAndShape() async throws {
        let capture = try live()
        // The first call of the process is timed on its own: it loads the framework,
        // and it is the one the first press after a launch pays.
        let coldStart = DispatchTime.now()
        let cold = await capture.freeze()
        let coldMs = Double(DispatchTime.now().uptimeNanoseconds - coldStart.uptimeNanoseconds) / 1e6
        guard case .frozen = cold else { return XCTFail("the first freeze came back \(cold)") }
        print(String(format: "freeze, first call of the process (ms): %.0f", coldMs))
        var times: [Double] = []
        var last: Freeze?
        for _ in 0..<5 {
            let start = DispatchTime.now()
            let outcome = await capture.freeze()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6)
            guard case .frozen(let freeze) = outcome else { return XCTFail("the freeze came back \(outcome)") }
            last = freeze
        }
        let freeze = try XCTUnwrap(last)
        print("freeze (ms): " + times.map { String(format: "%.0f", $0) }.joined(separator: ", ")
              + " — \(freeze.frames.count) display(s), \(freeze.windows.count) window(s)")

        XCTAssertFalse(freeze.frames.isEmpty, "no display came back")
        XCTAssertEqual(freeze.displays.count, freeze.frames.count, "a display was listed and could not be captured")
        for frame in freeze.frames {
            XCTAssertEqual(CGFloat(frame.image.width), frame.frame.width * frame.scale, accuracy: 1,
                           "the picture is not the display's size in pixels")
            XCTAssertEqual(CGFloat(frame.image.height), frame.frame.height * frame.scale, accuracy: 1)
        }
        XCTAssertFalse(freeze.windows.isEmpty, "the window list is empty, so nothing about it is shown")
        XCTAssertTrue(freeze.windows.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
    }

    func testAWindowComesBackAtItsOwnSize() async throws {
        let capture = try live()
        guard case .frozen(let freeze) = await capture.freeze() else { return XCTFail("no freeze") }
        let candidates = freeze.windows.filter { $0.layer == 0 && $0.frame.width > 100 && $0.frame.height > 100 }
        let window = try XCTUnwrap(candidates.first, "no ordinary window on screen to ask for")
        let start = DispatchTime.now()
        let shot = await capture.window(window.id)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
        guard case .image(let image) = shot else { return XCTFail("the window came back \(shot)") }
        let scale = freeze.frames.first?.scale ?? 2
        print(String(format: "window %ux%u pt asked for, %dx%d px came back in %.0f ms (scale %.0f)",
                     UInt32(window.frame.width), UInt32(window.frame.height), image.width, image.height, ms, scale))
        XCTAssertEqual(CGFloat(image.width), window.frame.width * scale, accuracy: 2, "the window's picture is not its frame")
        XCTAssertEqual(CGFloat(image.height), window.frame.height * scale, accuracy: 2)
    }

    func testAWholeScreenCaptureWritesAPNGOfTheRightSizeIntoScratch() async throws {
        let capture = try live()
        let home = scratchDirectory("shots-live")
        let writer = FileShotWriter(), board = FakePasteboard(), prefs = FakePreferences()
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let session = CaptureSession(capture: capture, writer: writer, pasteboard: board, preferences: prefs,
                                     settings: { .defaults }, naming: { .english },
                                     locations: ScreenshotsLocations(home: home, desktop: desktop))
        let start = DispatchTime.now()
        let delivery = await session.captureScreens()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
        XCTAssertEqual(delivery.refusals, [])
        XCTAssertFalse(delivery.files.isEmpty, "nothing was written")
        print(String(format: "captureScreens (freeze + encode + write): %.0f ms, %d file(s)", ms, delivery.files.count))
        for file in delivery.files {
            XCTAssertTrue(file.path.hasPrefix(desktop.path), "a picture was written outside the scratch Desktop: \(file.path)")
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertGreaterThan(properties[kCGImagePropertyPixelWidth] as? Int ?? 0, 0)
        }
        XCTAssertEqual(board.copies.count, 0)
    }
}

/// A store over memory, so the live port's "asked once" record never touches the
/// defaults of the account the suite runs as.
enum NamespacedStoreForTests {
    static func make() -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
    }
}
