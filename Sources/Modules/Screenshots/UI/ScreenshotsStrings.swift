import Foundation
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

enum ScStr {
    /// macOS's own word for them — «Bildschirmfotos», «Снимки экрана» — read out
    /// of `DefaultShortcutsTable.loctable`, where the same pane is titled.
    static var moduleName: String { L("Screenshots") }
    static var summary: String { L("Capture the screen, an area or a window") }

    static var needsAccess: String {
        L("Helm cannot read the screen until Screen & System Audio Recording is allowed, so the shortcuts below capture nothing.")
    }

    /// The system's own term, the same key Keyboard's page already carries.
    static var shortcuts: String { L("Keyboard shortcuts") }
    static var captureArea: String { L("Capture an area") }
    static var captureScreen: String { L("Capture the whole screen") }
    static var openPanel: String { L("Open the capture panel") }
    static var conflict: String {
        L("macOS still holds this combination for one of its own shortcuts. Untick it below first.")
    }

    static var systemSection: String { L("System shortcuts") }
    /// Over the boxes, which are three — ⇧⌘3 and ⇧⌘4 with their clipboard
    /// twins, and box 184 — so the title names none of the combinations.
    static var replaceTitle: String { L("macOS's own screenshot shortcuts") }
    static var replaceBody: String {
        L("To use them, untick their boxes below in System Settings. Helm reads that setting and never changes it.")
    }
    static var stillOn: String { L("Still on in macOS") }
    static var isOff: String { L("Off in macOS") }
    static var unknown: String { L("macOS did not say") }
    static var openSystemSettings: String { L("Open System Settings…") }
    static var useSystemKeys: String { L("Use ⇧⌘3 and ⇧⌘4") }
    /// Its own key and not an interpolation: the three combinations are spelled
    /// whole in each language, and the button that takes ⇧⌘5 as well says so.
    static var useSystemKeysAndPanel: String { L("Use ⇧⌘3, ⇧⌘4 and ⇧⌘5") }

    /// The four boxes macOS ticks, in macOS's own words — copied out of the
    /// Keyboard settings extension's `DefaultShortcutsTable.loctable`, which is
    /// where the list Helm sends a person to draws them. `TheNameIsMacOSsInEveryLanguageTests`
    /// reads that table and compares.
    static func boxName(_ box: SystemBox) -> String {
        switch box {
        case .saveScreen: L("Save picture of screen as a file")
        case .saveArea: L("Save picture of selected area as a file")
        case .copyScreen: L("Copy picture of screen to the clipboard")
        case .copyArea: L("Copy picture of selected area to the clipboard")
        case .panel: L("Screenshot and recording options")
        }
    }

    /// Under macOS's box 184, which is ⇧⌘5: that shortcut is also how screen
    /// recording is reached from the keyboard, and Helm has no recording.
    static var panelBoxWarning: String {
        L("Helm's panel takes ⇧⌘5 only when this is unticked. Unticking it also removes the keyboard shortcut for screen recording.")
    }

    /// macOS's own words for the bar — the tooltips of its three capture buttons,
    /// «Options», «Timer», «Capture», «Show Floating Thumbnail» and «Remember Last
    /// Selection» — read out of `screencaptureui`'s `Localizable.loctable`;
    /// `TheNameIsMacOSsInEveryLanguageTests` reads that table and compares.
    static var panelScreen: String { L("Capture entire screen") }
    static var panelWindow: String { L("Capture selected window") }
    static var panelArea: String { L("Capture selected portion") }
    static var captureButton: String { L("Capture") }
    static var options: String { L("Options") }
    static var timer: String { L("Timer") }
    static func timer(_ timer: CaptureTimer) -> String {
        switch timer {
        case .none: L("No timer")
        case .five: L("5 seconds")
        case .ten: L("10 seconds")
        }
    }
    static var floatingThumbnail: String { L("Show floating thumbnail") }
    static var rememberSelection: String { L("Remember last selection") }
    static var closePanel: String { L("Close") }

    /// macOS's own words — Save to, Desktop, Documents, Clipboard, Other… — read
    /// out of `screencaptureui`'s `Localizable.loctable`, where the same menu is drawn.
    static var saveTo: String { L("Save to") }
    static var targetMacOS: String { L("Same as macOS") }
    static var targetDesktop: String { L("Desktop") }
    static var targetDocuments: String { L("Documents") }
    static var targetClipboard: String { L("Clipboard") }
    /// Its own key, not KeepAwake's «Other…»: one key means one thing, and
    /// Portuguese says «Outra» for a folder where a duration is «Outro».
    /// The seven translations are macOS's «Other…» from the same table.
    static var targetOther: String { L("Other folder…") }
    static func target(_ target: SaveTarget) -> String {
        switch target {
        case .macOS: targetMacOS
        case .desktop: targetDesktop
        case .documents: targetDocuments
        case .clipboard: targetClipboard
        case .other: targetOther
        }
    }

    static var format: String { L("Capture format") }
    /// File-format names: the same letters in every language.
    static func format(_ format: ShotFormat) -> String {
        switch format {
        case .png: L("PNG")
        case .jpeg: L("JPEG")
        }
    }
    static var shutterSound: String { L("Shutter sound") }
    static var showCursor: String { L("Show mouse pointer") }
    static var chooseFolder: String { L("Choose…") }

    static var folder: String { L("Save folder") }
    static var folderNote: String { L("Where macOS keeps screenshots. Helm reads it and never changes it.") }
    static var folderRefused: String {
        L("The folder macOS names cannot be used, so Helm saves to the Desktop.")
    }
    static var chosenRefused: String {
        L("That folder cannot be used, so Helm saves to the Desktop.")
    }

