import Foundation
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

enum ScStr {
    /// macOS's own word for them — «Bildschirmfotos», «Снимки экрана» — read out
    /// of `DefaultShortcutsTable.loctable`, where the same pane is titled.
    static var moduleName: String { L(.moduleName) }
    static var summary: String { L(.summary) }

    static var needsAccess: String {
        L(.needsAccess)
    }

    /// The system's own term, the kit's `HelmWord`, which Keyboard's page reads too.
    static var shortcuts: String { HelmWord.keyboardShortcuts }
    static var captureArea: String { L(.captureArea) }
    static var captureScreen: String { L(.captureScreen) }
    static var openPanel: String { L(.openPanel) }
    static var conflict: String {
        L(.conflict)
    }

    static var systemSection: String { L(.systemSection) }
    /// Over the boxes — ⇧⌘3 and ⇧⌘4, box 184 and a clipboard twin while it conflicts — so the title names none of the
    /// combinations.
    static var replaceTitle: String { L(.replaceTitle) }
    static var replaceBody: String {
        L(.replaceBody)
    }
    static var stillOn: String { L(.stillOn) }
    static var isOff: String { L(.isOff) }
    static var unknown: String { L(.unknown) }
    static var openSystemSettings: String { L(.openSystemSettings) }
    static var useSystemKeys: String { L(.useSystemKeys) }
    /// Its own key and not an interpolation: the three combinations are spelled
    /// whole in each language, and the button that takes ⇧⌘5 as well says so.
    static var useSystemKeysAndPanel: String { L(.useSystemKeysAndPanel) }

    /// The five boxes macOS ticks, in macOS's own words — copied out of the
    /// Keyboard settings extension's `DefaultShortcutsTable.loctable`, which is
    /// where the list Helm sends a person to draws them.
    static func boxName(_ box: SystemBox) -> String {
        switch box {
        case .saveScreen: L(.boxSaveScreen)
        case .saveArea: L(.boxSaveArea)
        case .copyScreen: L(.boxCopyScreen)
        case .copyArea: L(.boxCopyArea)
        case .panel: L(.boxPanel)
        }
    }

    /// Under macOS's box 184, which is ⇧⌘5: that shortcut is also how screen
    /// recording is reached from the keyboard, and Helm has no recording.
    static var panelBoxWarning: String {
        L(.panelBoxWarning)
    }

    /// macOS's own words for the bar — the tooltips of its three capture buttons,
    /// «Options», «Timer», «Capture», «Show Floating Thumbnail» and «Remember Last
    /// Selection» — read out of `screencaptureui`'s `Localizable.loctable`.
    static var panelScreen: String { L(.panelScreen) }
    static var panelWindow: String { L(.panelWindow) }
    static var panelArea: String { L(.panelArea) }
    static var captureButton: String { L(.captureButton) }
    static var options: String { L(.options) }
    static var timer: String { HelmWord.timer }
    static func timer(_ timer: CaptureTimer) -> String {
        switch timer {
        case .none: L(.timerNone)
        case .five: L(.timerFive)
        case .ten: L(.timerTen)
        case .thirty: L(.timerThirty)
        }
    }
    /// The timer cell's name while the timer is on: «Timer: 5 seconds». Off, the cell is named `timer`. The length is
    /// the one argument, so the word order is the translator's and not a concatenation's.
    static func timerOn(_ timer: CaptureTimer) -> String { L(.timerOn(Self.timer(timer))) }
    static var putPanelBack: String { L(.putPanelBack) }
    static var floatingThumbnail: String { L(.floatingThumbnail) }
    static var rememberSelection: String { L(.rememberSelection) }
    static var closePanel: String { HelmWord.close }

    /// macOS's own words — Save to, Desktop, Documents, Clipboard, Other… — read
    /// out of `screencaptureui`'s `Localizable.loctable`, where the same menu is drawn.
    static var saveTo: String { L(.saveTo) }
    static var targetMacOS: String { L(.targetMacOS) }
    static var targetDesktop: String { L(.targetDesktop) }
    static var targetDocuments: String { L(.targetDocuments) }
    static var targetClipboard: String { HelmWord.clipboard }
    /// Its own key, not KeepAwake's «Other…»: one key means one thing, and
    /// Portuguese says «Outra» for a folder where a duration is «Outro».
    /// The seven translations are macOS's «Other…» from the same table.
    static var targetOther: String { L(.targetOther) }
    static func target(_ target: SaveTarget) -> String {
        switch target {
        case .macOS: targetMacOS
        case .desktop: targetDesktop
        case .documents: targetDocuments
        case .clipboard: targetClipboard
        case .other: targetOther
        }
    }

