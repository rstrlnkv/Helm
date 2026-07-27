import HelmUI
import Module_Autopilot_Engine

/// Every user-visible string in the rules module, in eight languages.
enum ApStr {
    static var moduleName: String { L("Rules", [.ru: "Правила", .es: "Reglas", .fr: "Règles", .de: "Regeln", .ja: "ルール", .zh: "规则", .pt: "Regras"]) }
    static var summary: String { L("Folders that keep themselves in order", [.ru: "Папки, которые убирают себя сами", .es: "Carpetas que se ordenan solas", .fr: "Des dossiers qui se rangent tout seuls", .de: "Ordner, die sich selbst aufräumen", .ja: "自分で片づくフォルダ", .zh: "会自己整理的文件夹", .pt: "Pastas que se organizam sozinhas"]) }
    static var startHint: String { L("Point Helm at a folder and give it rules. A file that arrives is checked against them in order, and the first rule that matches is the one that runs.", [.ru: "Укажите Helm папку и задайте правила. Появившийся файл проверяется по ним по порядку, и срабатывает первое подошедшее правило.", .es: "Indica una carpeta y dale reglas. Un archivo que llega se comprueba en orden, y se ejecuta la primera regla que coincide.", .fr: "Désignez un dossier et donnez-lui des règles. Un fichier qui arrive est vérifié dans l’ordre, et la première règle qui correspond s’exécute.", .de: "Wähle einen Ordner und gib ihm Regeln. Eine ankommende Datei wird der Reihe nach geprüft, und die erste passende Regel läuft.", .ja: "フォルダを指定してルールを与えます。届いたファイルは上から順に照合され、最初に一致したルールが実行されます。", .zh: "指定一个文件夹并为它设定规则。新到的文件按顺序检查，第一条匹配的规则会执行。", .pt: "Aponte para uma pasta e dê regras a ela. Um arquivo que chega é verificado na ordem, e a primeira regra que casa é a que roda."]) }
    static var needsAccess: String { L("Without Full Disk Access a rule sees only some of the folder, and acts on only some of it.", [.ru: "Без полного доступа к диску правило видит лишь часть папки — и действует лишь на часть.", .es: "Sin Acceso Total al Disco una regla ve solo parte de la carpeta y actúa solo sobre esa parte.", .fr: "Sans accès complet au disque, une règle ne voit qu’une partie du dossier et n’agit que sur celle-ci.", .de: "Ohne Festplattenvollzugriff sieht eine Regel nur einen Teil des Ordners — und wirkt nur darauf.", .ja: "フルディスクアクセスがないと、ルールはフォルダの一部しか見えず、その一部にしか働きません。", .zh: "没有完全磁盘访问权限时，规则只能看到文件夹的一部分，也只会作用于这一部分。", .pt: "Sem Acesso Total ao Disco uma regra vê apenas parte da pasta e age apenas sobre ela."]) }

    // MARK: - Folders

