import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A pin's picture is the selection's own bitmap.** A crop keeps its parent's pixels alive, so a pin made
/// from a layerless crop would hold a whole frozen display for as long as it is open. `detached` draws the
/// cut into a bitmap of its own; Copy and Save, which do not ask for it, still get the crop itself.
/// Read by the release of the display's backing store once the freeze is gone and the cut is still held.
///
/// Total failure of the subject prints: a held cut after which the display's pixels are still not released.
final class ThePinHoldsTheSelectionAndNotTheFrozenDisplayTests: XCTestCase {

    private final class Released: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        var value: Bool { lock.withLock { done } }
        func set() { lock.withLock { done = true } }
    }

    private func display(_ released: Released) -> CGImage {
        let size = 2000 * 1200 * 4
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        bytes.initialize(repeating: 0xff, count: size)
        let box = Unmanaged.passRetained(released)
        let provider = CGDataProvider(dataInfo: box.toOpaque(), data: bytes, size: size) { info, data, _ in
            data.deallocate()
            if let info { Unmanaged<Released>.fromOpaque(info).takeRetainedValue().set() }
        }!
        return CGImage(width: 2000, height: 1200, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8000,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// The cut as the session makes it, with the display's backing store released as soon as the freeze goes.
    private func held(detached: Bool, released: Released) async throws -> CGImage {
        let rig = Rig(home: scratchDirectory("shots-pin-detached-\(detached)"))
        var cut: CGImage?
        do {
            let freeze = Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1000, height: 600),
                                                                scale: 2, image: display(released)))], windows: [])
            cut = await rig.session.annotated(freeze, display: DisplayID(1), local: CGRect(x: 10, y: 10, width: 60, height: 30),
                                              layers: [], detached: detached)
        }
        return try XCTUnwrap(cut)
    }

    func testADetachedCutLetsTheDisplayGoAndTheOrdinaryOneHoldsIt() async throws {
        let shared = Released()
        let kept = try await held(detached: false, released: shared)
        XCTAssertFalse(shared.value, "the control: a layerless crop keeps the display's pixels alive")
        withExtendedLifetime(kept) {}

        let own = Released()
        let cut = try await held(detached: true, released: own)
        XCTAssertEqual(cut.width, kept.width)
        XCTAssertEqual(cut.height, kept.height)
        XCTAssertTrue(own.value, "a detached cut still holds the whole display")
        withExtendedLifetime(cut) {}
    }
}
