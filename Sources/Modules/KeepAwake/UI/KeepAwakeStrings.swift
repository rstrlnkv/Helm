import HelmUI

/// Localized strings for the Keep Awake module UI. English is the base; the
/// tables carry zh/es/fr/de/ja/ru/pt.
enum KAStr {
    static var moduleName: String {
        L("Keep Awake", [.ru: "Не спать", .es: "Mantener activo", .fr: "Rester éveillé",
                         .de: "Wach halten", .ja: "スリープ防止", .zh: "保持唤醒", .pt: "Manter ativo"])
    }
    static var summary: String {
        L("Keep the Mac from falling asleep.",
          [.ru: "Не давать Mac засыпать.", .es: "Evitar que el Mac se duerma.",
           .fr: "Empêcher le Mac de s’endormir.", .de: "Den Mac wach halten.",
           .ja: "Mac をスリープさせない。", .zh: "阻止 Mac 进入睡眠。",
           .pt: "Impedir que o Mac durma."])
    }
    /// Window title: no ellipsis — that belongs to the menu entry that opens it.
    static var customTimeTitle: String { L("Custom duration", [.ru: "Своё время", .es: "Duración personalizada", .fr: "Durée personnalisée", .de: "Eigene Dauer", .ja: "カスタム時間", .zh: "自定义时长", .pt: "Duração personalizada"]) }
    static var customTime: String { L("Custom…", [.ru: "Своё время…", .es: "Personalizado…", .fr: "Personnalisé…", .de: "Eigene Zeit…", .ja: "カスタム…", .zh: "自定义…", .pt: "Personalizado…"]) }
    static var done: String { L("Done", [.ru: "Готово", .es: "Listo", .fr: "OK", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "OK"]) }
    /// Short forms used under the "Automatically" heading, where the context is
    /// already given by the group title.
    static var onExternalDisplay: String { L("With an external display", [.ru: "При внешнем дисплее", .es: "Con pantalla externa", .fr: "Avec un écran externe", .de: "Mit externem Bildschirm", .ja: "外部ディスプレイ接続時", .zh: "连接外接显示器时", .pt: "Com tela externa"]) }
    static var onPower: String { L("On power", [.ru: "При питании", .es: "Con corriente", .fr: "Sur secteur", .de: "Am Netzstrom", .ja: "電源接続時", .zh: "接通电源时", .pt: "Na tomada"]) }
    static var timer: String { L("Timer", [.ru: "Таймер", .es: "Temporizador", .fr: "Minuteur", .de: "Timer", .ja: "タイマー", .zh: "计时器", .pt: "Timer"]) }
    static var start: String {
        L("Start", [.ru: "Старт", .es: "Iniciar", .fr: "Démarrer", .de: "Start", .ja: "開始", .zh: "开始", .pt: "Iniciar"])
    }
    static var stop: String {
        L("Stop", [.ru: "Стоп", .es: "Detener", .fr: "Arrêter", .de: "Stopp", .ja: "停止", .zh: "停止", .pt: "Parar"])
    }
    /// Single-letter units for the narrow preset pills ("15 м", "1 ч").
    static var minutesUnitShort: String {
        L("m", [.ru: "м", .es: "m", .fr: "m", .de: "M", .ja: "分", .zh: "分", .pt: "m"])
    }
    static var hoursUnitShort: String {
        L("h", [.ru: "ч", .es: "h", .fr: "h", .de: "Std", .ja: "時", .zh: "时", .pt: "h"])
    }
    static var hoursUnit: String {
        L("h", [.ru: "ч", .es: "h", .fr: "h", .de: "Std.", .ja: "時間", .zh: "小时", .pt: "h"])
    }
    static var minutesUnit: String {
        L("min", [.ru: "мин", .es: "min", .fr: "min", .de: "Min.", .ja: "分", .zh: "分钟", .pt: "min"])
    }
    static var lidClosed: String {
        L("Lid closed — staying awake",
          [.ru: "Крышка закрыта — не спит", .es: "Tapa cerrada — sigue activo",
           .fr: "Capot fermé — reste éveillé", .de: "Deckel zu — bleibt wach",
           .ja: "ふたを閉じても起動継続", .zh: "合盖仍保持唤醒", .pt: "Tampa fechada — continua ativo"])
    }

