import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// One press's outcome: an action sent through the model's door, or ⋯ asking to open its menu.
enum PaletteAnswer: Equatable {
    case action(EditorAction)
    /// `EditorBarModel.openMenu` was called; `pressedWhileOpen` is `model.morePressed` read inside that call.
    case more(pressedWhileOpen: Bool)
}

/// Every action a press at each x along the palette's middle sends, with the x it was sent at.
@MainActor func actionsAcrossThePalette(language: AppLanguage, canUndoAndRedo: Bool = false) throws -> [(x: CGFloat, action: EditorAction)] {
    try answersAcrossThePalette(language: language, canUndoAndRedo: canUndoAndRedo).answers.compactMap {
        if case .action(let action) = $0.answer { ($0.x, action) } else { nil }
    }
}

/// Every answer (an action, or ⋯ asking for its menu) to a press at each `step`-th x along the palette's middle,
/// with the x it was sent at. Also reports what `model.morePressed` read once the sweep ended (`morePressedAfter`).
@MainActor func answersAcrossThePalette(language: AppLanguage, canUndoAndRedo: Bool = false, step: CGFloat = 2,
                                        tool: AnnotationTool? = nil) throws -> (answers: [(x: CGFloat, answer: PaletteAnswer)], morePressedAfter: Bool) {
    AppLanguage.override = language
    let model = EditorBarModel()
    model.show(tool: tool, style: .standard, canUndo: canUndoAndRedo, canRedo: canUndoAndRedo)
    var sent: [(x: CGFloat, answer: PaletteAnswer)] = []
    var at: CGFloat = 0
    model.perform = { sent.append((at, .action($0))) }
    model.openMenu = { sent.append((at, .more(pressedWhileOpen: model.morePressed))) }
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
    for x in stride(from: step / 2, to: size.width, by: step) {
        at = x
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: size.height / 2),
                                                         modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                         context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }
    return (sent, model.morePressed)
}
