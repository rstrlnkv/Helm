import CoreGraphics

/// The masks that should stand, from the displays, the settings and the calibration; and what changed
/// between two such lists.
enum LayoutDecision {
    /// Built-in: the bottom corners when its switch is on. External: all four when its switch is on.
    /// Calibration adds coloured top masks on the built-in display only, which never hold the pointer.
    /// Mirrored displays are skipped (every member of a mirror set).
    /// A display id that appears twice counts once, the first. A radius never exceeds what its window
    /// holds (`CornerFrames.largestSize / 2`). Mirrored displays get no masks but are still neighbours:
    /// the pointer crosses into them like into any display.
    static func decide(displays: [DisplayDescriptor], settings: CornerSettings,
                       calibration: CalibrationColour?) -> [MaskSpec] {
        var seen = Set<UInt32>()
        let all = displays.filter { seen.insert($0.id).inserted }
        let live = all.filter { !$0.isMirrored }
        var specs: [MaskSpec] = []
        for display in live {
            let bottom = display.isBuiltIn ? settings.builtIn : settings.external
            let previewing = display.isBuiltIn && calibration != nil
            guard bottom || previewing else { continue }
            let radius = min(RadiusMath.points(pixels: settings.radiusPixels, pixelsPerPoint: display.pixelsPerPoint),
                             CornerFrames.largestSize / 2)
            let size = CornerFrames.size(radius: radius)
            guard size > 0, CornerFrames.isUsable(display.frame) else { continue }
            var corners: [CornerPosition] = []
            if bottom { corners += [.bottomLeft, .bottomRight] }
            if previewing || !display.isBuiltIn { corners += [.topLeft, .topRight] }
            for corner in corners {
                let frame = CornerFrames.windowFrame(display: display.frame, size: size, corner: corner)
                let isPreview = corner.isTop && previewing
                let touched = all.contains { $0.id != display.id && touches($0.frame, corner: corner, square: frame) }
                let backing = display.backingScale.isFinite && display.backingScale > 0 ? display.backingScale : 1
                specs.append(MaskSpec(key: MaskKey(display: display.id, corner: corner), frame: frame, radius: radius,
                                      colour: isPreview ? calibration.map { .rgb($0) } ?? .black : .black,
                                      constrainsCursor: !isPreview && !touched, topLevel: corner.isTop,
                                      backingScale: backing, maxFPS: display.maxFPS))
            }
        }
        return specs
    }

    /// Review finding 5: a neighbour's frame reaches the 1 pt strip just outside the corner square, over
    /// the square's span, on either side the corner has (left/right, and above/below). The pointer
    /// crosses there into the other display, so the curve is not a wall; the mask is still drawn.
    /// A display that meets the corner only at its point shares no span and does not free it.
    private static func touches(_ other: CGRect, corner: CornerPosition, square: CGRect) -> Bool {
        let side = CGRect(x: corner.isRight ? square.maxX : square.minX - 1, y: square.minY,
                          width: 1, height: square.height)
        let beyond = CGRect(x: square.minX, y: corner.isTop ? square.maxY : square.minY - 1,
                            width: square.width, height: 1)
        return other.intersects(side) || other.intersects(beyond)
    }
}

/// The difference between two layouts, by key. The UI keeps its windows by key: a changed spec
/// resizes and repaths its window, it does not order it out (review finding 3).
public struct MaskDiff: Equatable, Sendable {
    public let added: [MaskSpec]
    public let removed: [MaskKey]
    public let changed: [MaskSpec]

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    public init(added: [MaskSpec], removed: [MaskKey], changed: [MaskSpec]) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public static func between(_ old: [MaskSpec], _ new: [MaskSpec]) -> MaskDiff {
        let old = firstPerKey(old), new = firstPerKey(new)
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.key, $0) })
        let after = Set(new.map(\.key))
        return MaskDiff(added: new.filter { before[$0.key] == nil },
                        removed: old.map(\.key).filter { !after.contains($0) },
                        changed: new.filter { before[$0.key] != nil && before[$0.key] != $0 })
    }

    /// A key listed twice counts once, the first.
    private static func firstPerKey(_ specs: [MaskSpec]) -> [MaskSpec] {
        var seen = Set<MaskKey>()
        return specs.filter { seen.insert($0.key).inserted }
    }
}