    static var format: String { L(.format) }
    /// File-format names: the same letters in every language.
    static func format(_ format: ShotFormat) -> String {
        switch format {
        case .png: L(.formatPNG)
        case .jpeg: L(.formatJPEG)
        }
    }
    static var shutterSound: String { L(.shutterSound) }
    static var showCursor: String { L(.showCursor) }
    /// One key for the two things «Choose…» opens: a folder and the palette's tools.
    static var choose: String { HelmWord.choose }
    static var chooseFolder: String { choose }

    static var folder: String { L(.folder) }
    static var folderNote: String { L(.folderNote) }
    static var folderRefused: String {
        L(.folderRefused)
    }
    static var chosenRefused: String {
        L(.chosenRefused)
    }

    // MARK: - The settings tabs and the editor's settings

    /// The first tab, the gerund: `captureButton` is the verb of the panel's button.
    static var tabCapturing: String { L(.tabCapturing) }
    static var tabEditor: String { L(.tabEditor) }
    /// `Colour` is already the adjective of «Colour» printing, so the row has its own key.
    static var defaultColour: String { L(.defaultColour) }
    static var defaultColourNote: String {
        L(.defaultColourNote)
    }
    static var toolsInPalette: String { L(.toolsInPalette) }
    /// The ⋯ is the menu button's own name; each language's table quotes it as that language does.
    static var hiddenToolsNote: String { L(.hiddenToolsNote) }
    /// Counted from the palette's list, never written: the first number is what the row shows.
    static func toolsShown(_ shown: Int, of all: Int, language: AppLanguage = AppLanguage.current) -> String {
        let (n, m) = (Count(shown, language: language), Count(all, language: language))
        return L(.toolsShown(n, m), language: language)
    }
    /// Under «Show floating thumbnail»: where it stands and what several of them do.
    static var thumbnailNote: String { L(.thumbnailNote) }

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
    /// «Magnifier» is the lens Preview's markup calls «Loupe» in English: `AnnotationKit.framework`'s `AnnotationStrings.loctable`, key
    /// `LOUPE_ANNOTATION_NAME` (Lupe, Lupa, Loupe, ルーペ, Lupa, Лупа, 放大镜; its pt_BR and pt_PT agree). «Emoji» is the first word of
    /// AppKit's «Emoji & Symbols» (key `Emoji & Symbols` of `InputManager.loctable`: Emoji, Emojis, Emoji, 絵文字, Emoji, Эмодзи, 表情) in German,
    /// French, Japanese, Portuguese and Russian; the Spanish (Emoji) and the Chinese (表情符号) are Helm's own.
    static func tool(_ tool: AnnotationTool) -> String {
        switch tool {
        case .arrow: L(.toolArrow)
        case .rectangle: L(.toolRectangle)
        case .ellipse: L(.toolEllipse)
        case .line: L(.toolLine)
        case .pen: L(.toolPen)
        case .pencil: L(.toolPencil)
        case .highlighter: L(.toolHighlighter)
        case .blur: L(.toolBlur)
        case .text: L(.toolText)
        case .step: L(.toolStep)
        case .spotlight: L(.toolSpotlight)
        case .magnifier: L(.toolMagnifier)
        case .emoji: L(.toolEmoji)
        }
    }

    /// The eraser's name, which is no tool's: the word of `PaperKit.framework`'s `Localizable.loctable`, key `Eraser` (Eraser, Radiergummi,
    /// Borrador, Gomme, 消しゴム, Borracha, Ластик, 橡皮擦); `PencilKit.framework`'s table has «Object Eraser» and «Pixel Eraser» and no bare `Eraser`.
    static var eraser: String { L(.eraser) }

    /// The ruler's name: key `Ruler` of `PencilKit.framework`'s `Localizable.loctable` (Ruler, Lineal, Regla, Règle, 定規, Régua, Линейка, 标尺); `PaperKit.framework`'s table
    /// has no such key. The Portuguese is the table's `pt_BR`, which `pt_PT` repeats.
    static var ruler: String { L(.ruler) }

    /// The colours: the six Helm's palette already names, and «Black» is named in AppKit's colour panel table (`NSColorPanelExtras.loctable`), and both it and «White» in the system colour list (`Apple.clr/Apple.loctable`); in Japanese both are the system colour list's words (ブラック, ホワイト).
    static func ink(_ color: AnnotationColor) -> String {
        switch color {
        case .red: HelmWord.red
        case .orange: HelmWord.orange
        case .yellow: HelmWord.yellow
        case .green: HelmWord.green
        case .blue: HelmWord.blue
        case .purple: HelmWord.purple
        case .black: L(.inkBlack)
        case .white: HelmWord.white
        }
    }

