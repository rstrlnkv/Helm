import AppKit
import Carbon.HIToolbox
import Module_Screenshots_Engine

/// How the editor leaves, and what each way does with the picture.
enum EditorExit: Equatable {
    /// Return: what the settings say — copy and/or save by the save target.
    case confirm
    /// ⌘C: the clipboard only.
    case copy
    /// ⌘S: a file only.
    case save
    /// The ⋯ menu's Pin item, offered only while `PinEntry.isOffered`: the picture stays on the screen as a window. No key.
    case pin
}

/// What a key or a click on the palette means to the editor: **one vocabulary**, so that a
/// tool key and the tool's cell cannot do two different things. The keys name only
/// some of these; the rest are the palette's and the ⋯ menu's.
enum EditorAction: Equatable {
    case tool(AnnotationTool)
    /// The ⋯ menu's Select: no tool, so a drag selects. Choosing it twice is still no tool.
    case select
    /// The next object's colour, thickness and, for the boxes, fill.
    case color(AnnotationColor)
    case thickness(AnnotationThickness)
    case toggleFill
    case undo, redo
    /// ⌫ and ⌦: the selected object goes; with none selected it asks nothing.
    case delete
    case exit(EditorExit)
    /// An arrow: `pixels` of the display's own pixels along a direction, each component -1, 0 or 1.
    /// The selected object moves, or the area when none is selected.
    case nudge(dx: Int, dy: Int, pixels: Int)
    /// The palette's ✕: Esc's own rule, which asks first when there are layers.
    case close
}

/// **Keys by physical key code, never by character.** The owner types Russian: the
/// key that says A on an English layout says Ф on theirs and `characters` follows
/// the layout, so a binding written on it works for one of the two. The code names
/// the place on the keyboard.
enum EditorKeys {
    static func action(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> EditorAction? {
        let flags = flags.intersection([.command, .shift, .option, .control])
        // The arrows carry the numeric-pad and function flags of their own, which the intersection
        // drops; ⇧ makes the step ten pixels, and any other modifier is not a nudge.
        if flags.isSubset(of: .shift) {
            let pixels = flags.contains(.shift) ? 10 : 1
            switch Int(keyCode) {
            case kVK_LeftArrow: return .nudge(dx: -1, dy: 0, pixels: pixels)
            case kVK_RightArrow: return .nudge(dx: 1, dy: 0, pixels: pixels)
            case kVK_UpArrow: return .nudge(dx: 0, dy: -1, pixels: pixels)
            case kVK_DownArrow: return .nudge(dx: 0, dy: 1, pixels: pixels)
            default: break
            }
        }
        switch (Int(keyCode), flags) {
        case (kVK_ANSI_A, []): return .tool(.arrow)
        case (kVK_ANSI_R, []): return .tool(.rectangle)
        case (kVK_ANSI_O, []): return .tool(.ellipse)
        case (kVK_ANSI_L, []): return .tool(.line)
        case (kVK_ANSI_N, []): return .tool(.pen)
        case (kVK_ANSI_P, []): return .tool(.pencil)
        case (kVK_ANSI_H, []): return .tool(.highlighter)
        case (kVK_Delete, []), (kVK_ForwardDelete, []): return .delete
        case (kVK_ANSI_Z, .command): return .undo
        case (kVK_ANSI_Z, [.command, .shift]): return .redo
        case (kVK_ANSI_C, .command): return .exit(.copy)
        case (kVK_ANSI_S, .command): return .exit(.save)
        case (kVK_Return, _), (kVK_ANSI_KeypadEnter, _): return .exit(.confirm)
        default: return nil
        }
    }
}