    static var addFolder: String { L("Add folder…", [.ru: "Добавить папку…", .es: "Añadir carpeta…", .fr: "Ajouter un dossier…", .de: "Ordner hinzufügen…", .ja: "フォルダを追加…", .zh: "添加文件夹…", .pt: "Adicionar pasta…"]) }
    static var removeFolder: String { L("Stop watching", [.ru: "Перестать следить", .es: "Dejar de vigilar", .fr: "Ne plus surveiller", .de: "Nicht mehr beobachten", .ja: "監視をやめる", .zh: "停止监视", .pt: "Parar de vigiar"]) }
    static var runNow: String { L("Run now", [.ru: "Прогнать сейчас", .es: "Ejecutar ahora", .fr: "Exécuter maintenant", .de: "Jetzt ausführen", .ja: "今すぐ実行", .zh: "立即运行", .pt: "Executar agora"]) }
    static func ruleCount(_ count: Int) -> String { L("\(count) rules", [.ru: "Правил: \(count)", .es: "\(count) reglas", .fr: "\(count) règles", .de: "\(count) Regeln", .ja: "\(count) 個のルール", .zh: "\(count) 条规则", .pt: "\(count) regras"]) }
    static var noRules: String { L("No rules yet", [.ru: "Правил пока нет", .es: "Aún sin reglas", .fr: "Pas encore de règles", .de: "Noch keine Regeln", .ja: "まだルールがありません", .zh: "还没有规则", .pt: "Ainda sem regras"]) }
    static var depth: String { L("Include subfolders", [.ru: "Включая подпапки", .es: "Incluir subcarpetas", .fr: "Inclure les sous-dossiers", .de: "Unterordner einbeziehen", .ja: "サブフォルダも対象", .zh: "包含子文件夹", .pt: "Incluir subpastas"]) }
    static var depthNote: String { L("A rule that reaches into subfolders is how a tidy folder becomes a rearranged one. Off by default.", [.ru: "Правило, залезающее в подпапки, — это то, как аккуратная папка становится переставленной. По умолчанию выключено.", .es: "Una regla que entra en las subcarpetas es como una carpeta ordenada acaba reorganizada. Desactivado por omisión.", .fr: "Une règle qui descend dans les sous-dossiers, c’est ainsi qu’un dossier rangé devient un dossier réorganisé. Désactivé par défaut.", .de: "Eine Regel, die in Unterordner greift, macht aus einem ordentlichen Ordner einen umsortierten. Standardmäßig aus.", .ja: "サブフォルダまで踏み込むルールは、整ったフォルダを並べ替えられたフォルダに変えます。既定はオフです。", .zh: "深入子文件夹的规则，正是整齐的文件夹被重新排布的原因。默认关闭。", .pt: "Uma regra que entra nas subpastas é como uma pasta arrumada vira uma pasta remexida. Desligado por padrão."]) }

    // MARK: - Rules

    static var newRule: String { L("New rule", [.ru: "Новое правило", .es: "Nueva regla", .fr: "Nouvelle règle", .de: "Neue Regel", .ja: "新しいルール", .zh: "新建规则", .pt: "Nova regra"]) }
    static var untitledRule: String { L("Untitled rule", [.ru: "Без названия", .es: "Regla sin título", .fr: "Règle sans titre", .de: "Unbenannte Regel", .ja: "名称未設定のルール", .zh: "未命名规则", .pt: "Regra sem título"]) }
    static var ruleName: String { L("Name", [.ru: "Название", .es: "Nombre", .fr: "Nom", .de: "Name", .ja: "名前", .zh: "名称", .pt: "Nome"]) }
    static var matchAll: String { L("all of", [.ru: "все из", .es: "todas", .fr: "toutes", .de: "alle", .ja: "すべて", .zh: "全部满足", .pt: "todas"]) }
    static var matchAny: String { L("any of", [.ru: "любое из", .es: "cualquiera", .fr: "au moins une", .de: "eine von", .ja: "いずれか", .zh: "任一满足", .pt: "qualquer"]) }
    static var whenLabel: String { L("When", [.ru: "Когда", .es: "Cuando", .fr: "Quand", .de: "Wenn", .ja: "条件", .zh: "当", .pt: "Quando"]) }
    static var thenLabel: String { L("Then", [.ru: "То", .es: "Entonces", .fr: "Alors", .de: "Dann", .ja: "その時", .zh: "则", .pt: "Então"]) }
    static var addCondition: String { L("Add condition", [.ru: "Добавить условие", .es: "Añadir condición", .fr: "Ajouter une condition", .de: "Bedingung hinzufügen", .ja: "条件を追加", .zh: "添加条件", .pt: "Adicionar condição"]) }
    static var firstMatchNote: String { L("Rules run top to bottom and the first match wins — a file gets one action, not several.", [.ru: "Правила идут сверху вниз, побеждает первое подошедшее — с файлом происходит одно действие, а не несколько.", .es: "Las reglas van de arriba abajo y gana la primera que coincide: al archivo le ocurre una acción, no varias.", .fr: "Les règles s’appliquent de haut en bas et la première correspondance l’emporte : un fichier reçoit une action, pas plusieurs.", .de: "Regeln laufen von oben nach unten, die erste Übereinstimmung gewinnt — eine Datei bekommt eine Aktion, nicht mehrere.", .ja: "ルールは上から順に評価され、最初に一致したものが実行されます。ファイルに起きることは 1 つだけです。", .zh: "规则自上而下执行，第一条匹配的生效——一个文件只会发生一件事，不会连续发生多件。", .pt: "As regras vão de cima para baixo e a primeira que casa vence — o arquivo recebe uma ação, não várias."]) }