    static func condition(_ wire: String) -> String {
        switch wire {
        case "manual": return L("Manual", [.ru: "Вручную", .es: "Manual", .fr: "Manuel", .de: "Manuell", .ja: "手動", .zh: "手动", .pt: "Manual"])
        case "timer": return L("Timer", [.ru: "Таймер", .es: "Temporizador", .fr: "Minuteur", .de: "Timer", .ja: "タイマー", .zh: "计时器", .pt: "Temporizador"])
        case "externalDisplay": return L("External display", [.ru: "Внешний дисплей", .es: "Pantalla externa", .fr: "Écran externe", .de: "Externer Bildschirm", .ja: "外部ディスプレイ", .zh: "外接显示器", .pt: "Tela externa"])
        case "power": return L("Power", [.ru: "Питание", .es: "Corriente", .fr: "Secteur", .de: "Netzstrom", .ja: "電源", .zh: "电源", .pt: "Energia"])
        case "app": return L("App", [.ru: "Приложение", .es: "App", .fr: "App", .de: "App", .ja: "アプリ", .zh: "应用", .pt: "App"])
        default: return wire
        }
    }

    // MARK: - Settings

    static var automation: String { L("Automation", [.ru: "Автоматизация", .es: "Automatización", .fr: "Automatisation", .de: "Automatisierung", .ja: "自動化", .zh: "自动化", .pt: "Automação"]) }
    static var withExternalDisplay: String { L("Keep awake with external display", [.ru: "Не спать при внешнем дисплее", .es: "Mantener activo con pantalla externa", .fr: "Rester éveillé avec un écran externe", .de: "Mit externem Bildschirm wach halten", .ja: "外部ディスプレイ接続中はスリープ防止", .zh: "连接外接显示器时保持唤醒", .pt: "Manter ativo com tela externa"]) }
    static var whileOnPower: String { L("Keep awake while on power", [.ru: "Не спать при питании", .es: "Mantener activo con corriente", .fr: "Rester éveillé sur secteur", .de: "Am Netzstrom wach halten", .ja: "電源接続中はスリープ防止", .zh: "接通电源时保持唤醒", .pt: "Manter ativo na tomada"]) }
    static var appsSection: String { L("Apps that keep the Mac awake", [.ru: "Приложения, не дающие спать", .es: "Apps que mantienen activo el Mac", .fr: "Apps qui gardent le Mac éveillé", .de: "Apps, die den Mac wach halten", .ja: "Mac を起動させ続けるアプリ", .zh: "保持 Mac 唤醒的应用", .pt: "Apps que mantêm o Mac ativo"]) }
    static var behavior: String { L("Behavior", [.ru: "Поведение", .es: "Comportamiento", .fr: "Comportement", .de: "Verhalten", .ja: "動作", .zh: "行为", .pt: "Comportamento"]) }
    static var keepDisplayOn: String { L("Keep display on", [.ru: "Держать дисплей включённым", .es: "Mantener la pantalla encendida", .fr: "Garder l’écran allumé", .de: "Bildschirm anlassen", .ja: "ディスプレイを点灯したまま", .zh: "保持显示器常亮", .pt: "Manter a tela ligada"]) }
    static var movePointer: String { L("Move pointer periodically", [.ru: "Периодически двигать указателем", .es: "Mover el puntero periódicamente", .fr: "Déplacer le pointeur régulièrement", .de: "Zeiger regelmäßig bewegen", .ja: "定期的にポインタを動かす", .zh: "定期移动指针", .pt: "Mover o ponteiro periodicamente"]) }
    static func everyMinutes(_ n: Int) -> String { L("Every \(n) min", [.ru: "Каждые \(n) мин", .es: "Cada \(n) min", .fr: "Toutes les \(n) min", .de: "Alle \(n) Min.", .ja: "\(n) 分ごと", .zh: "每 \(n) 分钟", .pt: "A cada \(n) min"]) }
    static var defaultDuration: String { L("Default duration", [.ru: "Длительность по умолчанию", .es: "Duración por defecto", .fr: "Durée par défaut", .de: "Standarddauer", .ja: "デフォルトの継続時間", .zh: "默认时长", .pt: "Duração padrão"]) }
    static var oneHour: String { L("1 hour", [.ru: "1 час", .es: "1 hora", .fr: "1 heure", .de: "1 Stunde", .ja: "1 時間", .zh: "1 小时", .pt: "1 hora"]) }
    static var twoHours: String { L("2 hours", [.ru: "2 часа", .es: "2 horas", .fr: "2 heures", .de: "2 Stunden", .ja: "2 時間", .zh: "2 小时", .pt: "2 horas"]) }
    static var indefinite: String { L("Indefinite", [.ru: "Бессрочно", .es: "Indefinido", .fr: "Illimité", .de: "Unbegrenzt", .ja: "無期限", .zh: "无限期", .pt: "Indefinido"]) }
    static var pointerNeedsAccessibility: String { L("Needs Accessibility, or the pointer will not move.", [.ru: "Нужен «Универсальный доступ», иначе указатель не двинется.", .es: "Requiere Accesibilidad; si no, el puntero no se moverá.", .fr: "Nécessite l’Accessibilité, sinon le pointeur ne bougera pas.", .de: "Benötigt Bedienungshilfen, sonst bewegt sich der Zeiger nicht.", .ja: "アクセシビリティの許可が必要です。ないとポインタは動きません。", .zh: "需要辅助功能权限，否则指针不会移动。", .pt: "Precisa de Acessibilidade, senão o ponteiro não se move."]) }
    static var grantAccess: String { L("Grant…", [.ru: "Выдать…", .es: "Conceder…", .fr: "Accorder…", .de: "Erteilen…", .ja: "許可…", .zh: "授予…", .pt: "Conceder…"]) }
    static var globalShortcut: String { L("Global shortcut", [.ru: "Глобальный хоткей", .es: "Atajo global", .fr: "Raccourci global", .de: "Globaler Kurzbefehl", .ja: "グローバルショートカット", .zh: "全局快捷键", .pt: "Atalho global"]) }
    static var toggleAction: String { L("Toggle Keep Awake", [.ru: "Включить или выключить «Не спать»", .es: "Activar o desactivar Mantener activo", .fr: "Activer ou désactiver Rester éveillé", .de: "Wachhalten ein-/ausschalten", .ja: "「スリープ防止」を切り替え", .zh: "开关「保持唤醒」", .pt: "Ativar ou desativar Manter acordado"]) }
    static var pressKeys: String { L("Press keys…", [.ru: "Нажмите клавиши…", .es: "Pulsa las teclas…", .fr: "Appuyez sur les touches…", .de: "Tasten drücken…", .ja: "キーを押してください…", .zh: "请按下按键…", .pt: "Pressione as teclas…"]) }
    static var none: String { L("None", [.ru: "Нет", .es: "Ninguno", .fr: "Aucun", .de: "Keiner", .ja: "なし", .zh: "无", .pt: "Nenhum"]) }
    static var record: String { L("Record", [.ru: "Задать", .es: "Grabar", .fr: "Enregistrer", .de: "Aufnehmen", .ja: "記録", .zh: "录制", .pt: "Gravar"]) }
    static var cancel: String { L("Cancel", [.ru: "Отмена", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static var clear: String { L("Clear", [.ru: "Очистить", .es: "Borrar", .fr: "Effacer", .de: "Löschen", .ja: "クリア", .zh: "清除", .pt: "Limpar"]) }
    static var keepAwakeLidClosed: String { L("Keep awake with the lid closed", [.ru: "Не спать с закрытой крышкой", .es: "Mantener activo con la tapa cerrada", .fr: "Rester éveillé capot fermé", .de: "Bei geschlossenem Deckel wach halten", .ja: "ふたを閉じてもスリープ防止", .zh: "合盖时保持唤醒", .pt: "Manter ativo com a tampa fechada"]) }
    static var adminNote: String { L("Requires an admin password once (uses pmset).", [.ru: "Нужен пароль администратора один раз (использует pmset).", .es: "Requiere una contraseña de administrador una vez (usa pmset).", .fr: "Nécessite un mot de passe administrateur une fois (utilise pmset).", .de: "Erfordert einmalig ein Admin-Passwort (nutzt pmset).", .ja: "管理者パスワードが一度必要です（pmset を使用）。", .zh: "需要一次管理员密码（使用 pmset）。", .pt: "Requer uma senha de administrador uma vez (usa pmset)."]) }
    static var turnOffLowBattery: String { L("Turn off on low battery", [.ru: "Выключать при низком заряде", .es: "Apagar con batería baja", .fr: "Désactiver à batterie faible", .de: "Bei niedrigem Akku ausschalten", .ja: "バッテリー残量が少ないとき無効化", .zh: "电量低时关闭", .pt: "Desligar com bateria fraca"]) }
    static func belowPercent(_ n: Int) -> String { L("Below \(n)%", [.ru: "Ниже \(n)%", .es: "Por debajo del \(n)%", .fr: "En dessous de \(n) %", .de: "Unter \(n) %", .ja: "\(n)% 未満", .zh: "低于 \(n)%", .pt: "Abaixo de \(n)%"]) }
    static var activeIconColor: String { L("Active icon color", [.ru: "Цвет активной иконки", .es: "Color del icono activo", .fr: "Couleur de l’icône active", .de: "Farbe des aktiven Symbols", .ja: "アクティブ時のアイコン色", .zh: "激活时的图标颜色", .pt: "Cor do ícone ativo"]) }
    static var ringColorNote: String { L("Applies while Keep Awake is on; otherwise the shared menu-bar icon is used.", [.ru: "Действует, пока модуль включён; в покое используется общая иконка.", .es: "Se aplica mientras el módulo está activo; en reposo se usa el icono común.", .fr: "S’applique tant que le module est actif ; au repos, l’icône commune est utilisée.", .de: "Gilt, solange das Modul aktiv ist; im Ruhezustand wird das gemeinsame Symbol verwendet.", .ja: "モジュールが有効な間に適用されます。待機時は共通アイコンを使用します。", .zh: "在模块启用期间生效；空闲时使用通用图标。", .pt: "Vale enquanto o módulo está ativo; em repouso usa-se o ícone comum."]) }
    static var addApp: String { L("Add app…", [.ru: "Добавить приложение…", .es: "Añadir app…", .fr: "Ajouter une app…", .de: "App hinzufügen…", .ja: "アプリを追加…", .zh: "添加应用…", .pt: "Adicionar app…"]) }
    static var ringTimer: String { L("Countdown ring in the menu bar", [.ru: "Обратный отсчёт на иконке", .es: "Cuenta atrás en la barra de menús", .fr: "Compte à rebours dans la barre des menus", .de: "Countdown-Ring in der Menüleiste", .ja: "メニューバーでカウントダウン表示", .zh: "菜单栏倒计时圆环", .pt: "Contagem regressiva na barra de menus"]) }
    static var ringTimerNote: String { L("While a timer runs, the ring empties clockwise.", [.ru: "Пока идёт таймер, кольцо убывает по часовой стрелке.", .es: "Mientras corre el temporizador, el anillo se vacía en sentido horario.", .fr: "Pendant le minuteur, l’anneau se vide dans le sens horaire.", .de: "Während der Timer läuft, leert sich der Ring im Uhrzeigersinn.", .ja: "タイマー作動中はリングが時計回りに減っていきます。", .zh: "计时期间圆环按顺时针递减。", .pt: "Enquanto o timer corre, o anel se esvazia no sentido horário."]) }
    static var showTimerText: String { L("Show remaining time in the menu bar", [.ru: "Показывать время в строке меню", .es: "Mostrar el tiempo restante en la barra de menús", .fr: "Afficher le temps restant dans la barre des menus", .de: "Restzeit in der Menüleiste anzeigen", .ja: "残り時間をメニューバーに表示", .zh: "在菜单栏显示剩余时间", .pt: "Mostrar o tempo restante na barra de menus"]) }
    static var timerColor: String { L("Timer color", [.ru: "Цвет таймера", .es: "Color del temporizador", .fr: "Couleur du minuteur", .de: "Timer-Farbe", .ja: "タイマーの色", .zh: "计时器颜色", .pt: "Cor do timer"]) }
    static var menuBarIcon: String { L("Menu-bar icon", [.ru: "Иконка в строке меню", .es: "Icono en la barra de menús", .fr: "Icône de la barre des menus", .de: "Symbol in der Menüleiste", .ja: "メニューバーのアイコン", .zh: "菜单栏图标", .pt: "Ícone na barra de menus"]) }
    static var customActiveIcon: String { L("Custom icon when active", [.ru: "Своя иконка при активации", .es: "Icono propio cuando está activo", .fr: "Icône personnalisée si actif", .de: "Eigenes Symbol bei Aktivität", .ja: "アクティブ時にカスタムアイコン", .zh: "激活时使用自定义图标", .pt: "Ícone personalizado quando ativo"]) }
    static var min15: String { "15 " + minutesUnit }
    static var metricState: String { L("STATE", [.ru: "СОСТОЯНИЕ", .es: "ESTADO", .fr: "ÉTAT", .de: "STATUS", .ja: "状態", .zh: "状态", .pt: "ESTADO"]) }
    static var metricTimer: String { L("TIMER", [.ru: "ТАЙМЕР", .es: "TEMPORIZ.", .fr: "MINUTEUR", .de: "TIMER", .ja: "タイマー", .zh: "计时", .pt: "TIMER"]) }
    static var metricRules: String { L("AUTOMATIONS", [.ru: "АВТОМАТИКА", .es: "AUTOMATIZ.", .fr: "AUTOMATIS.", .de: "AUTOMATIK", .ja: "自動化", .zh: "自动化", .pt: "AUTOMAÇÕES"]) }
    static var metricOn: String { L("ON", [.ru: "ВКЛ", .es: "ON", .fr: "ON", .de: "AN", .ja: "オン", .zh: "开", .pt: "ON"]) }
    static var metricOff: String { L("OFF", [.ru: "ВЫКЛ", .es: "OFF", .fr: "OFF", .de: "AUS", .ja: "オフ", .zh: "关", .pt: "OFF"]) }
}
