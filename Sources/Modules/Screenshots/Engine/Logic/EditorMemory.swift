import Foundation
import HelmRuntime

/// What the editor opens with: the last tool, colour, thickness and fill.
///
/// Read once, when the first area is released, and written at each pick. The store
/// is a property list any process running as the user can write, so every field is
/// read with its bound: a stored name that is none of the cases reads as the
/// default, and a thickness is clamped to the steps there are. Not sealed — nothing
/// unattended reads it.
public struct EditorMemory: Equatable, Sendable {
    /// Nil is no tool, which is what a drag on the area means.
    public var tool: AnnotationTool?
    public var style: AnnotationStyle

    public init(tool: AnnotationTool? = nil, style: AnnotationStyle = .standard) {
        self.tool = tool
        self.style = style
    }

    public static func read(_ store: NamespacedStore) -> EditorMemory {
        typealias Key = ScreenshotsSettings.Key
        let steps = AnnotationThickness.allCases
        let thickness = store.int(Key.editorThickness, default: 0)
            .clamped(to: 0...(steps.count - 1))
        return EditorMemory(
            tool: AnnotationTool(rawValue: store.string(Key.editorTool, default: "")),
            style: AnnotationStyle(
                color: AnnotationColor(rawValue: store.string(Key.editorColor, default: "")),
                thickness: AnnotationThickness(rawValue: thickness) ?? .thin,
                filled: store.bool(Key.editorFill, default: false)))
    }

    public static func remember(tool: AnnotationTool?, in store: NamespacedStore) {
        store.set(tool?.rawValue, for: ScreenshotsSettings.Key.editorTool)
    }

    public static func remember(style: AnnotationStyle, in store: NamespacedStore) {
        store.set(style.color?.rawValue, for: ScreenshotsSettings.Key.editorColor)
        store.set(style.thickness.rawValue, for: ScreenshotsSettings.Key.editorThickness)
        store.set(style.filled, for: ScreenshotsSettings.Key.editorFill)
    }
}
