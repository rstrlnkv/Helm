import AppKit
import CoreGraphics
import HelmTestSupport
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Module_Screenshots_UI

/// The clock of a toast under test: **every step the toast's lifetime waits for is held here until the test lets it
/// go**, so no test sleeps and none races the countdown. `fire()` lets exactly the step the toast is waiting in pass
/// and `step()` also waits for the toast to ask for the next, which is how the loop's own re-checks are reached.
@MainActor
final class StepClock {
    private var pending: [CheckedContinuation<Void, Error>] = []
    /// Every wait the toast asked for, in order.
    private(set) var asked: [Duration] = []

    func tick(_ duration: Duration) async throws {
        asked.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending.append($0) }
        } onCancel: {
            Task { @MainActor in self.finish() }
        }
    }

    var isWaiting: Bool { !pending.isEmpty }

    /// Lets the waiting step pass; false when nothing was waiting.
    @discardableResult func fire() -> Bool {
        guard !pending.isEmpty else { return false }
        pending.removeFirst().resume()
        return true
    }

    /// One step, and waits until the toast asks for the one after it (a toast that ended asks for its fade).
    func step(_ test: XCTestCase, file: StaticString = #filePath, line: UInt = #line) async {
        // The toast's task starts on the next turn: it is waited for before it is let go.
        await test.waitUntil("the toast waited in a step", file: file, line: line) { isWaiting }
        let before = asked.count
        XCTAssertTrue(fire(), "the toast was not waiting in a step", file: file, line: line)
        await test.waitUntil("the toast asked for the step after", file: file, line: line) { asked.count > before }
    }

    /// Ends every wait that is still held, as a cancelled sleep does.
    func finish() {
        let held = pending
        pending = []
        for continuation in held { continuation.resume(throwing: CancellationError()) }
    }
}

/// A view on a window that was never ordered in, which stands where the thumbnail's view stands. The window is held
/// here: a view does not keep its window alive.
@MainActor
final class StandInThumbnail {
    let window: NSWindow
    let view: NSView

    init(at origin: CGPoint = .zero) {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 100, height: 60)), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
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

    /// A real PNG on disk of the default picture, so the path means a file that is there.
    static func realFile(_ test: XCTestCase, _ name: String = "shot.png") throws -> URL {
        try writePNG(try picture(), in: test.scratchDirectory("toast-file"), named: name)
    }

    /// The toast's view mounted on a window that was never ordered in, as a person sees it with the pointer `hovering`.
    static func mount(_ content: ShotToastModel.Content, hovering: Bool = true, width: CGFloat = ShotToast.width,
                      height: CGFloat = 300) -> (model: ShotToastModel, mount: MountedRender) {
        let model = ShotToastModel()
        model.content = content
        model.shown = true
        model.hovering = hovering
        let mount = MountedRender(ShotToastView(model: model), width: width, height: height, appearance: .aqua)
        mount.settle(20)
        return (model, mount)
    }

    /// The controls a rendered toast holds, counted off the tree, where a control drawn by SwiftUI is a focus-ring
    /// view. The capsule, and the ✕ in it, come up with the pointer over the picture.
    static func controls(_ content: ShotToastModel.Content, hovering: Bool = true) -> Int {
        mount(content, hovering: hovering).mount.host.everyView(named: "_FocusRingView").count
    }

    /// A toast with no panel, over a clock the test holds.
    static func toast(_ clock: StepClock) -> ShotToast {
        ShotToast(tick: { try await clock.tick($0) }, windowed: false)
    }
}
