import Foundation

/// Names for controls that show only an icon.
///
/// `.help()` fills `accessibilityHelp`, which is a hint — it does not name the
/// control. Without a label these read as "button" in the rotor and in the item
/// chooser, so a row with a remove button and an actions menu offered VoiceOver
/// two anonymous buttons and no way to tell them apart.
///
/// They live in `HelmUI` because the same controls appear across seven modules
/// and the host app, and a label that differs per module is the same defect in
/// a nicer costume. No count here: it was "four controls in four modules" when
/// it was written and is neither now, which is what a number in a comment does.
public enum HelmA11y {
    public static var moveUp: String {
        L("Move up", [.ru: "Переместить вверх", .es: "Mover arriba", .fr: "Monter", .de: "Nach oben", .ja: "上へ移動", .zh: "上移", .pt: "Mover para cima"])
    }
    public static var moveDown: String {
        L("Move down", [.ru: "Переместить вниз", .es: "Mover abajo", .fr: "Descendre", .de: "Nach unten", .ja: "下へ移動", .zh: "下移", .pt: "Mover para baixo"])
    }
    public static var remove: String {
        L("Remove", [.ru: "Убрать", .es: "Quitar", .fr: "Retirer", .de: "Entfernen", .ja: "削除", .zh: "移除", .pt: "Remover"])
    }
    public static var moreActions: String {
        L("More actions", [.ru: "Ещё действия", .es: "Más acciones", .fr: "Plus d’actions", .de: "Weitere Aktionen", .ja: "その他の操作", .zh: "更多操作", .pt: "Mais ações"])
    }
    public static var showInFinder: String {
        L("Show in Finder", [.ru: "Показать в Finder", .es: "Mostrar en el Finder", .fr: "Afficher dans le Finder", .de: "Im Finder zeigen", .ja: "Finderに表示", .zh: "在访达中显示", .pt: "Mostrar no Finder"])
    }

    /// A segmented picker that narrows what a list is showing. Three modules
    /// have one and none of them labelled it, because on screen the segments
    /// say everything — "Installed / Updates / Search" needs no heading above
    /// it. Read aloud it was a tab group with no name.
    public static var whatToShow: String {
        L("What to show", [.ru: "Что показывать", .es: "Qué mostrar", .fr: "Ce qui est affiché", .de: "Was angezeigt wird", .ja: "表示する内容", .zh: "显示内容", .pt: "O que mostrar"])
    }
    /// A number typed into a field whose unit is a separate label beside it,
    /// which VoiceOver reads as a neighbour rather than as part of the value.
    public static var minutes: String {
        L("Minutes", [.ru: "Минуты", .es: "Minutos", .fr: "Minutes", .de: "Minuten", .ja: "分", .zh: "分钟", .pt: "Minutos"])
    }

    /// Whether a disclosure is open. SwiftUI has no trait for it on macOS — the
    /// rotor gets `.isButton` and nothing else — so the state has to be said,
    /// and a control whose whole purpose is to open and close must say it.
    ///
    /// Read out of the system's own tables rather than translated: searching
    /// every `.loctable` macOS ships for the strings whose English is
    /// "expanded" / "collapsed" gives seven of the eight. Four of the first
    /// attempt's eight guesses were wrong — French says *condensé*, not
    /// *réduit*; Japanese says 折りたたまれています, not 閉じています; Russian
    /// spells it without the ё it is normally written with.
    ///
    /// Portuguese is the exception: no system table carries it, so it is a
    /// translation, and it is the only one here that is.
    public static func expanded(_ isExpanded: Bool) -> String {
        isExpanded
            ? L("expanded", [.ru: "развернуто", .es: "expandido", .fr: "développé",
                             .de: "erweitert", .ja: "展開されています", .zh: "已展开",
                             .pt: "expandido"])
            : L("collapsed", [.ru: "свернуто", .es: "contraído", .fr: "condensé",
                              .de: "reduziert", .ja: "折りたたまれています", .zh: "已折叠",
                              .pt: "recolhido"])
    }
}
