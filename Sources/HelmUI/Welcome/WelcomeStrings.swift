// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The tour's own words. Every module's name and summary comes from that
/// module's descriptor — a second copy here is nine descriptions that go stale
/// on the first rename.
///
/// **The English and the table are named, not inlined.** Every other string
/// table in Helm spells both into one `L(…)` call, which is fine when the only
/// reader is the screen. These are also read by a test that walks all eight
/// languages looking for a hole, and it cannot do that through an accessor that
/// has already resolved `AppLanguage.current`.
public enum WelcomeStr {
    public static let windowTitleEnglish = "Welcome to Helm"
    public static let windowTitleTable: [AppLanguage: String] = [.ru: "Добро пожаловать в Helm", .es: "Te damos la bienvenida a Helm", .fr: "Bienvenue dans Helm", .de: "Willkommen bei Helm", .ja: "Helm へようこそ", .zh: "欢迎使用 Helm", .pt: "Boas-vindas ao Helm"]
    public static var windowTitle: String { L(windowTitleEnglish, windowTitleTable) }

    public static let introTitleEnglish = "Tools for your Mac"
    public static let introTitleTable: [AppLanguage: String] = [.ru: "Инструменты для вашего Mac", .es: "Herramientas para tu Mac", .fr: "Des outils pour votre Mac", .de: "Werkzeuge für deinen Mac", .ja: "Mac のための道具", .zh: "给你的 Mac 的一套工具", .pt: "Ferramentas para o seu Mac"]
    public static var introTitle: String { L(introTitleEnglish, introTitleTable) }

    public static let introBodyEnglish = "Helm lives in the menu bar and is made of modules. Each one does a single job, and you can switch off the ones you do not want."
    public static let introBodyTable: [AppLanguage: String] = [.ru: "Helm живёт в строке меню и состоит из модулей. Каждый делает одно дело, и ненужные можно выключить.", .es: "Helm vive en la barra de menús y está hecho de módulos. Cada uno hace una sola cosa, y puedes desactivar los que no quieras.", .fr: "Helm vit dans la barre des menus et se compose de modules. Chacun fait une seule chose, et vous pouvez désactiver ceux dont vous ne voulez pas.", .de: "Helm sitzt in der Menüleiste und besteht aus Modulen. Jedes erledigt eine Sache, und was du nicht brauchst, schaltest du ab.", .ja: "Helm はメニューバーに常駐し、モジュールでできています。それぞれが一つの仕事をし、要らないものはオフにできます。", .zh: "Helm 常驻菜单栏，由若干模块组成。每个模块只做一件事，不需要的可以关掉。", .pt: "O Helm fica na barra de menus e é feito de módulos. Cada um faz uma única coisa, e você pode desligar os que não quiser."]
    public static var introBody: String { L(introBodyEnglish, introBodyTable) }

    public static let backEnglish = "Back"
    public static let backTable: [AppLanguage: String] = [.ru: "Назад", .es: "Atrás", .fr: "Précédent", .de: "Zurück", .ja: "戻る", .zh: "上一步", .pt: "Voltar"]
    public static var back: String { L(backEnglish, backTable) }

    public static let nextEnglish = "Next"
    public static let nextTable: [AppLanguage: String] = [.ru: "Далее", .es: "Siguiente", .fr: "Suivant", .de: "Weiter", .ja: "次へ", .zh: "下一步", .pt: "Avançar"]
    public static var next: String { L(nextEnglish, nextTable) }

    public static let skipEnglish = "Skip"
    public static let skipTable: [AppLanguage: String] = [.ru: "Пропустить", .es: "Omitir", .fr: "Ignorer", .de: "Überspringen", .ja: "スキップ", .zh: "跳过", .pt: "Pular"]
    public static var skip: String { L(skipEnglish, skipTable) }

    public static let doneEnglish = "Done"
    public static let doneTable: [AppLanguage: String] = [.ru: "Готово", .es: "Listo", .fr: "Terminé", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "Concluir"]
    public static var done: String { L(doneEnglish, doneTable) }

    /// Read aloud in place of "3 of 10", which VoiceOver otherwise renders as
    /// two bare numbers with no idea what they count.
    public static func stepPosition(_ step: Int, _ total: Int) -> String {
        L("Step \(step) of \(total)", [.ru: "Шаг \(step) из \(total)", .es: "Paso \(step) de \(total)", .fr: "Étape \(step) sur \(total)", .de: "Schritt \(step) von \(total)", .ja: "\(total) 中 \(step) ステップ目", .zh: "第 \(step) 步，共 \(total) 步", .pt: "Passo \(step) de \(total)"])
    }
}
