import Foundation
import HelmRuntime

/// Where a capture goes. **One setting decides it**: there is no second key for
/// "and the clipboard", so a screen and an area can never disagree about it.
///
/// `macOS` is the state of a store nothing was written into — the folder
/// `com.apple.screencapture` names, read and never written — which is why an
/// absent or unreadable key reads as it.
public enum SaveTarget: String, CaseIterable, Sendable {
    case macOS, desktop, documents, clipboard, other

    /// A file is written. The clipboard target is the only one that writes none.
    public var savesAFile: Bool { self != .clipboard }
}

/// What the file is encoded as. The clipboard always takes a PNG, whatever this
/// says: a pasteboard consumer that is handed a JPEG has lost the alpha of a
/// window's shadow for nothing.
public enum ShotFormat: String, CaseIterable, Sendable {
    case png, jpeg

    public var pathExtension: String { self == .png ? "png" : "jpg" }

    /// ImageIO's lossy quality for a JPEG. What macOS's own tool uses was not measured.
    public static let jpegQuality: Double = 0.9
}

/// The countdown before a shot. A stored number that is not one of the cases
/// reads as none: a plist can hold `1e300`, and a countdown of that is a press
/// that never ends.
public enum CaptureTimer: Int, CaseIterable, Sendable {
    case none = 0, five = 5, ten = 10, thirty = 30

    public var seconds: Int { rawValue }
}

/// What the panel's bar opens on.
public enum PanelMode: String, CaseIterable, Sendable {
    case area, window, screen
}

/// The module's stored settings, each read with its bound.
///
/// Read at the act, not at activation: the settings page writes the store and
/// nothing tells the session, and a session that cached them would act on the
/// answer the person replaced. The property list is a file anything running as
/// the user can write, so a stored string that is not one of the cases reads as
/// the default rather than as a crash or as "off".
public struct ScreenshotsSettings: Equatable, Sendable {
    public var saveTarget: SaveTarget
    /// The folder `other` names, as typed or chosen; nil when none was stored.
    /// Judged by `SaveLocation.resolve` at every capture and never trusted.
    public var otherFolder: String?
    public var format: ShotFormat
    public var thumbnail: Bool
    public var shutterSound: Bool
    public var showCursor: Bool
    /// Seconds now; `none` is off.
    public var timer: CaptureTimer
    /// The length the panel's timer cell switches on with: the last one picked, never `none`.
    public var timerLength: CaptureTimer
    public var rememberSelection: Bool
    public var panelMode: PanelMode
    /// Where the panel stands, as a move from its place by default (`PanelPlace`).
    public var panelOffset: PanelOffset

    public init(saveTarget: SaveTarget = .macOS, otherFolder: String? = nil,
                format: ShotFormat = .png, thumbnail: Bool = true, shutterSound: Bool = true,
                showCursor: Bool = false, timer: CaptureTimer = .none, timerLength: CaptureTimer = .five,
                rememberSelection: Bool = false, panelMode: PanelMode = .area, panelOffset: PanelOffset = .zero) {
        self.saveTarget = saveTarget
        self.otherFolder = otherFolder
        self.format = format
        self.thumbnail = thumbnail
        self.shutterSound = shutterSound
        self.showCursor = showCursor
        self.timer = timer
        self.timerLength = timerLength
        self.rememberSelection = rememberSelection
        self.panelMode = panelMode
        self.panelOffset = panelOffset
    }

    public static let defaults = ScreenshotsSettings()

    /// A path longer than this is not a path anybody chose: it is read as none.
    static let longestFolder = 4096

    public static func read(_ store: NamespacedStore) -> ScreenshotsSettings {
        let folder = store.string(Key.otherFolder, default: "")
        let timer = CaptureTimer(rawValue: store.int(Key.timer, default: 0)) ?? defaults.timer
        return ScreenshotsSettings(
            saveTarget: SaveTarget(rawValue: store.string(Key.saveTarget, default: "")) ?? defaults.saveTarget,
            otherFolder: folder.isEmpty || folder.count > longestFolder ? nil : folder,
            format: ShotFormat(rawValue: store.string(Key.format, default: "")) ?? defaults.format,
            thumbnail: store.bool(Key.thumbnail, default: defaults.thumbnail),
            shutterSound: store.bool(Key.shutterSound, default: defaults.shutterSound),
            showCursor: store.bool(Key.showCursor, default: defaults.showCursor),
            timer: timer,
            timerLength: timerLength(store, timer: timer),
            rememberSelection: store.bool(Key.rememberSelection, default: defaults.rememberSelection),
            panelMode: PanelMode(rawValue: store.string(Key.panelMode, default: "")) ?? defaults.panelMode,
            panelOffset: PanelOffset.read(store))
    }

