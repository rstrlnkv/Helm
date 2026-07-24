import HelmUI

/// Localized strings for the Keep Awake module UI. English is the base; the
/// tables carry zh/es/fr/de/ja/ru/pt.
enum KAStr {
    static var moduleName: String {
        L("Keep Awake", [.ru: "Не спать", .es: "Mantener activo", .fr: "Rester éveillé",
                         .de: "Wach halten", .ja: "スリープ防止", .zh: "保持唤醒", .pt: "Manter ativo"])
    }
    static var summary: String {
        L("Prevent your Mac from sleeping.",
          [.ru: "Не давать Mac уходить в сон.", .es: "Evita que tu Mac se suspenda.",
           .fr: "Empêche votre Mac de se mettre en veille.", .de: "Verhindert den Ruhezustand des Macs.",
           .ja: "Mac がスリープするのを防ぎます。", .zh: "防止 Mac 进入睡眠。",
           .pt: "Impede que o Mac entre em repouso."])
    }
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
    static var movePointer: String { L("Move pointer periodically", [.ru: "Двигать указатель периодически", .es: "Mover el puntero periódicamente", .fr: "Déplacer le pointeur régulièrement", .de: "Zeiger regelmäßig bewegen", .ja: "定期的にポインタを動かす", .zh: "定期移动指针", .pt: "Mover o ponteiro periodicamente"]) }
    static func everyMinutes(_ n: Int) -> String { L("Every \(n) min", [.ru: "Каждые \(n) мин", .es: "Cada \(n) min", .fr: "Toutes les \(n) min", .de: "Alle \(n) Min.", .ja: "\(n) 分ごと", .zh: "每 \(n) 分钟", .pt: "A cada \(n) min"]) }
    static var defaultDuration: String { L("Default duration", [.ru: "Длительность по умолчанию", .es: "Duración por defecto", .fr: "Durée par défaut", .de: "Standarddauer", .ja: "デフォルトの継続時間", .zh: "默认时长", .pt: "Duração padrão"]) }
    static var oneHour: String { L("1 hour", [.ru: "1 час", .es: "1 hora", .fr: "1 heure", .de: "1 Stunde", .ja: "1 時間", .zh: "1 小时", .pt: "1 hora"]) }
    static var twoHours: String { L("2 hours", [.ru: "2 часа", .es: "2 horas", .fr: "2 heures", .de: "2 Stunden", .ja: "2 時間", .zh: "2 小时", .pt: "2 horas"]) }
    static var indefinite: String { L("Indefinite", [.ru: "Бессрочно", .es: "Indefinido", .fr: "Illimité", .de: "Unbegrenzt", .ja: "無期限", .zh: "无限期", .pt: "Indefinido"]) }
    static var globalShortcut: String { L("Global shortcut", [.ru: "Глобальный хоткей", .es: "Atajo global", .fr: "Raccourci global", .de: "Globaler Kurzbefehl", .ja: "グローバルショートカット", .zh: "全局快捷键", .pt: "Atalho global"]) }
    static var toggleAction: String { L("Toggle Keep Awake", [.ru: "Вкл/выкл «Не давать спать»", .es: "Alternar Mantener activo", .fr: "Activer/désactiver Rester éveillé", .de: "Wach halten umschalten", .ja: "スリープ防止の切り替え", .zh: "切换保持唤醒", .pt: "Alternar Manter ativo"]) }
    static var pressKeys: String { L("Press keys…", [.ru: "Нажмите клавиши…", .es: "Pulsa las teclas…", .fr: "Appuyez sur les touches…", .de: "Tasten drücken…", .ja: "キーを押してください…", .zh: "请按下按键…", .pt: "Pressione as teclas…"]) }
    static var none: String { L("None", [.ru: "Нет", .es: "Ninguno", .fr: "Aucun", .de: "Keiner", .ja: "なし", .zh: "无", .pt: "Nenhum"]) }
    static var record: String { L("Record", [.ru: "Задать", .es: "Grabar", .fr: "Enregistrer", .de: "Aufnehmen", .ja: "記録", .zh: "录制", .pt: "Gravar"]) }
    static var cancel: String { L("Cancel", [.ru: "Отмена", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static var clear: String { L("Clear", [.ru: "Очистить", .es: "Borrar", .fr: "Effacer", .de: "Löschen", .ja: "クリア", .zh: "清除", .pt: "Limpar"]) }
    static var closedLid: String { L("Closed lid", [.ru: "Закрытая крышка", .es: "Tapa cerrada", .fr: "Capot fermé", .de: "Geschlossener Deckel", .ja: "ふたを閉じた状態", .zh: "合盖", .pt: "Tampa fechada"]) }
    static var keepAwakeLidClosed: String { L("Keep awake with the lid closed", [.ru: "Не спать с закрытой крышкой", .es: "Mantener activo con la tapa cerrada", .fr: "Rester éveillé capot fermé", .de: "Bei geschlossenem Deckel wach halten", .ja: "ふたを閉じてもスリープ防止", .zh: "合盖时保持唤醒", .pt: "Manter ativo com a tampa fechada"]) }
    static var adminNote: String { L("Requires an admin password once (uses pmset).", [.ru: "Нужен пароль администратора один раз (использует pmset).", .es: "Requiere una contraseña de administrador una vez (usa pmset).", .fr: "Nécessite un mot de passe administrateur une fois (utilise pmset).", .de: "Erfordert einmalig ein Admin-Passwort (nutzt pmset).", .ja: "管理者パスワードが一度必要です（pmset を使用）。", .zh: "需要一次管理员密码（使用 pmset）。", .pt: "Requer uma senha de administrador uma vez (usa pmset)."]) }
    static var battery: String { L("Battery", [.ru: "Батарея", .es: "Batería", .fr: "Batterie", .de: "Batterie", .ja: "バッテリー", .zh: "电池", .pt: "Bateria"]) }
    static var turnOffLowBattery: String { L("Turn off on low battery", [.ru: "Выключать при низком заряде", .es: "Apagar con batería baja", .fr: "Désactiver à batterie faible", .de: "Bei niedrigem Akku ausschalten", .ja: "バッテリー残量が少ないとき無効化", .zh: "电量低时关闭", .pt: "Desligar com bateria fraca"]) }
    static func belowPercent(_ n: Int) -> String { L("Below \(n)%", [.ru: "Ниже \(n)%", .es: "Por debajo del \(n)%", .fr: "En dessous de \(n) %", .de: "Unter \(n) %", .ja: "\(n)% 未満", .zh: "低于 \(n)%", .pt: "Abaixo de \(n)%"]) }
    static var activeIconColor: String { L("Active icon color", [.ru: "Цвет активной иконки", .es: "Color del icono activo", .fr: "Couleur de l’icône active", .de: "Farbe des aktiven Symbols", .ja: "アクティブ時のアイコン色", .zh: "激活时的图标颜色", .pt: "Cor do ícone ativo"]) }
    static var ringColorNote: String { L("Menu-bar ring color while active (white when idle).", [.ru: "Цвет кольца в меню-баре когда активно (белое в покое).", .es: "Color del anillo en la barra de menús mientras está activo (blanco en reposo).", .fr: "Couleur de l’anneau dans la barre des menus lorsqu’actif (blanc au repos).", .de: "Farbe des Menüleisten-Rings bei Aktivität (weiß im Ruhezustand).", .ja: "アクティブ時のメニューバーのリング色（待機時は白）。", .zh: "激活时菜单栏圆环的颜色（空闲时为白色）。", .pt: "Cor do anel na barra de menus quando ativo (branco em repouso)."]) }
    static var addApp: String { L("Add app…", [.ru: "Добавить приложение…", .es: "Añadir app…", .fr: "Ajouter une app…", .de: "App hinzufügen…", .ja: "アプリを追加…", .zh: "添加应用…", .pt: "Adicionar app…"]) }
    static var ringTimer: String { L("Countdown ring in the menu bar", [.ru: "Обратный отсчёт на иконке", .es: "Cuenta atrás en la barra de menús", .fr: "Compte à rebours dans la barre des menus", .de: "Countdown-Ring in der Menüleiste", .ja: "メニューバーでカウントダウン表示", .zh: "菜单栏倒计时圆环", .pt: "Contagem regressiva na barra de menus"]) }
    static var ringTimerNote: String { L("While a timer runs, the ring empties clockwise.", [.ru: "Пока идёт таймер, кольцо убывает по часовой стрелке.", .es: "Mientras corre el temporizador, el anillo se vacía en sentido horario.", .fr: "Pendant le minuteur, l’anneau se vide dans le sens horaire.", .de: "Während der Timer läuft, leert sich der Ring im Uhrzeigersinn.", .ja: "タイマー作動中はリングが時計回りに減っていきます。", .zh: "计时期间圆环按顺时针递减。", .pt: "Enquanto o timer corre, o anel se esvazia no sentido horário."]) }
    static var showTimerText: String { L("Show remaining time in the menu bar", [.ru: "Показывать время в строке меню", .es: "Mostrar el tiempo restante en la barra de menús", .fr: "Afficher le temps restant dans la barre des menus", .de: "Restzeit in der Menüleiste anzeigen", .ja: "残り時間をメニューバーに表示", .zh: "在菜单栏显示剩余时间", .pt: "Mostrar o tempo restante na barra de menus"]) }
    static var timerColor: String { L("Timer color", [.ru: "Цвет таймера", .es: "Color del temporizador", .fr: "Couleur du minuteur", .de: "Timer-Farbe", .ja: "タイマーの色", .zh: "计时器颜色", .pt: "Cor do timer"]) }
    static var sameAsActive: String { L("Same as active color", [.ru: "Как у активного состояния", .es: "Igual que el color activo", .fr: "Comme la couleur active", .de: "Wie die aktive Farbe", .ja: "アクティブ時の色と同じ", .zh: "与激活颜色相同", .pt: "Igual à cor ativa"]) }
    static var activeIcon: String { L("Active icon", [.ru: "Активная иконка", .es: "Icono activo", .fr: "Icône active", .de: "Aktives Symbol", .ja: "アクティブアイコン", .zh: "激活图标", .pt: "Ícone ativo"]) }
    static var customActiveIcon: String { L("Custom icon when active", [.ru: "Своя иконка при активации", .es: "Icono propio cuando está activo", .fr: "Icône personnalisée si actif", .de: "Eigenes Symbol bei Aktivität", .ja: "アクティブ時にカスタムアイコン", .zh: "激活时使用自定义图标", .pt: "Ícone personalizado quando ativo"]) }
    static var customActiveIconNote: String { L("Show this shape in the menu bar while Keep Awake is active.", [.ru: "Показывать эту форму в меню-баре, пока «Не давать спать» активно.", .es: "Mostrar esta forma en la barra de menús mientras Mantener activo está activo.", .fr: "Afficher cette forme dans la barre des menus tant que Rester éveillé est actif.", .de: "Diese Form in der Menüleiste anzeigen, solange Wach halten aktiv ist.", .ja: "スリープ防止が有効な間、この形をメニューバーに表示します。", .zh: "在保持唤醒激活时于菜单栏显示此形状。", .pt: "Mostrar esta forma na barra de menus enquanto Manter ativo estiver ativo."]) }
    static var min15: String { "15 " + minutesUnit }
}
