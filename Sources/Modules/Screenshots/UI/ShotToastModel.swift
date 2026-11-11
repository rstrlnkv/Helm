import SwiftUI
import Module_Screenshots_Engine

/// What the after-shot window says. One floating panel for both: the shots that follow captures, and the refusal
/// that follows one that did not happen.
///
/// **A list of shots, bounded by `ShotShelf.limit`.** One shot is the bare picture; more are a pile in the corner,
/// which a click unfolds into a row. The list is kept oldest first and changed through `add`, `update` and `remove`,
/// and emptied whole by the `content` setter; a shot gets onto it only by `add`, so the bound is `ShotShelf.add`'s. A refusal is drawn in the list's place and does
/// not end it: the shots are still what they were when the plaque goes.
@MainActor final class ShotToastModel: ObservableObject {
    enum Content {
        case picture(CGImage, caption: String?, file: URL?)
        case refusal(title: String, body: String, offersSettings: Bool)
    }

    /// One shot in the window.
    struct Shot: Identifiable {
        let id: Int
        /// The reduced copy that is drawn (`ShotToast.thumbnail`).
        var image: CGImage
        /// What a screen reader reads of it; nil while the shot is still being written.
        var caption: String?
        var file: URL?
        /// The full picture of a shot that was only copied: a thumbnail is a reduced copy, and a drag or a share of it
        /// would hand over `ShotThumbnail.longestEdge` pixels. A shot with a file holds none, and is read back from
        /// the file when asked. It leaves memory with the shot: pushed out, closed, or gone with the window.
        var full: CGImage?
        /// What the shot's file was when it was written: what «Edit» and the replacement that follows ask the file
        /// against. Nil for a shot with no file.
        var reading: ShotReading?
    }

    @Published private(set) var shots: [Shot] = []
    /// Only ever a `.refusal`.
    @Published private(set) var refusal: Content?
    @Published var shown = false
    /// The pointer is over the single picture, or over the pile: the capsule is up.
    @Published var hovering = false
    /// The pile is unfolded into a row.
    @Published var unfolded = false
    /// How far the row is scrolled toward its oldest shot (`ShotShelf.scrolled`).
    @Published var offset: CGFloat = 0
    /// The row's scroll bar is up.
    @Published var barShown = false
    /// The shot of the row the pointer is on, whose capsule is up.
    @Published var focus: Shot.ID?
    private var nextID = 0

    /// What the close control does: the toast's own `close`, set by its owner.
    var dismiss: () -> Void = {}
    /// What the capsule's Edit, Copy, Copy All and Pin do, what a click on the pile and on «N more» do, what a scroll
    /// over the row does, and what the pointer's coming and going tells the toast's clock: set by its owner.
    var edit: () -> Void = {}
    var copy: () -> Void = {}
    var copyAll: () -> Void = {}
    var pin: () -> Void = {}
    var unfold: () -> Void = {}
    var showOldest: () -> Void = {}
    var scroll: (CGFloat, Bool) -> Void = { _, _ in }
    var hoverChanged: (Bool) -> Void = { _ in }
    /// The newest shot's own view, which the Share sheet is shown relative to and the pointer is asked against; set
    /// by that view once it is on a window.
    weak var anchor: NSView? { didSet { if anchor != nil { anchorAttached() } } }
    var anchorAttached: () -> Void = {}
    /// The view of the row's shot the pointer came onto last.
    weak var focused: NSView?

    // MARK: - What the window is

    /// The window as one thing: the refusal while there is one, else the shot that an action is about. Setting it
    /// to a picture makes the window that one shot, the list that shot alone; a refusal is drawn over the list and
    /// leaves it; nil empties both.
    var content: Content? {
        get { refusal ?? current.map { .picture($0.image, caption: $0.caption, file: $0.file) } }
        set {
            unfolded = false
            focus = nil
            offset = 0
            barShown = false
            switch newValue {
            case .picture(let image, let caption, let file)?:
                refusal = nil
                shots = []
                add(image, caption: caption, file: file)
            case .refusal?:
                refusal = newValue
            case nil:
                refusal = nil
                shots = []
            }
        }
    }

