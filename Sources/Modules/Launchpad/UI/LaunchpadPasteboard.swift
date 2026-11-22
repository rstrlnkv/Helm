import AppKit

/// **Where Copy Path writes.** A path is plain text; a hidden app's path is as private as its name, so a copy made from the Hidden card
/// carries the two markers nspasteboard.org names beside the text, a type whose content is ignored: `ConcealedType` says "do not
/// record", `TransientType` that the item is short-lived (a manager may honour one and not the other). Neither stops anything from pasting
/// it. **Whether a given clipboard manager honours them was not measured**, and a copied path stays on the pasteboard after the card
/// locks (a known limit). Precedent: `SystemShotPasteboard` in the Screenshots module.
///
/// The board is named so a test reads the types off a pasteboard of its own and never the person's.
struct LaunchpadPasteboard {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    let name: NSPasteboard.Name

    init(named name: NSPasteboard.Name = .general) { self.name = name }

    @discardableResult
    func copy(path: String, concealed: Bool) -> Bool {
        let board = NSPasteboard(name: name)
        board.declareTypes(concealed ? [.string, Self.concealedType, Self.transientType] : [.string], owner: nil)
        // The text first: a refused text is a refusal whatever the markers did.
        guard board.setString(path, forType: .string) else { return false }
        if concealed {
            _ = board.setData(Data(), forType: Self.concealedType)
            _ = board.setData(Data(), forType: Self.transientType)
        }
        return true
    }
}
