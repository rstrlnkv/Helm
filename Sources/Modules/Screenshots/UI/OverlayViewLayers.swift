import AppKit
import QuartzCore
import Module_Screenshots_Engine

extension OverlayView {
    /// One shape layer per annotation, each a **direct child of the view's layer**, between the picture
    /// and the dim, in the annotations' own order. Not inside a clipping parent: a layer's
    /// `compositingFilter` blends with what is beneath it in the same parent only, so a marker nested in
    /// a clip came out olive over black text where the export multiplies to black. The selection is the
    /// clip all the same, by geometry — the outline of the stroke, intersected with the selection's
    /// rectangle, filled — and the dim's hole is what leaves it undimmed.
    ///
    /// **A layer is built once and kept while its annotation is equal to the one it was built from.**
    /// Stroking and intersecting an `Annotation.maxPoints` path is expected to cost milliseconds (an estimate, not a
    /// measurement) and the scene is applied on every pointer event, so only what changed is rebuilt: the draft, the object being moved or resized, the
    /// one recoloured. The cache is by `Annotation.id` and is dropped with the selection's rectangle.
    func drawLayers(_ scene: OverlayScene) {
        guard scene.editing, let selection = scene.selection else {
            for shape in drawnShapes { shape.removeFromSuperlayer() }
            drawnShapes = []
            shapeCache = [:]
            draftGrain = nil
            spotlightLayer.path = nil
            drawHandles(nil)
            return
        }
        let box = layerRect(selection)
        if cachedBox != box {
            for entry in shapeCache.values { entry.shape.removeFromSuperlayer() }
            shapeCache = [:]
            cachedBox = box
        }
        // The spotlights are one layer, laid here and not by `makeShape`: a layer of each would dim twice where two meet.
        var turn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        spotlightLayer.path = Spotlights.dim(of: scene.layers, within: selection)?.copy(using: &turn)
        var kept: [Annotation.ID: (annotation: Annotation, shape: CALayer, draft: Bool, number: Int?)] = [:]
        for (annotation, number) in zip(scene.layers, AnnotationStep.numbers(in: scene.layers)) where annotation.tool != .spotlight {
            let draft = annotation.id == scene.draftID
            // A step's picture holds its number, which another step's removal changes without touching the layer.
            if let entry = shapeCache[annotation.id], entry.annotation == annotation, entry.number == number {
                // The draft's grain covers the display; once it is released it is cut to the stroke's own box.
                if entry.draft && !draft && annotation.tool.isGrainy { entry.shape.mask = grainMask(annotation, draft: false) }
                kept[annotation.id] = (entry.annotation, entry.shape, draft, number)
            } else {
                shapeCache[annotation.id]?.shape.removeFromSuperlayer()
                kept[annotation.id] = (annotation, makeShape(annotation, number: number, clippedTo: box, draft: draft), draft, number)
            }
        }
        for (id, entry) in shapeCache where kept[id]?.shape !== entry.shape { entry.shape.removeFromSuperlayer() }
        shapeCache = kept
        for annotation in scene.layers {
            kept[annotation.id]?.shape.opacity = scene.fading.contains(annotation.id) ? Self.fadedOpacity : 1
        }
        // The draft's whole-display grain lives as long as the draft: a release has just cut it, a drop (Esc, right
        // click) leaves no draft among the layers, and either event ends here.
        if !kept.values.contains(where: \.draft) { draftGrain = nil }
        let ordered = scene.layers.compactMap { kept[$0.id]?.shape }
        // Re-inserting each below the dim in turn is what puts the sequence in order.
        if ordered.count != drawnShapes.count || !zip(ordered, drawnShapes).allSatisfy({ $0 === $1 }) {
            for shape in ordered { layer?.insertSublayer(shape, below: dimLayer) }
        }
        drawnShapes = ordered
        drawHandles(scene.selected)
    }

    /// The blur's layer: the export's own mosaic (`Pixelate.tile` over the same picture the file is cut from) as the
    /// layer's contents, one image pixel to a screen pixel, the selection's rectangle its mask. A layer of its own
    /// and not a path: the mosaic has no outline to fill.
    private func makeMosaic(_ annotation: Annotation, clippedTo box: CGRect) -> CALayer {
        makeTiled(Pixelate.tile(of: frozen.shot, rect: annotation.frame, blockPoints: annotation.blockPoints, scale: frozen.scale),
                  clippedTo: box)
    }