    // MARK: - Dry run

    static var dryRun: String { L("What would happen", [.ru: "Что произойдёт", .es: "Qué pasaría", .fr: "Ce qui se passerait", .de: "Was passieren würde", .ja: "何が起きるか", .zh: "会发生什么", .pt: "O que aconteceria"]) }
    static var dryRunNote: String { L("A rule is a decision made once and carried out from then on, so it is shown before it is switched on.", [.ru: "Правило — это решение, принятое один раз и исполняемое дальше всегда, поэтому его показывают до включения.", .es: "Una regla es una decisión tomada una vez y ejecutada desde entonces, por eso se muestra antes de activarla.", .fr: "Une règle est une décision prise une fois et appliquée ensuite toujours : elle est donc montrée avant d’être activée.", .de: "Eine Regel ist eine einmal getroffene und danach immer ausgeführte Entscheidung — deshalb wird sie vor dem Einschalten gezeigt.", .ja: "ルールは一度決めたらその後ずっと実行される判断なので、有効にする前に内容を示します。", .zh: "规则是一次做出、此后一直执行的决定，所以在开启之前先展示它。", .pt: "Uma regra é uma decisão tomada uma vez e executada dali em diante, por isso ela é mostrada antes de ser ligada."]) }
    static var nothingWouldHappen: String { L("Nothing in this folder matches yet.", [.ru: "Пока ничто в этой папке не подходит.", .es: "Por ahora nada en esta carpeta coincide.", .fr: "Rien dans ce dossier ne correspond pour l’instant.", .de: "Derzeit passt nichts in diesem Ordner.", .ja: "今のところ、このフォルダに一致するものはありません。", .zh: "目前这个文件夹里没有匹配的内容。", .pt: "Por ora nada nesta pasta corresponde."]) }
    static var enableRule: String { L("Turn the rule on", [.ru: "Включить правило", .es: "Activar la regla", .fr: "Activer la règle", .de: "Regel einschalten", .ja: "ルールを有効にする", .zh: "开启规则", .pt: "Ligar a regra"]) }
    static func swept(_ acted: Int, _ examined: Int) -> String { L("Acted on \(acted) of \(examined)", [.ru: "Обработано \(acted) из \(examined)", .es: "Se actuó sobre \(acted) de \(examined)", .fr: "\(acted) sur \(examined) traités", .de: "\(acted) von \(examined) bearbeitet", .ja: "\(examined) 件中 \(acted) 件を処理", .zh: "处理了 \(examined) 个中的 \(acted) 个", .pt: "Agiu sobre \(acted) de \(examined)"]) }

    // MARK: - Fields

    static var fieldName: String { L("Name", [.ru: "Имя", .es: "Nombre", .fr: "Nom", .de: "Name", .ja: "名前", .zh: "名称", .pt: "Nome"]) }
    static var fieldExtension: String { L("Extension", [.ru: "Расширение", .es: "Extensión", .fr: "Extension", .de: "Endung", .ja: "拡張子", .zh: "扩展名", .pt: "Extensão"]) }
    static var fieldKind: String { L("Kind", [.ru: "Вид", .es: "Tipo", .fr: "Type", .de: "Art", .ja: "種類", .zh: "种类", .pt: "Tipo"]) }
    static var fieldSize: String { L("Size", [.ru: "Размер", .es: "Tamaño", .fr: "Taille", .de: "Größe", .ja: "サイズ", .zh: "大小", .pt: "Tamanho"]) }
    static var fieldDateAdded: String { L("Date added", [.ru: "Дата добавления", .es: "Fecha de adición", .fr: "Date d’ajout", .de: "Hinzugefügt am", .ja: "追加日", .zh: "添加日期", .pt: "Data de adição"]) }
    static var fieldDateModified: String { L("Date modified", [.ru: "Дата изменения", .es: "Fecha de modificación", .fr: "Date de modification", .de: "Geändert am", .ja: "変更日", .zh: "修改日期", .pt: "Data de modificação"]) }
    static var fieldSource: String { L("Downloaded from", [.ru: "Откуда скачано", .es: "Descargado de", .fr: "Téléchargé depuis", .de: "Geladen von", .ja: "ダウンロード元", .zh: "下载来源", .pt: "Baixado de"]) }
    static var fieldTag: String { L("Tag", [.ru: "Тег", .es: "Etiqueta", .fr: "Étiquette", .de: "Tag", .ja: "タグ", .zh: "标签", .pt: "Etiqueta"]) }

