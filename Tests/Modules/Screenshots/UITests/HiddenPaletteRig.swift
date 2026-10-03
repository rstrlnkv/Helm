import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// What the files about the palette's hidden objects share: a store that holds a person's picks, an overlay over every
/// real screen built on it with an area released on the first, and the palette measured the way the overlay measures it.
/// No count here is a number: what a file asks of the row it asks of `EditorPalette.rowTools`.
@MainActor
final class HiddenPaletteRig {

    private(set) var overlay: CaptureOverlay?
    private(set) var results: [OverlayResult] = []
    private(set) var display: DisplayID?
    let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    func close() {
        overlay?.close()
        overlay = nil
        results = []
    }

    /// A store whose `paletteChoices` is what a person's picks look like: the items named, hidden. Written to the backing
    /// store directly, so the engine's own write path is not the thing that made the fixture.
    static func store(hiding items: some Collection<PaletteItem>, also foreign: [String] = []) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        var table: [String: Bool] = [:]
        for item in items { table[item.rawValue] = false }
        for name in foreign { table[name] = false }
        if !table.isEmpty { backing.set(table, forKey: "module.screenshots.\(ScreenshotsSettings.Key.paletteChoices)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    /// The overlay over every real screen, the area released on the first display: the moment the palette reads its picks.
    @discardableResult
    func build(store: NamespacedStore?) throws -> (display: DisplayID, view: OverlayView) {
        close()
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let id = try XCTUnwrap(frames.first?.id)
        display = id
        built.mouseDown(on: id, at: area.origin, flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        built.mouseUp(on: id)
        return (id, try XCTUnwrap(built.view(for: id)))
    }

    func key(_ code: Int) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code))!
    }

    func stroke(from: CGPoint = CGPoint(x: 150, y: 150), to: CGPoint = CGPoint(x: 300, y: 250)) {
        guard let display else { return }
        overlay?.mouseDown(on: display, at: from, flags: [])
        overlay?.mouseDragged(on: display, at: to, flags: [])
        overlay?.mouseUp(on: display)
    }

    /// What the editor handed back on Done: the tools of the layers it drew.
    func drawnTools() throws -> [AnnotationTool] {
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(results.count, 1, "the overlay did not finish exactly once: \(results)")
        guard case .edited(_, _, let layers, _)? = results.first else {
            XCTFail("the overlay finished with \(results)")
            return []
        }
        return layers.map(\.tool)
    }

    /// The palette's width, as the overlay asks for it: a hosting view nobody tells how wide to be.
    static func naturalWidth(of model: EditorBarModel) -> CGFloat {
        let host = NSHostingView(rootView: EditorPalette(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        return host.fittingSize.width
    }

    /// Every row object's item, in the row's order, for the tools the palette draws.
    static var rowItems: [PaletteItem] { EditorPalette.rowTools.compactMap(EditorPalette.item(of:)) }
}
