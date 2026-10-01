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
}

/// What a key means to the editor.
enum EditorAction: Equatable {
    case tool(AnnotationTool)
    case undo, redo
    case exit(EditorExit)
}

/// **Keys by physical key code, never by character.** The owner types Russian: the
/// key that says A on an English layout says Ф on theirs and `characters` follows
/// the layout, so a binding written on it works for one of the two. The code names
/// the place on the keyboard.
enum EditorKeys {
    static func action(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> EditorAction? {
        let flags = flags.intersection([.command, .shift, .option, .control])
        switch (Int(keyCode), flags) {
        case (kVK_ANSI_A, []): return .tool(.arrow)
        case (kVK_ANSI_R, []): return .tool(.rectangle)
        case (kVK_ANSI_O, []): return .tool(.ellipse)
        case (kVK_ANSI_L, []): return .tool(.line)
        case (kVK_ANSI_P, []): return .tool(.pencil)
        case (kVK_ANSI_H, []): return .tool(.highlighter)
        case (kVK_ANSI_Z, .command): return .undo
        case (kVK_ANSI_Z, [.command, .shift]): return .redo
        case (kVK_ANSI_C, .command): return .exit(.copy)
        case (kVK_ANSI_S, .command): return .exit(.save)
        case (kVK_Return, _), (kVK_ANSI_KeypadEnter, _): return .exit(.confirm)
        default: return nil
        }
    }
}