    /// A picture of whole display pixels as a layer, one image pixel to a screen pixel, the selection's rectangle its mask:
    /// the mosaic of a blur, and a text's line (`AnnotationText.tile`, the export's own `draw` into a bitmap).
    private func makeTiled(_ tile: Pixelate.Tile?, clippedTo box: CGRect) -> CALayer {
        let layer = CALayer()
        guard let tile else { return layer }
        let scale = frozen.scale
        layer.frame = CGRect(x: tile.pixels.minX / scale, y: bounds.height - tile.pixels.maxY / scale,
                             width: tile.pixels.width / scale, height: tile.pixels.height / scale)
        layer.contents = tile.image
        layer.contentsScale = scale
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        mask.frame = box.offsetBy(dx: -layer.frame.minX, dy: -layer.frame.minY)
        layer.mask = mask
        return layer
    }

    private func makeShape(_ annotation: Annotation, number: Int?, clippedTo box: CGRect, draft: Bool) -> CALayer {
        if annotation.tool == .blur { return makeMosaic(annotation, clippedTo: box) }
        if annotation.tool == .text || annotation.tool == .emoji { return makeTiled(AnnotationText.tile(of: annotation, scale: frozen.scale), clippedTo: box) }
        if annotation.tool == .magnifier {
            return makeTiled(Magnifier.tile(of: annotation, over: frozen.shot, scale: frozen.scale), clippedTo: box)
        }
        if let number { return makeTiled(AnnotationStep.tile(of: annotation, number: number, scale: frozen.scale), clippedTo: box) }
        let clip = CGPath(rect: box, transform: nil)
        var turn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        let shape = CAShapeLayer()
        shape.contentsScale = frozen.scale
        shape.frame = bounds
        let path = annotation.outline.copy(using: &turn)
        if let stroke = annotation.stroke, let path {
            let line = path.copy(strokingWithWidth: stroke.width, lineCap: stroke.cap, lineJoin: stroke.join,
                                 miterLimit: 10)
            shape.path = line.intersection(clip)
            shape.fillColor = stroke.color
            // The export's `.multiply` blend; a layer composites with the picture
            // beneath it by this filter name.
            if stroke.multiplies { shape.compositingFilter = "multiplyBlendMode" }
            shape.mask = grainMask(annotation, draft: draft)
        } else {
            shape.path = path?.intersection(clip)
            shape.fillColor = annotation.fillColor
        }
        shape.strokeColor = nil
        return shape
    }

    /// The pencil's grain, the file's one: the same function over the display's own pixels, laid on the layer at one
    /// pixel to a pixel. A finished stroke's is cut to its own box. A draft's covers the display and is kept for as
    /// long as its anchor stands, since the grain does not follow the path and the shape's path clips it: a drag
    /// pays the build once and not per pointer event.
    /// Nil for every tool but the pencil: `AnnotationTool.isGrainy` decides it, here and in the export, so no caller can give the Pen or the Marker a grain.
    private func grainMask(_ annotation: Annotation, draft: Bool) -> CALayer? {
        guard annotation.tool.isGrainy, let stroke = annotation.stroke else { return nil }
        let display = CGRect(x: 0, y: 0, width: bounds.width * frozen.scale, height: bounds.height * frozen.scale)
        let pixels: CGRect, alpha: CGImage
        if draft, let anchor = annotation.points.first {
            let key = DraftGrain(anchor: anchor, scale: frozen.scale, size: display.size)
            if draftGrain?.key != key {
                draftGrain = PencilGrain.mask(anchoredAt: anchor, scale: frozen.scale, pixels: display)
                    .flatMap { grain in grain.alpha.map { (key, grain, $0) } }
            }
            guard let kept = draftGrain else { return nil }
            (pixels, alpha) = (kept.mask.pixels, kept.alpha)
        } else {
            // Released: the draft's own grain, cut to the stroke's box, and no longer kept whole.
            let box = PencilGrain.box(for: annotation.points, width: stroke.width, scale: frozen.scale, pixels: display)
            let grain = box.flatMap { draftGrain?.mask.cut(to: $0) }
                ?? PencilGrain.mask(for: annotation.points, width: stroke.width, scale: frozen.scale, pixels: display)
            draftGrain = nil
            guard let grain, let cut = grain.alpha else { return nil }
            (pixels, alpha) = (grain.pixels, cut)
        }
        let mask = CALayer()
        mask.contents = alpha
        mask.contentsScale = frozen.scale
        mask.magnificationFilter = .nearest
        mask.frame = CGRect(x: pixels.minX / frozen.scale, y: bounds.height - pixels.maxY / frozen.scale,
                            width: pixels.width / frozen.scale, height: pixels.height / frozen.scale)
        return mask
    }
}
