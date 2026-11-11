import AppKit
import QuartzCore
import HelmUI
import Module_Screenshots_Engine

extension OverlayView {
    // MARK: Drawing

    func apply(_ scene: OverlayScene) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        windowMode = scene.windowMode
        if erasing != scene.erasing || sampling != scene.sampling {
            erasing = scene.erasing
            sampling = scene.sampling
            setCursor()
        }
        // The dim goes on with the first point a drag has moved over and stays until the shot or Esc, so a selection with
        // any size dims, and an empty one only when its drag has moved (`dimsWhenEmpty`); never over a window pick.
        if let selection = scene.selection, !scene.windowMode,
           selection.width > 0 || selection.height > 0 || scene.dimsWhenEmpty {
            let dim = CGMutablePath()
            dim.addRect(bounds)
            dim.addRect(layerRect(selection))
            dimLayer.path = dim
        } else {
            dimLayer.path = nil
        }

        if let card = scene.card {
            let rect = layerRect(card)
            cardLayer.path = CGPath(rect: rect, transform: nil)
            let outside = CGMutablePath()
            outside.addRect(bounds)
            outside.addRect(rect)
            cardMask.path = outside
        } else {
            cardLayer.path = nil
            cardMask.path = nil
        }

        let highlight = scene.highlight.map { WindowShape.path(for: layerRect($0)) }
        highlightEdgeLayer.path = highlight
        highlightLayer.path = highlight
        selectionLayer.path = scene.selection.map { CGPath(rect: layerRect($0), transform: nil) }

        drawLayers(scene)
        rulerLayer.frame = bounds
        rulerLayer.show(scene.editing ? scene.ruler : nil, in: scene.selection ?? .zero, height: bounds.height, scale: frozen.scale)
        drawAreaHandles(scene.editing && scene.handlesOffered ? scene.selection : nil)
        if let chrome = scene.chrome {
            _ = measuredPalette
            paletteHost.frame = layerRect(chrome.palette)
            paletteHost.isHidden = false
            let colours = overlay?.coloursAreOpen == true
            if let popover = chrome.popover {
                let host: NSView = colours ? coloursHost : popoverHost
                host.frame = layerRect(popover)
                host.isHidden = false
                if colours, popoverMade { popoverHost.isHidden = true }
                if !colours, coloursMade { coloursHost.isHidden = true }
            } else {
                if popoverMade { popoverHost.isHidden = true }
                if coloursMade { coloursHost.isHidden = true }
            }
        } else if paletteMade {
            paletteHost.isHidden = true
            if popoverMade { popoverHost.isHidden = true }
            if coloursMade { coloursHost.isHidden = true }
        }

        // The loupe, only while a handle is held or the eyedropper is on over the area: the pixels of the frame without the pointer, round the pointer.
        if let held = scene.loupeAt, let reading = PixelLoupe.around(held, in: frozen) {
            loupeLayer.show(reading, at: CGPoint(x: held.x, y: bounds.height - held.y), within: bounds)
        } else {
            loupeLayer.isHidden = true
        }
        placeEmojiGrid(scene)

        let at = scene.pointer.map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
        if let at, !scene.windowMode, scene.linesAcross {
            let lines = CGMutablePath()
            lines.move(to: CGPoint(x: 0, y: at.y)); lines.addLine(to: CGPoint(x: bounds.width, y: at.y))
            lines.move(to: CGPoint(x: at.x, y: 0)); lines.addLine(to: CGPoint(x: at.x, y: bounds.height))
            crosshairLayer.path = lines
            crosshairEdgeLayer.path = lines
        } else {
            crosshairLayer.path = nil
            crosshairEdgeLayer.path = nil
        }