    static var comparisonIs: String { L("is", [.ru: "равно", .es: "es", .fr: "est", .de: "ist", .ja: "が一致", .zh: "等于", .pt: "é"]) }
    static var comparisonContains: String { L("contains", [.ru: "содержит", .es: "contiene", .fr: "contient", .de: "enthält", .ja: "を含む", .zh: "包含", .pt: "contém"]) }
    static var comparisonBegins: String { L("begins with", [.ru: "начинается с", .es: "empieza por", .fr: "commence par", .de: "beginnt mit", .ja: "で始まる", .zh: "开头是", .pt: "começa com"]) }
    static var comparisonEnds: String { L("ends with", [.ru: "заканчивается на", .es: "termina en", .fr: "se termine par", .de: "endet mit", .ja: "で終わる", .zh: "结尾是", .pt: "termina com"]) }
    static var comparisonLarger: String { L("larger than", [.ru: "больше чем", .es: "mayor que", .fr: "plus grand que", .de: "größer als", .ja: "より大きい", .zh: "大于", .pt: "maior que"]) }
    static var comparisonSmaller: String { L("smaller than", [.ru: "меньше чем", .es: "menor que", .fr: "plus petit que", .de: "kleiner als", .ja: "より小さい", .zh: "小于", .pt: "menor que"]) }
    static var comparisonOlder: String { L("older than", [.ru: "старше", .es: "anterior a", .fr: "plus ancien que", .de: "älter als", .ja: "より古い", .zh: "早于", .pt: "mais antigo que"]) }
    static var comparisonNewer: String { L("newer than", [.ru: "новее", .es: "posterior a", .fr: "plus récent que", .de: "neuer als", .ja: "より新しい", .zh: "晚于", .pt: "mais recente que"]) }
    static var unitMegabytes: String { L("MB", [.ru: "МБ", .es: "MB", .fr: "Mo", .de: "MB", .ja: "MB", .zh: "MB", .pt: "MB"]) }
    static var unitDays: String { L("days", [.ru: "дней", .es: "días", .fr: "jours", .de: "Tage", .ja: "日", .zh: "天", .pt: "dias"]) }

    static func kindName(_ kind: FileKind) -> String {
        switch kind {
        case .image: L("Image", [.ru: "Изображение", .es: "Imagen", .fr: "Image", .de: "Bild", .ja: "画像", .zh: "图片", .pt: "Imagem"])
        case .document: L("Document", [.ru: "Документ", .es: "Documento", .fr: "Document", .de: "Dokument", .ja: "書類", .zh: "文稿", .pt: "Documento"])
        case .archive: L("Archive", [.ru: "Архив", .es: "Archivo comprimido", .fr: "Archive", .de: "Archiv", .ja: "アーカイブ", .zh: "压缩包", .pt: "Arquivo compactado"])
        case .video: L("Video", [.ru: "Видео", .es: "Vídeo", .fr: "Vidéo", .de: "Video", .ja: "ビデオ", .zh: "视频", .pt: "Vídeo"])
        case .audio: L("Audio", [.ru: "Аудио", .es: "Audio", .fr: "Audio", .de: "Audio", .ja: "オーディオ", .zh: "音频", .pt: "Áudio"])
        case .folder: L("Folder", [.ru: "Папка", .es: "Carpeta", .fr: "Dossier", .de: "Ordner", .ja: "フォルダ", .zh: "文件夹", .pt: "Pasta"])
        case .other: L("Other", [.ru: "Другое", .es: "Otro", .fr: "Autre", .de: "Anderes", .ja: "その他", .zh: "其他", .pt: "Outro"])
        }
    }

