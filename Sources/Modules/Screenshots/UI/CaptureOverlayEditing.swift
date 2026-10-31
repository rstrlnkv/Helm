import AppKit
import HelmRuntime
import Module_Screenshots_Engine

extension CaptureOverlay {
    // MARK: - The panel's overlay

    /// What Capture would take now: the window last under the pointer, or the area as drawn (or remembered).
    var hasTarget: Bool { selectionOnly && (mode == .window ? hovered != nil : preselected != nil) }

    /// The panel's Capture and Return: the target leaves as the click or the exit of the editor would have sent it.
    /// False, and nothing sent, where there is none.
    @discardableResult func takeTarget() -> Bool {
        guard hasTarget else { return false }
        if mode == .window, let hovered {
            finish(.window(hovered.id, shadow: true))
        } else if let preselected {
            finish(.edited(display: preselected.display, local: preselected.rect, layers: [], exit: .confirm))
        }
        return true
    }

    /// The panel's mode cell was pressed on an overlay that is already open: the same frozen screen picks again, and what
    /// the other mode had chosen is dropped.
    func select(_ next: Mode) {
        guard selectionOnly, next != mode else { return }
        drag = nil
        replacedByDrag = nil
        hovered = nil
        preselected = nil
        mode = next
    }

    /// The released area becomes the editor's: a new area starts a fresh set of
    /// layers, and the tool picked so far stays picked.
    func startEditing(display: DisplayID, rect: CGRect) {
        drag = nil
        preselected = nil
        spaceHeld = false
        // The first area of a capture opens on what was used last; the next ones keep what was picked since.
        var tool = edit?.tool
        if edit == nil, let store {
            memory = EditorMemory.read(store)
            palette.hide(Set(PaletteItem.allCases).subtracting(PaletteItems.visible(store)))
            tool = memory.tool
            styleTool = tool ?? styleTool
            style = memory.style(for: styleTool)
        }
        edit = (display, rect, AnnotationEditing(bounds: rect), tool)
        crop = nil
        // A strip on the picture goes with the area to the middle of the new one.
        if ruler != nil { ruler = .centred(in: rect) }
        rulerDrag = nil
        render()
    }