    /// The pop-over's two rows, in macOS's own words: «Thickness» is key `Thickness` of Preview's `Localizable.loctable`
    /// (Stärke, Grosor, Épaisseur, 太さ, Espessura, Толщина, 粗细) and «Opacity» key `Opacity` of `PaperKit.framework`'s
    /// `Localizable.loctable` and of AppKit's `NSColorPanelExtras.loctable` (Deckkraft, Opacidad, Opacité, 不透明度,
    /// Opacidade, Непрозрачность, 不透明度); Chinese is the tables' `zh_CN`, and their `pt_BR` and `pt_PT` agree.
    static var thicknessLabel: String { L(.thicknessLabel) }
    static var opacityLabel: String { L(.opacityLabel) }
    /// The ⋯ menu's item that opens the pop-over. No table has the phrase: it is the two words above joined by the
    /// language's «and», with the ellipsis of an item that opens something.
    static var thicknessAndOpacity: String { L(.thicknessAndOpacity) }

    /// The colour wheel's name. No table has the phrase («All Colors» is in none of AppKit's colour loctables, nor
    /// PaperKit's): it is «all» before the word the colour panel uses, `Colors` of `NSColorPanelExtras.loctable` (Farben,
    /// Colores, Couleurs, カラー, Цвета, 颜色, Cores), so Japanese keeps the panel's カラー and Chinese its 颜色.
    static var allColours: String { L(.allColours) }

    /// The eyedropper's name. Helm's own words: measured, no table macOS displays carries it; the word occurs only in accessibility
    /// tables (the symbol's name in `AccessibilitySharedSupport`'s symbol-names table, and `DesktopServicesUI`'s `Localizable` table under
    /// an accessibility key).
    static var eyedropper: String { L(.eyedropper) }

    /// The name of a thickness step, which the pop-over says beside its slider (the frame's «Средняя»).
    static func thickness(_ step: AnnotationThickness) -> String {
        switch step {
        case .thin: L(.thicknessThin)
        case .medium: L(.thicknessMedium)
        case .thick: L(.thicknessThick)
        }
    }

    /// Fill and Save are items of the ⋯ menu (Fill inside Shapes); Copy is the capsule's cell, read in `ScStr.copy`. Pin is read by the ⋯ menu's Pin item and by the thumbnail capsule's Pin cell, while `PinEntry.isOffered`.
    static var fill: String { L(.fill) }
    /// The submenu of the ⋯ menu that holds the shapes, and the pointer's item: Preview's own words: the
    /// selection tool is the noun «Выбор», key `Selection` of Preview's `DFR-BBBAA77A32-C4EBFEA440.loctable`, and the
    /// shapes are key `TB_USD_Shapes` of its `Localizable.loctable`.
    static var shapes: String { L(.shapes) }
    static var select: String { L(.select) }
    /// The ⋯ menu's Crop, a mode of the editor and no tool: Preview's inspector toolbar item, key `PVInspectorCrop` of its
    /// `Localizable.loctable` (Обрезка, Zuschneiden, Recortar, Recadrer, 切り取り, Recortar, 裁剪), the noun as Select is.
    static var crop: String { L(.crop) }
    /// Preview's «Undo» and «Redo».
    static var undo: String { L(.undo) }
    static var redo: String { L(.redo) }
    /// Preview's «Save».
    static var save: String { L(.save) }
    static var closeEditor: String { HelmWord.close }
    /// The editor's checkmark: what Return does.
    static var done: String { HelmWord.done }
    /// The editor's Pin item on the ⋯ menu, which keeps the picture on the screen as a window.
    static var pin: String { L(.pin) }
    /// The plate at the limit of open pins; no number, so no argument.
    static var pinLimit: String { L(.pinLimit) }
    /// Copy Text: the word of `VisionKitCore.framework`'s `Localizable.loctable`, key `VK_COPY_TEXT_MENU_ITEM_TITLE`, which is Live Text's menu item
    /// (Text kopieren, Copiar texto, Copier le texte, テキストをコピー, Copiar texto, Скопировать текст, 拷贝文本; its Portuguese is the `pt_PT` table's, since `pt_BR` capitalises it).
    static var copyText: String { L(.copyText) }
    /// What it blurs is the four kinds in the hint: the name says less than the item does.
    static var blurPersonalText: String { L(.blurPersonalText) }
    /// The item's hint: the whole list of what is found, and what is not. A kind added later is a new key.
    static var blurPersonalTextHint: String {
        L(.blurPersonalTextHint)
    }
    /// The plates after a reading say what was **done**, never what the picture now is: no word for safe, hidden or clean, and a zero is not good news.
    static var nothingBlurred: String { L(.nothingBlurred) }
    static var textCopied: String { L(.textCopied) }
    static var noTextFound: String { L(.noTextFound) }
    static var textUnreadable: String { L(.textUnreadable) }
    /// A count after a colon takes no form of a noun, so no plural helper; the digits are grouped as the language groups them.
    static func blurred(_ count: Int, language: AppLanguage = AppLanguage.current) -> String {
        let n = HelmBytes.grouped(count, language: language.rawValue)
        return L(.blurred(n), language: language)
    }
    /// What a screen reader calls a pin.
    static var pinnedScreenshot: String { L(.pinnedScreenshot) }

