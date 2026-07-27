import AppKit

// What the duplicates toolbar needs, in the widest of the eight languages.
func w(_ s: String, _ f: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: f]).width }
let callout = NSFont.preferredFont(forTextStyle: .callout)
let calloutBold = NSFont.systemFont(ofSize: callout.pointSize, weight: .semibold)
let caption = NSFont.preferredFont(forTextStyle: .caption1)
func button(_ l: String) -> CGFloat { w(l, caption) + 22 }

let folderIcon: CGFloat = 20
/// A path shorter than this says nothing: "/…re" is not a location.
let pathFloor: CGFloat = 180
let chooseAnother = [
    "Choose another folder", "Выбрать другую папку", "Elegir otra carpeta",
    "Choisir un autre dossier", "Anderen Ordner wählen", "別のフォルダを選択",
    "选择其他文件夹", "Escolher outra pasta",
].map(button).max()!
let searchAgain = [
    "Search again", "Искать заново", "Buscar de nuevo", "Rechercher à nouveau",
    "Erneut suchen", "もう一度検索", "重新搜索", "Buscar de novo",
].map(button).max()!
let count = [
    "Groups: 12 · 18,9 MB recoverable", "Групп: 12 · можно освободить 18,9 МБ",
    "Grupos: 12 · 18,9 MB recuperables", "Groupes : 12 · 18,9 Mo récupérables",
    "Gruppen: 12 · 18,9 MB freizugeben",
].map { w($0, caption) }.max()!
let chrome: CGFloat = 40 + 8 * 4          // page padding + inter-item spacing

let withoutCount = folderIcon + pathFloor + chooseAnother + searchAgain + chrome
print(String(format: "  choose+search buttons:      %.0f pt", chooseAnother + searchAgain))
print(String(format: "  count line (widest of 8):   %.0f pt", count))
print(String(format: "  bar without the count:      %.0f pt", withoutCount))
print(String(format: "  bar with it:                %.0f pt", withoutCount + count + 8))
