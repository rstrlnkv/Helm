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
        case .thirty: L("30 seconds")
        }
    }
    /// The timer cell's name while the timer is on: «Timer: 5 seconds». Off, the cell is named `timer`. The length is
    /// the one argument, so the word order is the translator's and not a concatenation's.
    static func timerOn(_ timer: CaptureTimer) -> String { String(format: L("Timer: %@"), Self.timer(timer)) }
    static var putPanelBack: String { L("Put the Panel Back") }
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
    /// One key for the two things «Choose…» opens: a folder and the palette's tools.
    static var choose: String { L("Choose…") }
    static var chooseFolder: String { choose }

    static var folder: String { L("Save folder") }
    static var folderNote: String { L("Where macOS keeps screenshots. Helm reads it and never changes it.") }
    static var folderRefused: String {
        L("The folder macOS names cannot be used, so Helm saves to the Desktop.")
    }
    static var chosenRefused: String {
        L("That folder cannot be used, so Helm saves to the Desktop.")
    }

    // MARK: - The settings tabs and the editor's settings

    /// The first tab, the gerund: `Capture` is the verb of the panel's button.
    static var tabCapturing: String { L("Capturing") }
    static var tabEditor: String { L("Editor") }
    /// `Colour` is already the adjective of «Colour» printing, so the row has its own key.
    static var defaultColour: String { L("Default colour") }
    static var defaultColourNote: String {
        L("Until a colour is picked, each tool has its own: red, and yellow for the highlighter.")
    }
    static var toolsInPalette: String { L("Tools in the palette") }
    /// The ⋯ is the menu button's own name; each language's table quotes it as that language does.
    static var hiddenToolsNote: String { L("Hidden tools move to the ⋯ menu and still answer to their keys.") }
    /// Counted from the palette's list, never written: the first number is what the row shows.
    static func toolsShown(_ shown: Int, of all: Int, language: AppLanguage = AppLanguage.current) -> String {
        let (n, m) = (Count(shown, language: language), Count(all, language: language))
        return L("\(n) of \(m)", [.ru: "\(n) из \(m)", .es: "\(n) de \(m)", .fr: "\(n) sur \(m)", .de: "\(n) von \(m)",
                                  .ja: "\(m) 個中 \(n) 個", .zh: "\(m) 个中的 \(n) 个", .pt: "\(n) de \(m)"], language: language)
    }
    /// Under «Show floating thumbnail»: where it stands and what several of them do.
    static var thumbnailNote: String { L("Lower right. Shots taken one after another stack up.") }

    // MARK: - The palette, its menu and pop-overs

    /// The tools, in the words of macOS's own Preview markup menu; the ellipse is
    /// «Oval» there, and «Highlight» was its marker. «Pen» and «Marker» are the ones the system's PencilKit says:
    /// keys `Pen` and `Marker` of `PencilKit.framework`'s `Localizable.loctable` (Pen: Stift, Bolígrafo, Stylo, ペン, Caneta, Перо, 笔;
    /// Marker: Marker, Marcador, Marqueur, マーカー, Marcador, Маркер, 马克笔); no table of Preview, Markup or AnnotationKit has the word.
    /// «Text» is the word of Preview's toolbar: key `TB_text` of `Preview.app`'s `Localizable.loctable` (Text, Text, Texto, Texte, テキスト,
    /// Texto, Текст, 文本), the same in `AnnotationKit.framework`'s `AKToolbarViewController.loctable` under `Text`.
    /// «Spotlight» is the stage light's word in `PhotosFormats.framework`'s `scenetaxonomy.loctable`, key `spotlight` (Spotlight, Spotlight,
    /// Foco, Projecteur, スポットライト, Holofote, Прожектор, 聚光灯), the same in `IMCore.framework`'s `IMCoreLocalizable.loctable`.
    /// «Steps» has no such word for numbered marks: the system tables say it of footsteps (`Intents.framework`'s `Localizable.loctable`, key
    /// `com.apple.intents.WorkoutNameIdentifier.Steps`: Schritte, Pasos, Pas, ステップ, Passos, Шаги, 步数), so the German, Spanish,
    /// Japanese, Portuguese and Russian are that table's word and the French (Étapes) and the Chinese (步骤) are Helm's own.
    static func tool(_ tool: AnnotationTool) -> String {
        switch tool {
        case .arrow: L("Arrow")
        case .rectangle: L("Rectangle")
        case .ellipse: L("Oval")
        case .line: L("Line")
        case .pen: L("Pen")
        case .pencil: L("Pencil")
        case .highlighter: L("Highlighter")
        case .blur: L("Blur")
        case .text: L("Text")
        case .step: L("Steps")
        case .spotlight: L("Spotlight")
        }
    }

    /// The eraser's name, which is no tool's: the word of `PaperKit.framework`'s `Localizable.loctable`, key `Eraser` (Eraser, Radiergummi,
    /// Borrador, Gomme, 消しゴム, Borracha, Ластик, 橡皮擦); `PencilKit.framework`'s table has «Object Eraser» and «Pixel Eraser» and no bare `Eraser`.
    static var eraser: String { L("Eraser") }

    /// The ruler's name: key `Ruler` of `PencilKit.framework`'s `Localizable.loctable` (Ruler, Lineal, Regla, Règle, 定規, Régua, Линейка, 标尺); `PaperKit.framework`'s table
    /// has no such key. The Portuguese is the table's `pt_BR`, which `pt_PT` repeats.
    static var ruler: String { L("Ruler") }

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

    /// The pop-over's two rows, in macOS's own words: «Thickness» is key `Thickness` of Preview's `Localizable.loctable`
    /// (Stärke, Grosor, Épaisseur, 太さ, Espessura, Толщина, 粗细) and «Opacity» key `Opacity` of `PaperKit.framework`'s
    /// `Localizable.loctable` and of AppKit's `NSColorPanelExtras.loctable` (Deckkraft, Opacidad, Opacité, 不透明度,
    /// Opacidade, Непрозрачность, 不透明度); Chinese is the tables' `zh_CN`, and their `pt_BR` and `pt_PT` agree.
    static var thicknessLabel: String { L("Thickness") }
    static var opacityLabel: String { L("Opacity") }
    /// The ⋯ menu's item that opens the pop-over. No table has the phrase: it is the two words above joined by the
    /// language's «and», with the ellipsis of an item that opens something.
    static var thicknessAndOpacity: String { L("Thickness and Opacity…") }

    /// The colour wheel's name. No table has the phrase («All Colors» is in none of AppKit's colour loctables, nor
    /// PaperKit's): it is «all» before the word the colour panel uses, `Colors` of `NSColorPanelExtras.loctable` (Farben,
    /// Colores, Couleurs, カラー, Цвета, 颜色, Cores), so Japanese keeps the panel's カラー and Chinese its 颜色.
    static var allColours: String { L("All Colours") }

    /// The name of a thickness step, which the pop-over says beside its slider (the frame's «Средняя»).
    static func thickness(_ step: AnnotationThickness) -> String {
        switch step {
        case .thin: L("Thin")
        case .medium: L("Medium")
        case .thick: L("Thick")
        }
    }

    /// Fill and Save are items of the ⋯ menu (Fill inside Shapes); Copy has no control on the palette yet, and its name
    /// is kept for the one that comes. Pin is read by the ⋯ menu's Pin item while `PinEntry.isOffered`.
    static var fill: String { L("Filled") }
    /// The submenu of the ⋯ menu that holds the shapes, and the pointer's item: Preview's own words: the
    /// selection tool is the noun «Выбор», key `Selection` of Preview's `DFR-BBBAA77A32-C4EBFEA440.loctable`, and the
    /// shapes are key `TB_USD_Shapes` of its `Localizable.loctable`.
    static var shapes: String { L("Shapes") }
    static var select: String { L("Select") }
    /// The ⋯ menu's Crop, a mode of the editor and no tool: Preview's inspector toolbar item, key `PVInspectorCrop` of its
    /// `Localizable.loctable` (Обрезка, Zuschneiden, Recortar, Recadrer, 切り取り, Recortar, 裁剪), the noun as Select is.
    static var crop: String { L("Crop") }
    /// Preview's «Undo» and «Redo».
    static var undo: String { L("Undo") }
    static var redo: String { L("Redo") }
    /// Preview's «Save».
    static var save: String { L("Save") }
    static var closeEditor: String { L("Close") }
    /// The editor's checkmark: what Return does.
    static var done: String { L("Done") }
    /// The editor's Pin item on the ⋯ menu, which keeps the picture on the screen as a window.
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