    // MARK: - Actions

    static var actionMove: String { L("Move to folder", [.ru: "Переместить в папку", .es: "Mover a carpeta", .fr: "Déplacer vers un dossier", .de: "In Ordner bewegen", .ja: "フォルダへ移動", .zh: "移动到文件夹", .pt: "Mover para pasta"]) }
    static var actionSort: String { L("Sort into subfolder", [.ru: "Разложить по подпапкам", .es: "Ordenar en subcarpetas", .fr: "Ranger en sous-dossier", .de: "In Unterordner einsortieren", .ja: "サブフォルダに整理", .zh: "整理到子文件夹", .pt: "Organizar em subpasta"]) }
    static var actionRename: String { L("Rename", [.ru: "Переименовать", .es: "Renombrar", .fr: "Renommer", .de: "Umbenennen", .ja: "名前を変更", .zh: "重命名", .pt: "Renomear"]) }
    static var actionTag: String { L("Add tag", [.ru: "Поставить тег", .es: "Añadir etiqueta", .fr: "Ajouter une étiquette", .de: "Tag hinzufügen", .ja: "タグを付ける", .zh: "添加标签", .pt: "Adicionar etiqueta"]) }
    static var actionTrash: String { L("Move to Trash", [.ru: "Переместить в Корзину", .es: "Mover a la Papelera", .fr: "Placer dans la corbeille", .de: "In den Papierkorb", .ja: "ゴミ箱に入れる", .zh: "移到废纸篓", .pt: "Mover para o Lixo"]) }
    static var schemeKind: String { L("by kind", [.ru: "по виду", .es: "por tipo", .fr: "par type", .de: "nach Art", .ja: "種類別", .zh: "按种类", .pt: "por tipo"]) }
    static var schemeMonth: String { L("by month", [.ru: "по месяцу", .es: "por mes", .fr: "par mois", .de: "nach Monat", .ja: "月別", .zh: "按月份", .pt: "por mês"]) }
    static var patternHint: String { L("{name}, {date} and {counter} are replaced. The extension is always the file’s own.", [.ru: "{name}, {date} и {counter} подставляются. Расширение всегда остаётся собственным.", .es: "{name}, {date} y {counter} se sustituyen. La extensión siempre es la del archivo.", .fr: "{name}, {date} et {counter} sont remplacés. L’extension reste toujours celle du fichier.", .de: "{name}, {date} und {counter} werden ersetzt. Die Endung bleibt immer die der Datei.", .ja: "{name}、{date}、{counter} が置き換わります。拡張子は常に元のままです。", .zh: "{name}、{date} 和 {counter} 会被替换。扩展名始终保持文件本身的。", .pt: "{name}, {date} e {counter} são substituídos. A extensão é sempre a do próprio arquivo."]) }
    static var chooseDestination: String { L("Choose…", [.ru: "Выбрать…", .es: "Elegir…", .fr: "Choisir…", .de: "Wählen…", .ja: "選択…", .zh: "选择…", .pt: "Escolher…"]) }

    // MARK: - Common

    static var cancel: String { L("Cancel", [.ru: "Отменить", .es: "Cancelar", .fr: "Annuler", .de: "Abbrechen", .ja: "キャンセル", .zh: "取消", .pt: "Cancelar"]) }
    static var done: String { L("Done", [.ru: "Готово", .es: "Listo", .fr: "Terminé", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "Concluído"]) }
    static var edit: String { L("Edit", [.ru: "Изменить", .es: "Editar", .fr: "Modifier", .de: "Bearbeiten", .ja: "編集", .zh: "编辑", .pt: "Editar"]) }
    static var delete: String { L("Delete", [.ru: "Удалить", .es: "Eliminar", .fr: "Supprimer", .de: "Löschen", .ja: "削除", .zh: "删除", .pt: "Excluir"]) }
}