        // **One plate by the pointer while selecting.** Before a drag it says where the pointer
        // is; while one is open it says how large the selection is, in the same
        // place — the size *replaces* the coordinates, as macOS's own ⌘⇧4 does.
        // Two plates at the pointer's offset lay one over the other. Once the area is edited the plate
        // stands over its corner instead.
        if !scene.editing { cornerLabel.isHidden = true }
        if scene.editing {
            // Editing has no lines across the screen and no plate by the pointer but the Esc question and, while a
            // handle is held, the loupe's; the area's size stands over its top-left corner, at the place
            // `cornerPlace` picks, with Crop on as with it off.
            coordinateLabel.isHidden = true
            sizeLabel.isHidden = true
            if let selection = scene.selection {
                let pixels = Selection.pixelSize(of: selection, scale: frozen.scale)
                let text = "\(pixels.width) × \(pixels.height)"
                let at = LabelLayer.cornerPlace(of: LabelLayer.size(of: text), over: selection, within: bounds,
                                                clearOf: scene.chrome.map { [$0.palette] } ?? [])
                cornerLabel.show(text, near: CGPoint(x: at.x, y: bounds.height - at.y - LabelLayer.size(of: text).height),
                                 within: bounds)
            } else {
                cornerLabel.isHidden = true
            }
            if let plate = scene.plate, let selection = scene.selection {
                let box = layerRect(selection)
                // The pointer's offset, as the other plates; the selection's corner
                // is the fallback for a scene with no pointer.
                if scene.plateByActions, let palette = scene.chrome.map({ layerRect($0.palette) }) {
                    let height = LabelLayer.size(of: plate).height
                    let above = palette.maxY + HelmSpace.s2
                    let y = above + height + 4 <= bounds.maxY ? above : palette.minY - HelmSpace.s2 - height
                    sizeLabel.show(plate, near: CGPoint(x: palette.minX, y: y), within: bounds)
                } else {
                    let anchor = scene.plateAt.map { CGPoint(x: $0.x, y: bounds.height - $0.y) }
                        ?? CGPoint(x: box.maxX, y: box.minY + 26)
                    sizeLabel.show(plate, near: CGPoint(x: anchor.x + 14, y: anchor.y - 26), within: bounds)
                }
            }
        } else if let selection = scene.selection {
            let pixels = Selection.pixelSize(of: selection, scale: frozen.scale)
            let box = layerRect(selection)
            // The pointer is where the eye is; the corner is the fallback for a
            // scene that has a selection and no pointer.
            let anchor = at ?? CGPoint(x: box.maxX, y: box.minY + 26)
            sizeLabel.show("\(pixels.width) × \(pixels.height)",
                           near: CGPoint(x: anchor.x + 14, y: anchor.y - 26), within: bounds)
            coordinateLabel.isHidden = true
        } else if let pointer = scene.pointer, let at, !scene.windowMode {
            coordinateLabel.show("\(Int(pointer.x.rounded())), \(Int(pointer.y.rounded()))",
                                 near: CGPoint(x: at.x + 14, y: at.y - 26), within: bounds)
            sizeLabel.isHidden = true
        } else {
            coordinateLabel.isHidden = true
            sizeLabel.isHidden = true
        }
    }

    /// The box round the selected object and a square at each of its handles; none for none.
    func drawHandles(_ annotation: Annotation?) {
        guard let annotation else {
            frameLayer.path = nil
            handleLayer.path = nil
            return
        }
        let path = CGMutablePath()
        frameLayer.path = CGPath(rect: layerRect(annotation.frame), transform: nil)
        for point in annotation.handles.map(\.point) {
            path.addRect(layerRect(CGRect(x: point.x - Self.handleSide / 2, y: point.y - Self.handleSide / 2,
                                          width: Self.handleSide, height: Self.handleSide)))
        }
        handleLayer.path = path
    }

    private static let handleSide: CGFloat = 8

    /// A dot at each of the area's handles; none for none. A dot is never wider than the reach that
    /// takes it, so an area too small for eight reaches is not drawn eight dots wide.
    private func drawAreaHandles(_ area: CGRect?) {
        guard let area else { areaHandleLayer.path = nil; drawnAreaHandles = []; return }
        let radius = min(AreaFrame.dotRadius, AreaFrame.reach(on: area))
        guard radius >= 1 else { areaHandleLayer.path = nil; drawnAreaHandles = []; return }
        drawnAreaHandles = AreaFrame.offered(on: area).map(\.point)
        let path = CGMutablePath()
        for point in drawnAreaHandles {
            path.addEllipse(in: layerRect(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)))
        }
        areaHandleLayer.path = path
    }

    /// The plates on screen apart from the area's size over its corner (`cornerLabel`), so a test can ask how many
    /// there are and where: the coordinates, the size of a drag, the Esc question, the Pin refusal and a reading's answer, which
    /// stand over or under the palette (`plateByActions`) and not by the pointer.
    var visiblePlates: [LabelLayer] { [coordinateLabel, sizeLabel].filter { !$0.isHidden } }

    /// Lights `rect` (display-local, top-left points) white and fades it, in a window's outline for a window; the palette
    /// goes, since it is not part of the shot, and the overlay is deaf until it closes.
    func flash(over rect: CGRect, window: Bool) {
        if paletteMade { paletteHost.isHidden = true }
        if popoverMade { popoverHost.isHidden = true }
        if coloursMade { coloursHost.isHidden = true }
        let box = layerRect(rect)
        flashLayer.play(shape: window ? WindowShape.path(for: box) : CGPath(rect: box, transform: nil))
    }
}
