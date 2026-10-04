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
    /// The ⋯ menu's Share… item: what Return does, then the system's Share sheet at the thumbnail that follows. No key.
    case share
}

/// What a key or a click on the palette means to the editor: **one vocabulary**, so that a
/// tool key and the tool's cell cannot do two different things. The keys name only
/// some of these; the rest are the palette's and the ⋯ menu's.
enum EditorAction: Equatable {
    case tool(AnnotationTool)
    /// The eraser, a mode of the editor and no `AnnotationTool`: a drag takes away the layers it meets, and the chosen tool
    /// stays chosen under it. The key again puts it down; choosing any tool, or Select, does too.
    case erase
    /// The ruler: a switch and no tool and no mode. It is put on the picture, in the middle of the area, or lowered; the tool chosen,
    /// or the eraser, is as it was.
    case toggleRuler
    /// The ⋯ menu's Crop, a mode and no tool, with no key: while it is on the area's handles are offered, the pending area is what
    /// the screen shows, Return takes it and Esc, a tool, the eraser or Select gives the area back. Choosing it again is Esc's.
    case crop
    /// The ⋯ menu's Select: no tool, so a drag selects. Choosing it twice is still no tool.
    case select
    /// A cell of the emoji grid: the emoji the Emoji tool places on the next click on the picture. Nothing happens unless that tool is chosen
    /// and the string is one grapheme that leaves ink (`EmojiSet.isOne`).
    case pickEmoji(String)
    /// The next object's colour, thickness and, for the boxes, fill.
    case color(AnnotationColor)
    case thickness(AnnotationThickness)
    /// The next object's opacity, held to 0.1…1 where it is applied.
    case opacity(Double)
    /// Opens the thickness and opacity pop-over under the palette (above it when there is no room), centred at `anchorX` in the palette's own
    /// points (the cell that asked); opening one that is open closes it, and with no tool chosen nothing opens.
    case thicknessAndOpacity(anchorX: CGFloat)
    /// Opens the colours pop-over, all eight inks, the same way under the colour wheel's cell: the one at a time with
    /// the thickness pop-over, and open with no tool chosen too, since the colour is every tool's.
    case colours(anchorX: CGFloat)
    case toggleFill
    case undo, redo
    /// ⌫ and ⌦: the selected object goes; with none selected it asks nothing.
    case delete
    case exit(EditorExit)
    /// The ⋯ menu's Copy Text and Blur Emails and Phone Numbers, no keys: each reads the area as the screen shows it and acts on the
    /// answer when it comes (`CaptureOverlay.beginReading`); both are in the menu and disabled while a reading runs.
    case copyText, blurPersonalText
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
    /// The tool keys, the one table: `action(keyCode:flags:)` reads the code and the ⋯ menu shows the letter beside the tool.
    /// The letter is what the key says on an English layout; the code is what is matched.
    static let toolKeys: [(tool: AnnotationTool, code: Int, letter: String)] = [
        (.arrow, kVK_ANSI_A, "A"), (.rectangle, kVK_ANSI_R, "R"), (.ellipse, kVK_ANSI_O, "O"), (.line, kVK_ANSI_L, "L"),
        (.pen, kVK_ANSI_N, "N"), (.pencil, kVK_ANSI_P, "P"), (.highlighter, kVK_ANSI_H, "H"),
        (.text, kVK_ANSI_T, "T"), (.blur, kVK_ANSI_B, "B"),
    ]

    /// The eraser's key code (E on an English layout), which is no tool's: the eraser has no row in `toolKeys`, and an item in the ⋯ menu only while it is taken off the palette's row.
    static let eraserKeyCode = kVK_ANSI_E

    /// The ruler's key code (U on an English layout), the same way: no row in `toolKeys`, and an item in the ⋯ menu only while it is taken off the palette's row.
    static let rulerKeyCode = kVK_ANSI_U

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
        if flags.isEmpty, let key = toolKeys.first(where: { $0.code == Int(keyCode) }) { return .tool(key.tool) }
        if flags.isEmpty, Int(keyCode) == eraserKeyCode { return .erase }
        if flags.isEmpty, Int(keyCode) == rulerKeyCode { return .toggleRuler }
        switch (Int(keyCode), flags) {
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
