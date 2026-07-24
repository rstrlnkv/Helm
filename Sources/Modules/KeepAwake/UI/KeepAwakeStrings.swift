import HelmUI

/// Localized strings for the Keep Awake module UI. English is the base; the
/// tables carry zh/es/fr/de/ja/ru/pt.
enum KAStr {
    static var moduleName: String {
        L("Keep Awake", [.ru: "Не давать спать", .es: "Mantener activo", .fr: "Rester éveillé",
                         .de: "Wach halten", .ja: "スリープ防止", .zh: "保持唤醒", .pt: "Manter ativo"])
    }
    static var summary: String {
        L("Prevent your Mac from sleeping.",
          [.ru: "Не давать Mac уходить в сон.", .es: "Evita que tu Mac se suspenda.",
           .fr: "Empêche votre Mac de se mettre en veille.", .de: "Verhindert den Ruhezustand des Macs.",
           .ja: "Mac がスリープするのを防ぎます。", .zh: "防止 Mac 进入睡眠。",
           .pt: "Impede que o Mac entre em repouso."])
    }
    static var start: String {
        L("Start", [.ru: "Старт", .es: "Iniciar", .fr: "Démarrer", .de: "Start", .ja: "開始", .zh: "开始", .pt: "Iniciar"])
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
}
