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
    static var conflict: String {
        L("macOS still holds this combination for one of its own shortcuts. Untick it below first.")
    }

    static var systemSection: String { L("System shortcuts") }
    static var replaceTitle: String { L("Use ⇧⌘3 and ⇧⌘4 here") }
    static var replaceBody: String {
        L("To use them, untick these two in System Settings. Helm reads that setting and never changes it.")
    }
    static var stillOn: String { L("Still on in macOS") }
    static var isOff: String { L("Off in macOS") }
    static var unknown: String { L("macOS did not say") }
    static var openSystemSettings: String { L("Open System Settings…") }
    static var useSystemKeys: String { L("Use ⇧⌘3 and ⇧⌘4") }

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
        }
    }

    static var afterFullScreen: String { L("After a full-screen capture") }
    static var afterFile: String { L("Save to the folder") }
    static var afterClipboard: String { L("Copy to the clipboard") }
    static var afterBoth: String { L("Save and copy") }
    static func after(_ destination: ScreenDestination) -> String {
        switch destination {
        case .file: afterFile
        case .clipboard: afterClipboard
        case .both: afterBoth
        }
    }

    static var thumbnail: String { L("Show a thumbnail after a capture") }
    static var folder: String { L("Save folder") }
    static var folderNote: String { L("Where macOS keeps screenshots. Helm reads it and never changes it.") }
    static var folderRefused: String {
        L("The folder macOS names cannot be used, so Helm saves to the Desktop.")
    }

    // MARK: - The toast

    /// The word in a file name and on a thumbnail. One key, macOS's own word.
    static var thumbnailLabel: String { L("Screenshot") }
    static var saved: String { L("Saved") }
    static var copied: String { L("Copied to the clipboard") }
    static var savedAndCopied: String { L("Saved and copied") }
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