    // MARK: - The editor's bars

    /// The tools, in the words of macOS's own Preview markup menu; the ellipse is
    /// «Oval» there, and «Highlight» is its marker.
    static func tool(_ tool: AnnotationTool) -> String {
        switch tool {
        case .arrow: L("Arrow")
        case .rectangle: L("Rectangle")
        case .ellipse: L("Oval")
        case .line: L("Line")
        case .pencil: L("Pencil")
        case .highlighter: L("Highlight")
        }
    }

    /// The colours: the six Helm's palette already names, and «Black» is named in AppKit's colour panel table (`NSColorPanelExtras.loctable`), and both it and «White» in the system colour list (`Apple.clr/Apple.loctable`); in Japanese both are the system colour list's words (ブラック, ホワイト).
    static func ink(_ color: AnnotationColor) -> String {
        switch color {
        case .red: L("Red")
        case .orange: L("Orange")
        case .yellow: L("Yellow")
        case .green: L("Green")
        case .blue: L("Blue")
        case .purple: L("Purple")
        case .black: L("Black")
        case .white: L("White")
        }
    }

    /// Thickness, Fill, Copy and Save have no cell on the palette: the next task's ⋯ menu takes them, and these
    /// names are kept for it. Pin is read by the palette's Pin cell while `PinEntry.isOffered`.
    static func thickness(_ step: AnnotationThickness) -> String {
        switch step {
        case .thin: L("Thin")
        case .medium: L("Medium")
        case .thick: L("Thick")
        }
    }

    static var fill: String { L("Filled") }
    /// Preview's «Undo» and «Redo».
    static var undo: String { L("Undo") }
    static var redo: String { L("Redo") }
    static var copy: String { L("Copy") }
    /// Preview's «Save».
    static var save: String { L("Save") }
    static var closeEditor: String { L("Close") }
    /// The editor's checkmark: what Return does.
    static var done: String { L("Done") }
    /// The editor's Pin cell, which keeps the picture on the screen as a window.
    static var pin: String { L("Pin") }
    /// The plate at the limit of open pins; no number, so no table.
    static var pinLimit: String { L("Too many pins are open — close one first") }
    /// What a screen reader calls a pin.
    static var pinnedScreenshot: String { L("Pinned screenshot") }

    // MARK: - The toast

    /// The word in a file name and on a thumbnail. One key, macOS's own word.
    static var thumbnailLabel: String { L("Screenshot") }
    static var saved: String { L("Saved") }
    static var copied: String { L("Copied to the clipboard") }
    static var savedAndCopied: String { L("Saved and copied") }
    /// The plate over an edited picture after a first Esc.
    static var confirmClose: String { L("Press Esc again to close without saving") }
    static var dismissToast: String { L("Close") }
    static var openSettings: String { L("Open Settings") }
    static var noPermissionTitle: String { L("Helm cannot read the screen") }
    static var noPermissionBody: String {
        L("Allow Helm under Screen & System Audio Recording, then press the shortcut again.")
    }
    static var failedTitle: String { L("The screenshot was not taken") }

    /// One sentence per thing that can go wrong, and none of them carries a path.
    static func refusal(_ reason: CaptureRefusal) -> String {
        switch reason {
        case .noPermission: noPermissionBody
        case .captureFailed: L("The screen could not be captured.")
        case .displayGone: L("A display went away before it could be captured.")
        case .windowGone: L("That window is gone.")
        case .write(.noFolder), .write(.notAFolder): L("The save folder is missing.")
        case .write(.noPermission): L("Helm may not write to the save folder.")
        case .write(.diskFull): L("The disk is full.")
        case .write(.namesExhausted), .write(.failed): L("The screenshot could not be saved.")
        case .pasteboard: L("The clipboard did not take the picture.")
        case .encoding: L("The picture could not be made.")
        }
    }

    /// macOS's own file-name template, with its word already in it. The English
    /// key is the pattern and the seven translations are copied out of
    /// `screencaptureui`'s `Localizable.loctable` — the template for the order of
    /// the parts and the word for the noun — at development time;
    /// `TheNameIsMacOSsInEveryLanguageTests` reads that table and compares.
    static var nameTemplate: String { L("Screenshot %@ at %@") }

    /// The word is Helm's language and the clock is the system's region, both
    /// at once: macOS names its own files by the hour cycle of the region, and a
    /// person who has both expects the same file names from both — but a file
    /// called "Screenshot … at 오후 10.25.33" is half of each. The locale is the
    /// language Helm is speaking in the region the Mac is set to, so the
    /// day-period marker comes in the word's language and the hour cycle in the
    /// region's.
    static var naming: ShotNaming { naming(system: .current) }

    /// `system` is the Mac's locale; a test passes one the machine it runs on
    /// is not set to.
    static func naming(system: Locale, language: AppLanguage = .current) -> ShotNaming {
        ShotNaming(template: nameTemplate, locale: fileNameLocale(language: language, system: system))
    }

    static func fileNameLocale(language: AppLanguage, system: Locale) -> Locale {
        var parts = Locale.Components(locale: system)
        // The language and its script only: the region, the calendar and the
        // hour cycle stay the Mac's own.
        parts.languageComponents.languageCode = Locale.LanguageCode(language.rawValue)
        parts.languageComponents.script = nil
        return Locale(components: parts)
    }
}
