import Foundation
import HelmRuntime

/// What the editor opens with: the last tool, the colour and fill every tool shares, and each
/// tool's own thickness step and opacity.
///
/// Read once, when the first area is released, and written at each pick. The store
/// is a property list any process running as the user can write, so every field is
/// read with its bound: a stored name that is none of the cases reads as the
/// default, a step is clamped to the steps there are and an opacity to 0.1…1. The two
/// per-tool tables are read by walking the tools there are and asking the table about each,
/// never by walking the table, so a stranger's key is never read as a tool. A table is read whole, though
/// (`[String: Int]`, `[String: Double]`): one entry of another type makes it read as no record for
/// every tool, so each falls back to its default, bounded and without a crash.
/// Not sealed — nothing unattended reads it.
public struct EditorMemory: Equatable, Sendable {
    /// Nil is no tool, which is what a drag on the area means.
    public var tool: AnnotationTool?
    private var color: AnnotationInk?
    private var filled: Bool
    private var steps: [AnnotationTool: AnnotationThickness]
    private var opacities: [AnnotationTool: Double]

    public init(tool: AnnotationTool? = nil, color: AnnotationInk? = nil, filled: Bool = false) {
        self.tool = tool
        self.color = color
        self.filled = filled
        steps = [:]
        opacities = [:]
    }

    /// What the next object of `tool` is drawn with: the shared colour and fill, that tool's own
    /// step and opacity, and for a tool with no record the middle step at full ink.
    public func style(for tool: AnnotationTool) -> AnnotationStyle {
        AnnotationStyle(color: color, thickness: steps[tool] ?? .medium, filled: filled, opacity: opacities[tool] ?? 1)
    }

    /// A pick, as the reader would see it after the write: what the overlay keeps beside the store, which a test may not have.
    public mutating func note(style: AnnotationStyle, for tool: AnnotationTool) {
        color = style.color
        filled = style.filled
        steps[tool] = style.thickness
        opacities[tool] = style.opacity
    }

    public static func read(_ store: NamespacedStore) -> EditorMemory {
        typealias Key = ScreenshotsSettings.Key
        var memory = EditorMemory(
            tool: AnnotationTool(rawValue: store.string(Key.editorTool, default: "")),
            color: readInk(store),
            filled: store.bool(Key.editorFill, default: false))
        let stored = store.intTable(Key.editorThicknessByTool)
        let opacities = store.doubleTable(Key.editorOpacityByTool)
        for tool in AnnotationTool.allCases {
            if let step = stored[tool.rawValue] {
                memory.steps[tool] = AnnotationThickness(rawValue: step.clamped(to: 0...(AnnotationThickness.allCases.count - 1)))
            }
            // A stored opacity that is not a number is full ink: a stroke that vanishes for a garbled
            // preference is worse than one that is solid, and the person sees it at once.
            if let opacity = opacities[tool.rawValue] {
                memory.opacities[tool] = opacity.clamped(to: 0.1...1, whenNotANumber: 1)
            }
        }
        return memory
    }

    /// The shared colour: `editorInk`, three numbers; or, while that key has never been written, the swatch the old
    /// `editorColor` names. A key that is there and cannot be read as three numbers is no colour, and the old key
    /// is not asked then, so a damaged record never turns into a colour from before it.
    private static func readInk(_ store: NamespacedStore) -> AnnotationInk? {
        typealias Key = ScreenshotsSettings.Key
        guard let stored = store.object(Key.editorInk) else {
            return AnnotationColor(rawValue: store.string(Key.editorColor, default: "")).map(AnnotationInk.init)
        }
        guard let parts = stored as? [Double], parts.count == 3 else { return nil }
        return AnnotationInk(red: parts[0], green: parts[1], blue: parts[2])
    }

    public static func remember(tool: AnnotationTool?, in store: NamespacedStore) {
        store.set(tool?.rawValue, for: ScreenshotsSettings.Key.editorTool)
    }

    /// The colour and fill are everybody's; the step and the opacity are written under `tool` alone,
    /// and what the two tables hold under a name that is no tool is dropped with the write.
    public static func remember(style: AnnotationStyle, for tool: AnnotationTool, in store: NamespacedStore) {
        typealias Key = ScreenshotsSettings.Key
        if let ink = style.color { store.set([ink.red, ink.green, ink.blue], for: Key.editorInk) }
        store.set(style.filled, for: Key.editorFill)
        let known = Set(AnnotationTool.allCases.map(\.rawValue))
        var steps = store.intTable(Key.editorThicknessByTool).filter { known.contains($0.key) }
        steps[tool.rawValue] = style.thickness.rawValue
        store.set(steps, for: Key.editorThicknessByTool)
        var opacities = store.doubleTable(Key.editorOpacityByTool).filter { known.contains($0.key) }
        opacities[tool.rawValue] = style.opacity
        store.set(opacities, for: Key.editorOpacityByTool)
    }
}
