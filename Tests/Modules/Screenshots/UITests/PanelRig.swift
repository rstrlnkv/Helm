import AppKit
import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// What the capture panel's test families share: a controller over fake ports whose freezes can be counted and
/// held call by call, and a disk that counts what it was given.
/// The overlay is **built and not ordered in** (`CaptureOverlay.build`), the bar seam puts nothing on a screen unless
/// a test asks for the real one.
@MainActor
enum PanelRig {

    typealias Disk = FakeWorkDisk
    @MainActor final class Held { var overlay: CaptureOverlay?; var overlays = 0; var bars = 0 }

    struct Rig {
        let controller: CaptureController
        let screen: FakeScreen
        let disk: Disk
        let held: Held
        let display: DisplayID
    }

    /// A rig whose controller is cancelled when `test` ends. Every real screen, 1000 x 800 points at scale 1, each with a UUID; the first holds a window at (100,100,300,200).
    static func rig(in test: XCTestCase, timer: CaptureTimer = .none, presentBar: @escaping (CapturePanel) -> Void = { _ in },
                    tick: @escaping @Sendable (Duration) async throws -> Void = { _ in }) throws -> Rig {
        let shown = try OverlayRig.frames(scale: 1)
        let base = shown.enumerated().map { index, frame in
            FrozenDisplay(id: frame.id, frame: frame.frame, scale: 1, image: frame.image, uuid: "UUID-\(index)")
        }
        let window = FrozenWindow(id: 7, frame: CGRect(x: 100, y: 100, width: 300, height: 200),
                                  layer: WindowPick.lowestLevel, ownerName: "Notes")
        let screen = FakeScreen(outcome: .frozen(Freeze(displays: base.map { .image($0) }, windows: [window])))
        let disk = Disk(), held = Held()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        let home = test.scratchDirectory("shots-panel")
        let session = CaptureSession(capture: screen, writer: disk, trash: AsideTrash.refusing(), pasteboard: CountingBoard(groups: true), preferences: NoPreferences(),
                                     shutter: CountingShutter(), textReader: NoTextReader(), settings: { ScreenshotsSettings.read(store) },
                                     naming: { .english }, locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(store: store, session: session,
                                           presentOverlay: { overlay in held.overlays += 1; held.overlay = overlay; return overlay.build() },
                                           presentBar: { bar in held.bars += 1; presentBar(bar) }, tick: tick)
        let rig = Rig(controller: controller, screen: screen, disk: disk, held: held, display: try XCTUnwrap(base.first?.id))
        test.addTeardownBlock { @MainActor in rig.controller.cancel() }
        return rig
    }

    static let area = CGRect(x: 50, y: 60, width: 400, height: 300)
}
