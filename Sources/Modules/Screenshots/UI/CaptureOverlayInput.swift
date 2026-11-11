import AppKit
import Module_Screenshots_Engine

extension CaptureOverlay {
    // MARK: - Events, reported by the views

    func mouseMoved(on display: DisplayID, at local: CGPoint) {
        pointer = (display, local)
        if mode == .window { hovered = windowUnder(display: display, local: local) }
        if let entry = panels[display], !entry.panel.isKeyWindow {
            entry.panel.makeKey()
            entry.panel.makeFirstResponder(entry.view)
        }
        render()
    }

    func mouseDown(on display: DisplayID, at local: CGPoint, flags: NSEvent.ModifierFlags) {
        pointer = (display, local)
        pinRefused = false
        // No release is guaranteed: a press that finds a reshape open ends it where it was.
        reshaping = nil
        // A press on the palette is the palette's: never a draft, never a new area. Its background is an
        // input like any other, so it withdraws Esc's question as a button does; and the reshape it ended
        // never having been released, it judges the selection as that release would.
        if chrome(on: display)?.covers(local) == true || panels[display]?.view.emojiGridCovers(local) == true {
            if var current = edit, drag == nil { current.layers.disarm(); current.layers.releaseIfOutside(); edit = current; render() }
            return
        }
        // A press anywhere else ends an open input first, as a click out of a text box does, and then means what it means.
        endTyping()
        // An open pop-over is closed by a press outside the chrome, and that press is no other: it draws nothing and
        // moves nothing, so the person who opened the pop-over by mistake is not left with a stroke.
        if popover != nil {
            popover = nil
            if var current = edit { current.layers.disarm(); edit = current }
            render()
            return
        }
        // The eyedropper takes any press that is not the palette's or an open pop-over's and is over with it: on the area, the pixel
        // under it is the colour; anywhere else nothing is picked.
        if sampling, let current = edit, drag == nil {
            sampling = false
            if display == current.display, current.rect.contains(local),
               let frame = freeze.frames.first(where: { $0.id == display }),
               let loupe = PixelLoupe.around(local, in: frame) { perform(.color(AnnotationInk(loupe))) } else { render() }
            return
        }
        if var current = edit, drag == nil {
            current.layers.disarm()
            // The editor reads the press on the edited display only: a handle of the area reshapes it, where the area offers
            // them (with no layers, or with Crop on; an object's own handle, where the two meet, is taken first), then, with the eraser on, the erase,
            // then the ruler's strip where the area shows it, and then a tool draws, a handle
            // resizes, an object is taken to be moved, and a click selects or lets go. What is
            // left is no tool and no layers, the old gesture, a new drag, which replaces the
            // area only when it turns out to be one (opened on a picture, a press beside it starts none); on another display, with a tool or with
            // layers, a press does nothing. The disarm is the click's own effect, kept either way.
            if display == current.display,
               let handle = AreaFrame.handle(of: current.rect, at: local, yieldingTo: current.layers.selected,
                                             layersExist: !current.layers.layers.isEmpty, cropping: crop != nil) {
                current.layers.end()
                reshaping = (display, handle, current.rect, local)
                edit = current
                render()
                return
            }
            // The eraser takes the press before any tool or selection does, even over a handle of the selected object: only
            // a handle of the area, above, is before it.
            if display == current.display, erasing {
                current.layers.beginErase(at: local, radius: Self.eraserRadius)
                edit = current
                render()
                return
            }
            // The ruler's strip takes the press with any tool, on the part of it the area shows: the strip is drawn above
            // the layers, so what is under it is not what the pointer is over. With the eraser on, above, the strip is not taken: the eraser takes layers and the ruler is none.
            if display == current.display, let strip = ruler, current.rect.contains(local), strip.contains(local) {
                current.layers.end()
                rulerDrag = (display, flags.contains(.option)
                             ? .turn(base: strip.angle, from: strip.degrees(toward: local))
                             : .move(offset: CGPoint(x: strip.center.x - local.x, y: strip.center.y - local.y)))
                edit = current
                render()
                return
            }
            // The text tool on bare picture inside the area starts a field there; on a layer or a handle the press is the
            // editor's own, and selects.
            if display == current.display, current.tool == .text, current.rect.contains(local), !current.layers.takes(at: local),
               panels[display]?.view.beginText(at: local, style: style, within: current.rect) == true {
                current.layers.deselect()
                typing = (display, local)
                edit = current
                render()
                return
            }
            // The Emoji tool on bare picture inside the area puts the picked emoji there, its middle at the press; with none picked the press only
            // lets go of the selection. On a layer or a handle the press is the editor's own, as the text tool's is.
            if display == current.display, current.tool == .emoji, current.rect.contains(local), !current.layers.takes(at: local) {
                if let emoji { current.layers.place(emoji: emoji, at: local, style: style) } else { current.layers.deselect() }
                edit = current
                render()
                return
            }
            if display == current.display,
               current.layers.press(at: local, tool: current.tool, style: style, ruler: ruler) {
                edit = current
                render()
                return
            }
            guard current.tool == nil, !erasing, current.layers.layers.isEmpty else { edit = current; render(); return }
            edit = current
        }
        switch mode {
        case .window:
            // The default is the shadow, as macOS's; an option-click asks for the window alone.
            if let hovered { finish(.window(hovered.id, shadow: !flags.contains(.option))) }
        case .area:
            guard picture == nil || picture?.display == display, let bounds = displayBounds(display) else { return }
            // Opened on a picture, the screen round it is only the ground it stands on: a press there starts no area and draws nothing.
            if let picture, !picture.rect.contains(local) { render(); return }
            // The panel's overlay keeps the area that was drawn until a drag that is usable replaces it (`mouseUp`).
            replacedByDrag = selectionOnly ? (preselected ?? replacedByDrag) : nil
            preselected = nil
            drag = (display, SelectionDrag(start: local, bounds: bounds))
            render()
        }
    }