    /// The one door of the editor: a key and a click on the palette both come here, so a tool has
    /// one meaning however it was asked for. Nil is an input with no action, which only
    /// withdraws Esc's question and ends a run of arrows (`AnnotationEditing.disarm`).
    func perform(_ action: EditorAction?, isRepeat: Bool = false) {
        // An open input ends first, its text placed, so that the action meets the picture as it is; a colour, a step or
        // an opacity is the field's own pick and restyles it (below), and the text is placed in that style.
        switch action {
        case .color?, .thickness?, .opacity?: break
        default: endTyping()
        }
        guard var current = edit, drag == nil, reshaping == nil else { return }
        if action != .eyedropper { sampling = false }
        pinRefused = false
        if case .nudge? = action {
            // A repeat after the object was let go of is the held key going on, not a new input.
            if isRepeat && arrowReleasedObject { return }
        }
        arrowReleasedObject = false
        // An arrow press moves the selected object, or the area when none is selected, by pixels of
        // this display. It is not routed through the `disarm` below: that is what ends a run of
        // presses, and a run of arrows is one undo step. A held key repeats on purpose.
        if case .nudge(let dx, let dy, let pixels)? = action {
            guard !current.layers.isBusy, let frame = freeze.frames.first(where: { $0.id == current.display }) else { return }
            let delta = AreaFrame.step(CGPoint(x: dx, y: dy), pixels: pixels, scale: frame.scale)
            let hadSelection = current.layers.selected != nil
            if !current.layers.nudgeSelected(by: delta) {
                current.rect = AreaFrame.nudged(current.rect, by: delta, within: displayBounds(current.display) ?? current.rect)
                current.layers.reshape(bounds: current.rect)
                if crop == nil { ruler?.keep(within: current.rect) }
            } else if hadSelection, current.layers.selected == nil {
                arrowReleasedObject = true
            }
            edit = current
            render()
            return
        }
        // Close is Esc's own door and carries Esc's question with it: disarming first would ask again for ever.
        if action == .close { escapeAsked(); return }
        current.layers.disarm()
        defer {
            edit = current
            if let typing { panels[typing.display]?.view.restyleText(style) }
            render()
        }
        switch action {
        case .tool(let tool)?:
            // The same key again puts the tool down, which is how a drag selects again;
            // a held key's repeats are not that second press.
            guard !isRepeat else { return }
            dropCrop(&current)
            // Under the eraser a tool's key picks that tool, even the one chosen under it: the eraser is what puts down.
            current.tool = current.tool == tool && !erasing ? nil : tool
            erasing = false
            popover = nil
            if let store { EditorMemory.remember(tool: current.tool, in: store) }
            // Each tool is drawn with its own colour, step and opacity, and every tool with the one fill.
            if let picked = current.tool { styleTool = picked; style = memory.style(for: picked) }
        case .erase?:
            // The key again puts the eraser down, as a tool's does; the tool chosen under it is as it was, and the store is not asked.
            guard !isRepeat else { return }
            dropCrop(&current)
            erasing.toggle()
            popover = nil
        case .eyedropper?:
            // Only ever on: no key asks for it (`EditorKeys.action`), and the cell's press closes its pop-over, which asking for it
            // again would mean; the mode ends with the pick or with any other input (above).
            popover = nil
            sampling = true
        case .allColours?:
            // The system's colour panel, which stands over the overlay (`EditorColourPanel`); what is picked there is a `.color` like any other.
            popover = nil
            colourPanel.open(showing: style.ink(for: styleTool)) { [weak self] in self?.perform(.color($0)) }
        case .toggleRuler?:
            // A switch: the key again lowers it, and a click on the raised object does. The tool chosen and the eraser stay as they were.
            guard !isRepeat else { return }
            ruler = ruler == nil ? .centred(in: current.rect) : nil
            rulerDrag = nil
            rulerTurn = nil
            popover = nil
        case .crop?:
            // Crop is a mode: it puts the eraser and the chosen tool down (the store is not asked, so the next capture opens on the tool
            // it did), and the pop-over of a tool with them. Choosing it again is Esc's: the area back.
            guard !isRepeat else { return }
            if !dropCrop(&current) {
                crop = current.rect
                current.tool = nil
                erasing = false
                popover = nil
            }
        case .pickEmoji(let picked)?:
            if current.tool == .emoji, EmojiSet.isOne(picked) { emoji = picked }
        case .select?:
            dropCrop(&current)
            current.tool = nil
            erasing = false
            popover = nil
            if let store { EditorMemory.remember(tool: nil, in: store) }
        // A pick is one tool's: the selected object's, else the tool in hand's (below).
        case .color(let color)?:
            if coloursAreOpen { popover = nil }
            // The pick is its owner's: the selected object's tool, else the tool last in hand (which is also what Select with
            // nothing selected, the eraser, the ruler and Crop leave it as). Another tool's pick is not the one in hand's.
            let owner = current.layers.selected?.tool ?? styleTool
            if owner == styleTool { style.color = color }
            current.layers.recolor(color)
            remember(colour: color, for: owner)
        case .thickness(let step)?:
            style.thickness = step
            // With an object selected a thickness pick also re-weights it; the opacity below is the next stroke's alone.
            current.layers.setThickness(step)
            remember()
        case .opacity(let value)?:
            // A value that is no number is full ink, as the reader of the store reads it (`EditorMemory.read`).
            style.opacity = value.clamped(to: 0.1...1, whenNotANumber: 1)
            remember()
        case .thicknessAndOpacity(let anchorX)?:
            // A second request closes it; with no tool chosen, the spotlight, which has no steps, or the eraser on, there is nothing whose steps it could set.
            popover = current.tool != nil && current.tool != .spotlight && !erasing && !thicknessIsOpen ? (.thickness, anchorX) : nil
        case .colours(let anchorX)?:
            // Opened with no tool chosen too: a pick is then the selected object's tool's, or the tool last in hand's. The other pop-over gives way to it.
            popover = coloursAreOpen ? nil : (.colours, anchorX)
        case .toggleFill?:
            // With a box selected the fill is flipped from that box's own state, and the pick follows it.
            if let box = current.layers.selected, box.tool == .rectangle || box.tool == .ellipse {
                style.filled = !box.style.filled
                current.layers.setFilled(style.filled)
            } else {
                style.filled.toggle()
            }
            remember()
        case .copyText?, .blurPersonalText?:
            // One reading at a time; the menu has both items disabled meanwhile, and a second ask that gets here anyway starts nothing.
            guard !isRepeat, reading == nil else { return }
            popover = nil
            beginReading(action == .copyText ? .copy : .blur, display: current.display, rect: current.rect)
        case .delete?: current.layers.deleteSelected()
        case .undo?: current.layers.undo()
        case .redo?: current.layers.redo()
        case .exit(.confirm)? where crop != nil:
            // Return (and Done, which sends the same) takes the crop and leaves the editor open on the new area: the strip is
            // brought inside it, and no step is recorded, as for any reshape of the area.
            guard !isRepeat else { return }
            crop = nil
            ruler?.keep(within: current.rect)
        case .exit(let how)?:
            guard !isRepeat else { return }
            popover = nil
            // No room for a pin: the editor stays, with the picture in it, a pending crop still pending, and says why on the plate
            // (the toast lies below the overlay and could not be seen).
            if how == .pin, !pinRoom() { pinRefused = true; return }
            // An exit that is no Return delivers the area as the screen shows it, a pending crop included.
            crop = nil
            // What the screen shows is what is delivered: a stroke still under the
            // pointer becomes a layer now, and an unusable one is dropped by `end`.
            current.layers.end()
            finish(.edited(display: current.display, local: current.rect, layers: current.layers.layers, exit: how))
        case .nudge?, .close?, nil: break
        }
    }

