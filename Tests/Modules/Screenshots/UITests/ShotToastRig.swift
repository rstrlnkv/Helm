import AppKit
import CoreGraphics
import HelmTestSupport
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Module_Screenshots_UI

/// The clock of a toast under test: **every step the toast's lifetime waits for is held here until `finish()` ends
/// it**, so no test sleeps and none races the countdown.
@MainActor
final class StepClock {
    private var pending: [CheckedContinuation<Void, Error>] = []

    func tick(_: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending.append($0) }
        } onCancel: {
            Task { @MainActor in self.finish() }
        }
    }

    /// Ends every wait that is still held, as a cancelled sleep does.
    func finish() {
        let held = pending
        pending = []
        for continuation in held { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
enum ShotToastRig {
    static func picture(width: Int = 520, height: Int = 300) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// A real PNG on disk, so that what reads a file back has one to read.
    static func writePNG(_ image: CGImage, in folder: URL, named name: String = "shot.png") throws -> URL {
        let url = folder.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// The toast's view mounted on a window that was never ordered in, with the pointer over it.
    static func mount(_ content: ShotToastModel.Content) -> (model: ShotToastModel, mount: MountedRender) {
        let model = ShotToastModel()
        model.content = content
        model.shown = true
        model.hovering = true
        let mount = MountedRender(ShotToastView(model: model), width: ShotToast.width, height: 300, appearance: .aqua)
        mount.settle(20)
        return (model, mount)
    }

    /// A toast with no panel, over a clock the test holds.
    static func toast(_ clock: StepClock) -> ShotToast {
        ShotToast(tick: { try await clock.tick($0) }, windowed: false)
    }
}