    func mouseDragged(on display: DisplayID, at local: CGPoint, flags: NSEvent.ModifierFlags) {
        pointer = (display, local)
        if let held = reshaping, var current = edit {
            // A result with nothing to draw is not taken: the area keeps the last one that had.
            if held.display == display, let bounds = displayBounds(display),
               let rect = AreaFrame.resized(held.base, held.handle, from: held.press, to: local, within: bounds) {
                current.rect = rect
                current.layers.reshape(bounds: rect)
                // While Crop is on the strip is kept inside at Return, so that Esc gives it back where it was.
                if crop == nil { ruler?.keep(within: rect) }
                edit = current
            }
            render()
            return
        }
        if let held = rulerDrag, held.display == display, var strip = ruler, let current = edit {
            switch held.kind {
            case .move(let offset): strip.move(to: CGPoint(x: local.x + offset.x, y: local.y + offset.y), within: current.rect)
            case .turn(let base, let from): strip.rotate(to: base + strip.degrees(toward: local) - from)
            }
            ruler = strip
            render()
            return
        }
        if var current = edit, drag == nil {
            current.layers.drag(to: local, shift: flags.contains(.shift))
            edit = current
            render()
            return
        }
        guard var current = drag, current.display == display else { return }
        current.drag.move(to: local, shift: flags.contains(.shift), option: flags.contains(.option),
                          space: spaceHeld)
        drag = current
        render()
    }

    /// A right click leaves, wherever it lands (`rightMouseDown(on:at:)` is the one that asks where). Esc is the documented way out and it depends on the
    /// panel being key; a full-screen overlay with no way out that needs no key
    /// is the one failure here that strands a person.
    func rightMouseDown() { escapeAsked() }

    /// The right click at a point of a display. Opened on a picture, the one beside it is the ground's and does nothing (Esc, ✕ and Done are the
    /// ways out); on the picture, and with no picture anywhere, it is `rightMouseDown()`.
    func rightMouseDown(on display: DisplayID, at local: CGPoint) {
        if let picture, picture.display != display || !picture.rect.contains(local) { return }
        rightMouseDown()
    }

    /// Esc and the right click are one door with one rule (opened on a picture, a right click beside it never gets here), `AnnotationEditing.escape`, and it is asked last. Before it, in this order, each press does
    /// only its own thing and arms nothing: an open text input is ended, the eyedropper is put down, an open pop-over is closed, a held area handle puts the area back as the press
    /// took it, and with Crop on the area goes back as the mode found it (a selected object stays selected). Then the rule: at once with nothing to
    /// lose, and with layers a second press, whenever it comes; a selected object is let go of first, and that press asks nothing. A drag in
    /// progress is not an edit and leaves at once.
    func escapeAsked() {
        pinRefused = false
        // An open input takes this press and nothing else: it places a non-empty text and drops an empty one, and the
        // rule below starts with the next press.
        if typing != nil { endTyping(); return }
        // The eyedropper is put down by this press, which does only that.
        if sampling { sampling = false; render(); return }
        // An open pop-over takes this press and nothing else: Esc's own rule below starts with the next one.
        if popover != nil { popover = nil; render(); return }
        // A reshape under the pointer is cancelled, the area back as the press took it: Esc is the
        // way out of what is being done, and that press does only that.
        if let held = reshaping, var current = edit {
            reshaping = nil
            current.rect = held.base
            current.layers.reshape(bounds: held.base)
            edit = current
            render()
            return
        }
        // Crop on: the area goes back as the mode found it. That press does only that and does not arm the rule below, which
        // starts with the next press.
        if var current = edit, drag == nil, dropCrop(&current) {
            edit = current
            render()
            return
        }
        guard var current = edit, drag == nil else { finish(.cancelled); return }
        let outcome = current.layers.escape()
        edit = current
        switch outcome {
        case .close: finish(.cancelled)
        case .armed, .deselected, .dropped: render()
        }
    }

