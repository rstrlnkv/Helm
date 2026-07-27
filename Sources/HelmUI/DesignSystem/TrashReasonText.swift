import Foundation
import HelmRuntime

/// Why a path refused to move, in a sentence.
///
/// These lived inside the Uninstaller, which is the module that had them
/// first — so Disk and Duplicates, which refuse for exactly the same reasons,
/// said nothing but a number. A reason phrased two ways in two modules is two
/// things to the person reading it, so there is one table.
public enum TrashReasonText {
    public static func sentence(_ raw: String) -> String {
        switch raw {
        case "needsFullDiskAccess":
            return L("Helm needs Full Disk Access to move this.", [.ru: "Для перемещения нужен доступ к диску.", .es: "Helm necesita Acceso total al disco para moverlo.", .fr: "Helm a besoin de l’accès complet au disque pour le déplacer.", .de: "Helm braucht Festplattenvollzugriff dafür.", .ja: "移動にはフルディスクアクセスが必要です。", .zh: "移动此项需要完全磁盘访问权限。", .pt: "O Helm precisa de Acesso Total ao Disco para mover isto."])
        case "activeSystemExtension":
            return L("The app has an active system extension. Turn it off first.", [.ru: "У программы активно системное расширение. Сначала отключите его.", .es: "La app tiene una extensión del sistema activa. Desactívala primero.", .fr: "L’app a une extension système active. Désactivez-la d’abord.", .de: "Die App hat eine aktive Systemerweiterung. Zuerst deaktivieren.", .ja: "アプリのシステム機能拡張が有効です。先に無効にしてください。", .zh: "该应用有已启用的系统扩展，请先关闭。", .pt: "O app tem uma extensão do sistema ativa. Desative-a primeiro."])
        case TrashFailure.Reason.outOfScope.rawValue:
            return L("Outside the folders Helm may clean — nothing was attempted.", [.ru: "За пределами папок, которые Helm может чистить — ничего не удалялось.", .es: "Fuera de las carpetas que Helm puede limpiar; no se intentó nada.", .fr: "Hors des dossiers que Helm peut nettoyer — rien n’a été tenté.", .de: "Außerhalb der Ordner, die Helm bereinigen darf — nichts versucht.", .ja: "Helm が整理できるフォルダの外です。何も実行していません。", .zh: "不在 Helm 可清理的文件夹内，未执行任何操作。", .pt: "Fora das pastas que o Helm pode limpar — nada foi tentado."])
        case "noPermission":
            return L("No permission to move this item — it may be locked or in use.", [.ru: "Нет прав на перемещение — объект может быть заблокирован или используется.", .es: "Sin permiso para mover este elemento: puede estar bloqueado o en uso.", .fr: "Pas l’autorisation de déplacer cet élément — il peut être verrouillé ou utilisé.", .de: "Keine Berechtigung zum Verschieben — möglicherweise gesperrt oder in Benutzung.", .ja: "移動する権限がありません。ロック中か使用中の可能性があります。", .zh: "没有权限移动此项——可能已锁定或正在使用。", .pt: "Sem permissão para mover este item — pode estar bloqueado ou em uso."])
        default:
            return L("macOS refused to move this item.", [.ru: "macOS отказалась перемещать этот объект.", .es: "macOS se negó a mover este elemento.", .fr: "macOS a refusé de déplacer cet élément.", .de: "macOS hat das Verschieben abgelehnt.", .ja: "macOS がこの項目の移動を拒否しました。", .zh: "macOS 拒绝移动此项。", .pt: "O macOS recusou mover este item."])
        }
    }
}