    /// **Only a missing key says "not yet migrated"**: then the length is what `timer` holds, if it holds one, else
    /// five. A key that is there and is not a length (`none`, a string, `1e300`) is a damaged value and reads as five,
    /// where the timer's own number would be a second answer to the same question.
    private static func timerLength(_ store: NamespacedStore, timer: CaptureTimer) -> CaptureTimer {
        guard store.object(Key.timerLength) != nil else { return timer == .none ? .five : timer }
        let stored = CaptureTimer(rawValue: store.int(Key.timerLength, default: 0))
        return stored.flatMap { $0 == .none ? nil : $0 } ?? .five
    }

    /// The one door for "Remember last selection". Switching it off **erases**
    /// the stored selection: the option is a promise that nothing about the
    /// last area is kept, and a record left behind would come back, stale, the
    /// day it is switched on again. Every writer of the key goes through here.
    public static func setRememberSelection(_ on: Bool, in store: NamespacedStore) {
        if !on { RememberedSelection.erase(from: store) }
        store.set(on, for: Key.rememberSelection)
    }

    /// **Deployed stored data: these names never move.**
    public enum Key {
        public static let saveTarget = "saveTarget"
        public static let otherFolder = "otherFolder"
        public static let format = "format"
        public static let thumbnail = "thumbnail"
        public static let shutterSound = "shutterSound"
        public static let showCursor = "showCursor"
        public static let timer = "timer"
        public static let rememberSelection = "rememberSelection"
        public static let panelMode = "panelMode"
        /// The last length the timer was switched on with; `timer` stays "seconds now, 0 is off" and is not re-keyed.
        public static let timerLength = "timerLength"
        /// The panel's move from its place by default, one number per axis (`PanelOffset`).
        public static let panelOffsetX = "panelOffsetX"
        public static let panelOffsetY = "panelOffsetY"
        /// The editor's memory, read by `EditorMemory` and not by `ScreenshotsSettings`.
        public static let editorTool = "editorTool"
        /// The swatch's name, which the Settings row writes: the colour a tool starts with until it has its own: the editor
        /// reads it only while `editorInk` is absent, the Settings row always. Never re-keyed.
        public static let editorColor = "editorColor"
        /// The colour every tool had before each kept its own, `[red, green, blue]`, sRGB 0…1 (`AnnotationInk`): written no
        /// more, read as the start of a tool with no entry in `editorInkByTool`; the Settings row's pick removes it (a pick in the editor never writes it).
        public static let editorInk = "editorInk"
        /// Tool raw value → `[red, green, blue]`, each tool's own colour (`EditorMemory`).
        public static let editorInkByTool = "editorInkByTool"
        /// Retired, not read: one step for every tool, before each tool had its own. Never reused.
        public static let editorThickness = "editorThickness"
        /// Tool raw value → step 0…2, and tool raw value → opacity, each tool's own (`EditorMemory`).
        public static let editorThicknessByTool = "editorThicknessByTool"
        public static let editorOpacityByTool = "editorOpacityByTool"
        public static let editorFill = "editorFill"
        /// Palette item raw value → shown or hidden, the person's own picks only (`PaletteItems`).
        public static let paletteChoices = "paletteChoices"
    }
}

/// Whether the shutter sounds: the module's switch **and** the system's.
///
/// `com.apple.sound.uiaudio.enabled` is the "Play user interface sound effects"
/// switch of System Settings. Absent is the ordinary state and means on; a
/// number that is zero means off; any other kind of value is not a decision and
/// reads as on, because a sound that is silent for a garbled preference is
/// harder to find than one that plays. Whether macOS's own capture honours the
/// key on this Mac was not measured.
public enum ShutterRule {
    public static func plays(setting: Bool, uiAudio: Any?) -> Bool {
        guard setting else { return false }
        guard let number = uiAudio as? NSNumber else { return true }
        return number.doubleValue != 0
    }
}