    func mouseUp(on display: DisplayID) {
        if reshaping != nil {
            // Judged at the release and not along the drag: a drag back brings the object in again, and Esc
            // gives the area back whole, so nothing is let go of that the person has not settled.
            reshaping = nil
            if var current = edit { current.layers.releaseIfOutside(); edit = current }
            render()
            return
        }
        if rulerDrag != nil { rulerDrag = nil; render(); return }
        if var current = edit, drag == nil {
            current.layers.end()
            edit = current
            render()
            return
        }
        guard let current = drag, current.display == display else { return }
        // A click that never moved is not a selection: the drag ends and the
        // overlay waits for a real one — or goes on editing the one it had.
        guard current.drag.isUsable else { drag = nil; preselected = replacedByDrag; replacedByDrag = nil; render(); return }
        replacedByDrag = nil
        if selectionOnly {
            drag = nil
            spaceHeld = false
            preselected = (display, current.drag.rect)
            render()
            return
        }
        startEditing(display: display, rect: current.drag.rect)
    }

    func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        optionHeld = flags.contains(.option)
        render()
        // Shift and option change the selection without the pointer moving, and ⇧
        // reshapes the stroke under the pointer the same way.
        if var current = edit, drag == nil {
            current.layers.modifiersChanged(shift: flags.contains(.shift))
            edit = current
            render()
            return
        }
        guard var current = drag, let pointer, pointer.display == current.display else { return }
        current.drag.move(to: pointer.point, shift: flags.contains(.shift),
                          option: flags.contains(.option), space: false)
        drag = current
        render()
    }

    func keyDown(_ event: NSEvent) {
        // A held Esc repeats, and a repeat is not the second press the question waits for.
        if event.keyCode == ShotKey.escape { if !event.isARepeat { escapeAsked() }; return }
        // The field has the keys while a text is typed: a key it did not take (it hands on what it has no use for) is not the editor's.
        if typing != nil { return }
        if edit != nil, drag == nil { editorKey(event); return }
        switch event.keyCode {
        case ShotKey.returnKey, ShotKey.enter:
            // A held Return repeats, and a repeat is not a press that asked for anything.
            guard !event.isARepeat else { return }
            if selectionOnly { takeTarget(); return }
            // A preselection is only ever held under `selectionOnly`, which `takeTarget`
            // above has already answered, so no caller in Sources reaches this: it would
            // take the remembered selection into the editor, where the next Return takes the picture.
            if drag == nil, mode == .area, let preselected {
                startEditing(display: preselected.display, rect: preselected.rect)
                return
            }
            // Nothing selected: the whole display the pointer is on, as macOS does.
            guard drag == nil, let display = pointer?.display ?? freeze.frames.first?.id else { return }
            finish(.wholeDisplay(display))
        case ShotKey.space:
            guard !event.isARepeat else { return }
            if drag != nil {
                spaceHeld = true
            } else if !selectionOnly {
                mode = mode == .area ? .window : .area
                if mode == .window, let pointer {
                    hovered = windowUnder(display: pointer.display, local: pointer.point)
                } else {
                    hovered = nil
                }
                render()
            }
        default:
            break
        }
    }

    /// A key while an area is being edited, read by its physical code: Space and
    /// every key the editor has no use for only withdraw a question asked by Esc and end a run of arrows.
    private func editorKey(_ event: NSEvent) {
        perform(EditorKeys.action(keyCode: event.keyCode, flags: event.modifierFlags), isRepeat: event.isARepeat)
    }

    func keyUp(_ event: NSEvent) {
        if event.keyCode == ShotKey.space { spaceHeld = false }
    }
}