    /// The shot an action is about: in the row the one the pointer is on, else the newest. None while a refusal
    /// covers the shots: nothing of them can be copied, edited, dragged or pinned from under it.
    var current: Shot? {
        guard refusal == nil else { return nil }
        return (unfolded ? shots.first { $0.id == focus } : nil) ?? shots.last
    }
    /// Shots are what is drawn, and not a refusal over them.
    var showsShots: Bool { refusal == nil && !shots.isEmpty }
    /// More than one shot, folded.
    var isPile: Bool { refusal == nil && shots.count > 1 && !unfolded }

    // MARK: - The list

    /// A new shot, the newest. The one past `ShotShelf.limit` pushes the oldest out, and with it everything that
    /// shot held.
    @discardableResult
    func add(_ image: CGImage, caption: String?, file: URL?, full: CGImage? = nil, reading: ShotReading? = nil) -> Shot.ID {
        nextID += 1
        let out = ShotShelf.add(Shot(id: nextID, image: image, caption: caption, file: file, full: full, reading: reading),
                                to: &shots)
        if out.contains(where: { $0.id == focus }) { focus = nil }
        return nextID
    }

    /// False when no such shot is on the list any more.
    @discardableResult
    func update(_ id: Shot.ID, _ change: (inout Shot) -> Void) -> Bool {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return false }
        change(&shots[index])
        return true
    }

    func remove(_ id: Shot.ID) {
        shots.removeAll { $0.id == id }
        if focus == id { focus = nil }
    }

    func say(_ refusal: Content?) {
        if case .picture? = refusal { return }
        self.refusal = refusal
    }

    // MARK: - What a shot offers

    /// What «Edit» opens on, nil while there is nothing it could: the written file with its reading, or the held
    /// picture of a shot that was only copied. A file with no reading is not offered, since nothing could say
    /// later that it is still that file.
    func editSource(of shot: Shot) -> (shot: WrittenShot?, held: CGImage?)? {
        guard shot.caption != nil else { return nil }
        if let file = shot.file { return shot.reading.map { (WrittenShot(url: file, reading: $0), nil) } }
        return shot.full.map { (nil, $0) }
    }

    var editSource: (shot: WrittenShot?, held: CGImage?)? {
        guard refusal == nil, let current else { return nil }
        return editSource(of: current)
    }

    /// What a drag of one shot carries, nil until the shot is written or copied.
    func drag(of shot: Shot) -> ShotDrag? {
        guard shot.caption != nil else { return nil }
        // A path that is gone is not carried: the drop would receive a name with nothing behind it.
        if let file = shot.file { return FileManager.default.fileExists(atPath: file.path) ? .file(file) : nil }
        return shot.full.map { .picture($0) }
    }

    /// What a drag that began on this shot carries beside the shot itself: every other shot of a folded pile, which
    /// leaves as one; nothing from the row or from a single shot.
    func othersDragged(with id: Shot.ID) -> [ShotDrag] {
        isPile ? shots.filter { $0.id != id }.compactMap { drag(of: $0) } : []
    }

    // MARK: - From the views

    /// The pointer's coming and going over the single shot or the pile.
    func pointer(over: Bool) {
        hovering = over
        hoverChanged(over)
    }

    /// The pointer's coming and going over one shot's view. In the row it moves the capsule to that shot. Folded, only
    /// the newest shot's view counts: the slivers of the sheets under it would answer an exit after the top
    /// sheet's enter, and take the capsule from under the pointer.
    func pointer(over: Bool, shot id: Shot.ID, view: NSView?) {
        if unfolded {
            if over {
                focus = id
                focused = view
            } else if focus == id {
                focus = nil
            }
        } else if id == shots.last?.id {
            pointer(over: over)
        }
    }

    /// A click on a shot: on the pile it unfolds the row; on a shot of the row, or on the single shot, it is «Edit».
    func clicked(_ id: Shot.ID) {
        if isPile { return unfold() }
        if unfolded { focus = id }
        edit()
    }
}