    /// Crop is put down with the area as the mode found it: true when it was on. Not a step, and the layers are told the bounds as a
    /// reshape tells them.
    @discardableResult
    func dropCrop(_ current: inout (display: DisplayID, rect: CGRect, layers: AnnotationEditing, tool: AnnotationTool?)) -> Bool {
        guard let base = crop else { return false }
        crop = nil
        current.rect = base
        current.layers.reshape(bounds: base)
        return true
    }

    /// Whether Crop is on, for a test and for nobody else.
    var isCropping: Bool { crop != nil }

    /// A turn of the trackpad's rotate gesture, in degrees, counter-clockwise as AppKit reports it, while the ruler is on the picture. Whether the
    /// non-activating panel is sent the gesture at all is not known; the ⌥-drag turns the strip without it.
    func rotateRuler(by degrees: CGFloat, phase: NSEvent.Phase) {
        guard var strip = ruler, edit != nil else { return }
        if phase.contains(.ended) || phase.contains(.cancelled) { rulerTurn = nil; return }
        // A gesture whose end never came leaves its base and sum: a new one starts from the angle the strip has now.
        if phase.contains(.began) || phase.contains(.mayBegin) { rulerTurn = nil }
        let turn = rulerTurn ?? (strip.angle, 0)
        guard degrees.isFinite else { return }
        let sum = turn.sum - degrees
        rulerTurn = (turn.base, sum)
        strip.rotate(to: turn.base + sum)
        ruler = strip
        render()
    }

    /// A reading of the area as the screen shows it (a pending crop's area, the picture without the layers), held by this overlay: the task is
    /// cancelled by `close` and an answer that finds the editor closed, the area changed or another reading begun is dropped.
    private func beginReading(_ ask: TextAsk, display: DisplayID, rect: CGRect) {
        readingsBegun += 1
        let serial = readingsBegun
        let read = textTools.read
        let task = Task { [weak self] in
            let answer = await read(display, rect)
            self?.answered(answer, serial: serial)
        }
        reading = (serial, ask, task, display, rect)
        render()
    }

    private func answered(_ answer: CaptureSession.AreaReading, serial: Int) {
        guard let held = reading, held.serial == serial, !held.task.isCancelled, var current = edit,
              current.display == held.display, current.rect == held.rect else { return }
        reading = nil
        // The answer is the later thing to say: a refused pin's plate gives way to it.
        if case .cancelled = answer {} else { pinRefused = false }
        switch answer {
        case .cancelled: break
        case .failed: textPlate = ScStr.textUnreadable
        case .read(let lines, let source):
            switch held.ask {
            case .copy:
                switch textTools.copy(CopiedText.lines(lines, source: source, notUnder: current.layers.layers)) {
                case .copied: textPlate = ScStr.textCopied
                case .noText: textPlate = ScStr.noTextFound
                // The clipboard said no: the text was read and nobody has it, and the one sentence for a text that did not arrive is this.
                case .refused: textPlate = ScStr.textUnreadable
                }
            case .blur:
                let finds = PersonalFinds.finds(in: lines, source: source, under: current.layers.layers)
                let added = current.layers.insert(blurs: finds)
                edit = current
                textPlate = added == 0 ? ScStr.nothingBlurred : ScStr.blurred(added)
            }
        }
        render()
    }

    /// The input ends: the field goes, and its text is placed where the line began in the style picked now (`AnnotationEditing.place`:
    /// one undo step, and none for an empty or blank text). Return, Esc, a press elsewhere, a palette action but a colour, a step or an opacity, an exit and
    /// the panel losing key all come here; `close` drops the record without placing the text.
    func endTyping() {
        guard let held = typing else { return }
        typing = nil
        let text = panels[held.display]?.view.endText() ?? ""
        guard var current = edit else { return }
        current.layers.place(text: text, at: held.at, style: style)
        edit = current
        render()
    }

    /// What ⋯ asks for: the menu, under the ⋯ circle on the display whose palette is up. `popUp` returns only when the
    /// menu has closed, which the palette's pressed look counts on.
    func openMoreMenu() {
        guard let view = panels.values.first(where: { $0.view.paletteIsShown })?.view else { return }
        openedMenu = moreMenu
        defer { openedMenu = nil }
        view.popUp(moreMenu, below: EditorPalette.moreCircleBottomLeft(palette.moreFrame))
    }

    /// A colour picked for the selected object of another tool than `styleTool` is that tool's: its own colour is written, the other
    /// picks (step, opacity) are what it had, and the fill is the shared one.
    private func remember(colour: AnnotationInk, for owner: AnnotationTool) {
        guard owner != styleTool else { return remember() }
        var picked = memory.style(for: owner)
        picked.color = colour
        picked.filled = style.filled
        memory.note(style: picked, for: owner)
        if let store { EditorMemory.remember(style: picked, for: owner, in: store) }
    }

    /// `style` is the pick of `styleTool`: kept beside the store and written to it.
    private func remember() {
        memory.note(style: style, for: styleTool)
        if let store { EditorMemory.remember(style: style, for: styleTool, in: store) }
    }
}
