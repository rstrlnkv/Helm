import AppKit
import Module_Screenshots_Engine

extension CaptureOverlay {
    // MARK: - Reading and drawing

    func windowUnder(display: DisplayID, local: CGPoint) -> FrozenWindow? {
        guard let frame = freeze.frames.first(where: { $0.id == display }) else { return nil }
        return WindowPick.window(at: ScreenSpace.global(CGRect(origin: local, size: .zero), in: frame.frame).origin,
                                 in: freeze.windows)
    }

    func local(_ mouse: NSPoint, in panel: NSPanel, frame height: CGFloat) -> CGPoint {
        CGPoint(x: mouse.x - panel.frame.minX, y: height - (mouse.y - panel.frame.minY))
    }

    /// What an area on `display` stays inside: the display, or the picture the overlay was opened on.
    func displayBounds(_ display: DisplayID) -> CGRect? {
        if let picture, picture.display == display { return picture.rect }
        return freeze.frames.first { $0.id == display }.map { CGRect(origin: .zero, size: $0.frame.size) }
    }

    /// Where the palette stands on `display`, under the area (under the base area while Crop is on): nil when it is not the edited one, and nil while an
    /// object is being drawn, moved or resized — a palette under the pointer would be drawn into — or
    /// the area is being reshaped or a new one dragged. It is back on the release, and on the
    /// Esc that drops a drawing or cancels a move, a resize or a reshape.
    func chrome(on display: DisplayID) -> EditorChrome? {
        guard let edit, drag == nil, reshaping == nil, !edit.layers.isBusy, edit.display == display,
              let view = panels[display]?.view else { return nil }
        let screen = view.frozen.frame.size
        // With Crop on the palette stands under the area as the mode found it, so it never covers the strip a handle is
        // dragged back into; after Return it stands under the new one.
        let area = crop ?? edit.rect
        let bare = EditorChrome.place(selection: area, in: screen, palette: view.paletteSize)
        guard let open = popover else { return bare }
        // The pop-over's cell is in the palette's own points; the palette does not move for it.
        return EditorChrome.place(selection: area, in: screen, palette: view.paletteSize,
                                  popover: open.kind == .colours ? view.coloursSize : view.popoverSize,
                                  anchorX: bare.palette.minX + open.anchorX)
    }

    func render() {
        // The area moved or was replaced under a reading: its boxes were for the old one.
        if let held = reading, edit?.display != held.display || edit?.rect != held.rect {
            held.task.cancel()
            reading = nil
        }
        if let edit {
            let held = edit.layers.selected
            emojiGrid.show(chosen: emoji)
            palette.show(tool: edit.tool, erasing: erasing, ruler: ruler != nil, cropping: crop != nil, style: held?.style ?? style, picked: style, memory: memory, selectedTool: held?.tool,
                      popoverOpen: thicknessIsOpen, coloursOpen: coloursAreOpen, canUndo: edit.layers.canUndo, canRedo: edit.layers.canRedo,
                      reading: reading != nil)
        }
        for (id, entry) in panels {
            var scene = OverlayScene()
            scene.windowMode = mode == .window
            scene.linesAcross = optionHeld
            if let pointer, pointer.display == id, edit == nil || drag != nil { scene.pointer = pointer.point }
            scene.sampling = sampling
            if let drag, drag.display == id {
                // A press that has not moved is not a new area yet: the area being edited is still the selection.
                let old = edit.flatMap { $0.display == id ? $0.rect : nil }
                scene.selection = drag.drag.hasMoved ? drag.drag.rect : old ?? drag.drag.rect
                scene.dimsWhenEmpty = drag.drag.hasMoved
            }
            else if let edit, edit.display == id {
                scene.selection = edit.rect
                if let picture, picture.display == id { scene.card = picture.rect }
                scene.editing = drag == nil
                if let reshaping, reshaping.display == id, let pointer, pointer.display == id {
                    scene.loupeAt = pointer.point
                }
                scene.chrome = chrome(on: id)
                scene.layers = edit.layers.layers + (edit.layers.draft.map { [$0] } ?? [])
                scene.draftID = edit.layers.draft?.id
                scene.erasing = erasing
                if sampling, let pointer, pointer.display == id, edit.rect.contains(pointer.point),
                   scene.chrome?.covers(pointer.point) != true { scene.loupeAt = pointer.point }
                scene.emojiGrid = edit.tool == .emoji && !erasing && crop == nil
                scene.handlesOffered = AreaFrame.offersHandles(layersExist: !edit.layers.layers.isEmpty, cropping: crop != nil)
                scene.ruler = ruler
                scene.fading = edit.layers.erased
                scene.selected = edit.layers.draft == nil ? edit.layers.selected : nil
                if pinRefused {
                    // By the palette, which the menu was opened from, so that the plate does not lie under the glass.
                    scene.plate = ScStr.pinLimit
                    scene.plateByActions = true
                } else if edit.layers.isArmed {
                    scene.plate = ScStr.confirmClose
                    if let pointer, pointer.display == id { scene.plateAt = pointer.point }
                } else if let textPlate {
                    scene.plate = textPlate
                    scene.plateByActions = true
                }
            } else if mode == .area, let preselected, preselected.display == id { scene.selection = preselected.rect }
            if mode == .window, let hovered { scene.highlight = windowPart(hovered, on: id) }
            entry.view.apply(scene)
        }
        if hasTarget != reportedTarget { reportedTarget = hasTarget; targetChanged(reportedTarget) }
    }

