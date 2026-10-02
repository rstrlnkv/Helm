import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// Every action a press at each x along the palette's middle sends, with the x it was sent at.
@MainActor func actionsAcrossThePalette(language: AppLanguage, canUndoAndRedo: Bool = false) throws -> [(x: CGFloat, action: EditorAction)] {
    AppLanguage.override = language
    let model = EditorBarModel()
    model.show(tool: nil, style: .standard, canUndo: canUndoAndRedo, canRedo: canUndoAndRedo)
    var sent: [(x: CGFloat, action: EditorAction)] = []
    var at: CGFloat = 0
    model.perform = { sent.append((at, $0)) }
    let probe = NSHostingView(rootView: EditorPalette(model: model))
    probe.sizingOptions = [.intrinsicContentSize]
    let size = probe.fittingSize
    let mount = MountedRender(EditorPalette(model: model), width: size.width, height: size.height, appearance: .aqua)
    mount.settle(20)
    let window = try XCTUnwrap(mount.window)
    // SwiftUI takes a press only in a window that is ordered in: invisible, and far off every screen.
    window.alphaValue = 0
    window.ignoresMouseEvents = false
    window.setFrameOrigin(CGPoint(x: -30_000, y: -30_000))
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    window.layoutIfNeeded()
    // Undo and Redo are drawn off while there is nothing to undo, so they send nothing: not a finding.
    for x in stride(from: CGFloat(1), to: size.width, by: 2) {
        at = x
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: size.height / 2),
                                                         modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }
    return sent
}