    // MARK: - The toast

    /// The word on a thumbnail, macOS's own; a file name's word is inside `nameTemplate`.
    static var thumbnailLabel: String { L(.thumbnailLabel) }
    /// The capsule over a thumbnail: the clipboard's own word, and Finder's.
    static var edit: String { HelmWord.edit }
    static var copy: String { HelmWord.copy }
    static var showInFinder: String { HelmWord.showInFinder }
    /// The pile's capsule, the label on the row's farthest whole shot, and what a screen reader calls the pile. The
    /// count is interpolated; the verb is the kit's
    /// (`Copy`) and the noun the catalog's (`moduleName`). A pile is two shots or more; «N more» counts one as well, so
    /// the counted forms are written so that none needs a plural: German's «weitere» is wrong for one, and «mehr»
    /// is right for every count.
    static func copyAll(_ count: Int) -> String {
        L(.copyAll(String(count)))
    }
    static func more(_ count: Int) -> String {
        L(.more(String(count)))
    }
    static func screenshots(_ count: Int) -> String {
        L(.screenshots(String(count)))
    }
    /// The ⋯ menu's Share item, which opens the system's sheet at the thumbnail.
    static var share: String { L(.share) }
    static var saved: String { L(.saved) }
    static var copied: String { L(.copied) }
    static var savedAndCopied: String { L(.savedAndCopied) }
    /// What a screen reader reads of a thumbnail whose edit took its original's place.
    static var replaced: String { L(.replaced) }
    /// The plate over an edited picture after a first Esc.
    static var confirmClose: String { L(.confirmClose) }
    static var dismissToast: String { HelmWord.close }
    static var openSettings: String { L(.openSettings) }
    static var noPermissionTitle: String { L(.noPermissionTitle) }
    static var noPermissionBody: String {
        L(.noPermissionBody)
    }
    static var failedTitle: String { L(.failedTitle) }

    /// One sentence per thing that can go wrong, and none of them carries a path.
    static func refusal(_ reason: CaptureRefusal) -> String {
        switch reason {
        case .noPermission: noPermissionBody
        case .captureFailed: L(.refusalCaptureFailed)
        case .displayGone: L(.refusalDisplayGone)
        case .windowGone: L(.refusalWindowGone)
        case .write(.noFolder), .write(.notAFolder): L(.refusalNoFolder)
        case .write(.noPermission): L(.refusalNoWritePermission)
        case .write(.diskFull): L(.refusalDiskFull)
        case .write(.namesExhausted), .write(.failed): L(.refusalNotSaved)
        case .pasteboard: L(.refusalPasteboard)
        case .encoding: L(.refusalEncoding)
        case .notEditable:
            L(.refusalNotEditable)
        // The Trash's own two words for a file that is not where it was end by naming a «Scan again» control,
        // which this module has none of: they are this module's sentence, and the one sentence also says it for a
        // folder that took no write: the person is told that the edit is a separate file, not why.
        case .notReplaced(.missing), .notReplaced(.changed), .notReplaced(.folderRefused),
             .notReplaced(.trash(.missing)), .notReplaced(.trash(.changedSinceScan)):
            L(.refusalNotReplaced)
        case .notReplaced(.trash(let reason)): TrashReasonText.sentence(reason.rawValue)
        }
    }

    /// macOS's own file-name template, with its word already in it. The two `%@` are handed
    /// back as they are: `ShotNames.base` fills them. The catalog's English is the pattern and the
    /// seven translations are copied out of `screencaptureui`'s `Localizable.loctable` — the
    /// template for the order of the parts and the word for the noun — at development time.
    static var nameTemplate: String { L(.nameTemplate("%@", "%@")) }

    /// The word is Helm's language and the clock is the system's region, both
    /// at once: macOS names its own files by the hour cycle of the region, and a
    /// person who has both expects the same file names from both — but a file
    /// called "Screenshot … at 오후 10.25.33" is half of each. The locale is the
    /// language Helm is speaking in the region the Mac is set to, so the
    /// day-period marker comes in the word's language and the hour cycle in the
    /// region's.
    static var naming: ShotNaming {
        ShotNaming(template: nameTemplate, locale: fileNameLocale(language: .current, system: .current))
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
