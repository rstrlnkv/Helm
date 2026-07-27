import AppKit

func w(_ s: String, _ f: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: f]).width }
let callout = NSFont.preferredFont(forTextStyle: .callout)
let calloutBold = NSFont.systemFont(ofSize: callout.pointSize, weight: .semibold)
let caption = NSFont.preferredFont(forTextStyle: .caption1)
let mono11 = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
func button(_ l: String) -> CGFloat { w(l, caption) + 22 }

print("=== the bar ===")
// Crumbs: 3 levels shown in full (the collapse rule), realistic ru names.
let crumbs = ["Macintosh HD", "Пользователи", "Фильмы"]
var crumbText: CGFloat = 0
for (i, c) in crumbs.enumerated() {
    crumbText += min(w(c, i == crumbs.count - 1 ? calloutBold : callout),
                     i == crumbs.count - 1 ? 150 : 120)
}
let crumbsTotal = crumbText + CGFloat(crumbs.count - 1) * 14 + CGFloat(crumbs.count) * 8
let back: CGFloat = 28
let status = w("Файлов: 1 449 960 за 76,7 с", caption)
let measured = w("Измерено 7 часов назад", caption)
let advice = button("12") + 16
let duplicates = button("Дубликаты") + 16
let scanAgain = button("Сканировать заново")
let chrome: CGFloat = 40 + 8 * 5     // padding + inter-item spacing

let withoutStatus = back + crumbsTotal + advice + duplicates + scanAgain + chrome
let withStatus = withoutStatus + max(status, measured) + 8
print(String(format: "  bar without the scan statement: %.0f pt", withoutStatus))
print(String(format: "  bar with it:                    %.0f pt", withStatus))

print("=== the two panes ===")
// The ring column as declared, plus its padding.
let ringMin: CGFloat = 300 + 28
// The list: swatch + name + "Системный" caption + size + basket button.
let listName = w("Медиатека iMovie.imovielibrary", callout)
let listSize = w("248,52 ГБ", mono11)
let listMin = 8 + 10 + listName + 12 + listSize + 8 + 24 + 12
print(String(format: "  ring column minimum: %.0f pt", ringMin))
print(String(format: "  list comfortable:    %.0f pt (name %.0f + size %.0f)", listMin, listName, listSize))
print(String(format: "  both side by side:   %.0f pt", ringMin + 1 + listMin))

print("=== against real windows ===")
for window in [860.0, 940.0, 1100.0, 1400.0] {
    let detail = window - 250
    let bothFit = detail >= ringMin + 1 + listMin
    let statusFits = detail >= withStatus
    print(String(format: "  window %4.0f → detail %4.0f: ring+list %@, bar-with-statement %@",
                 window, detail,
                 bothFit ? "fit " : "DON'T",
                 statusFits ? "fits" : "DOESN'T"))
}
