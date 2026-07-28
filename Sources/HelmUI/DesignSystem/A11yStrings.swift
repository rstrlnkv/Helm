import Foundation

/// Names for controls that show only an icon.
///
/// `.help()` fills `accessibilityHelp`, which is a hint — it does not name the
/// control. Without a label these read as "button" in the rotor and in the item
/// chooser, so a row with a remove button and an actions menu offered VoiceOver
/// two anonymous buttons and no way to tell them apart.
///
/// They live in `HelmUI` because the same four controls appear in four modules
/// and in the host app, and a label that differs per module is the same defect
/// in a nicer costume.
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
}