    /// The part of `window` that lies on `display`, in that display's top-left points; nil where it has none.
    func windowPart(_ window: FrozenWindow, on display: DisplayID) -> CGRect? {
        guard let frame = freeze.frames.first(where: { $0.id == display }) else { return nil }
        let part = ScreenSpace.local(window.frame, in: frame.frame)
            .intersection(CGRect(origin: .zero, size: frame.frame.size))
        return !part.isNull && part.width > 0 && part.height > 0 ? part : nil
    }
}

/// Everything one panel draws, decided by the overlay.
struct OverlayScene {
    var windowMode = false
    var pointer: CGPoint?
    var selection: CGRect?
    var highlight: CGRect?
    /// The area is being edited: no lines across the screen; the size plate over the area's top-left corner all the
    /// while, Crop's included (`LabelLayer.cornerPlace`), and the loupe only while an area handle is held or the eyedropper is on (`loupeAt`).
    var editing = false
    /// Layers over the selection, the one being drawn last.
    var layers: [Annotation] = []
    /// Which of `layers` is still being drawn, if one is.
    var draftID: Annotation.ID?
    /// The eraser is on: the cursor is its circle.
    var erasing = false
    /// The Emoji tool is chosen: its grid stands by the palette, where the palette is shown.
    var emojiGrid = false
    /// The eyedropper is on: the cursor is its symbol on every display, the loupe only over the area (`loupeAt`).
    var sampling = false
    /// The area's handles are drawn: no layer on the picture, or Crop on (`AreaFrame.offersHandles`).
    var handlesOffered = true
    /// The layers the eraser's drag has met: drawn at `OverlayView.fadedOpacity` until the release takes them.
    var fading: Set<Annotation.ID> = []
    /// The ruler on the picture: drawn above the layers, clipped to the selection, and in no file.
    var ruler: Ruler?
    /// The selected layer, held by its handles; nil while one is being drawn.
    var selected: Annotation?
    /// Where the palette stands; nil is none on this display, or none while drawing, moving, resizing, reshaping or erasing.
    var chrome: EditorChrome?
    /// What the plate says: the refused pin, Esc's question while it waits for its second press, or a finished reading's answer.
    var plate: String?
    /// Where the pointer is while the plate is up, in display-top-left points; the
    /// crosshair stays off while editing, so this is not `pointer`.
    var plateAt: CGPoint?
    /// The plate is the Pin refusal or a reading's answer: it stands over the palette, or under it with no room above (`plateByActions`).
    var plateByActions = false
    /// The area is being reshaped, or the eyedropper is on over the area, and the pointer is here, in display-top-left points: the loupe reads the pixel under it.
    var loupeAt: CGPoint?
    /// ⌥ is held: the lines run across the screen through the pointer.
    var linesAcross = false
    /// The selection is dimmed around even with no width and no height: a drag that has moved and come back to its press.
    var dimsWhenEmpty = false
    /// The picture the editor was opened on, in display-top-left points: it stands as a card on the dimmed screen, with a shadow round it.
    var card: CGRect?
}
