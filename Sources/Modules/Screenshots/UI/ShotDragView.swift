import AppKit
import SwiftUI
import Module_Screenshots_Engine

/// What a person takes away by dragging the thumbnail: **the file when one was written, the picture as a PNG when the
/// shot is only on the clipboard.** Nil while the shot is still being written: neither exists yet, and a drag that
/// carried the thumbnail's reduced copy would drop a `ShotThumbnail.longestEdge`-pixel picture into somebody's document.
enum ShotDrag {
    case file(URL)
    case picture(CGImage)

    /// What the pasteboard gets. **A picture's PNG is encoded when a drop asks for it, not when the drag begins**
    /// (`PictureProvider`): a pile's drag starts as cheaply as one shot's whatever its size, and only the pictures a
    /// target takes are ever encoded, one at a time. A file goes by its URL.
    func writer() -> NSPasteboardWriting? {
        switch self {
        case .file(let url): return url as NSURL
        case .picture(let image):
            let provider = PictureProvider(image)
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.png])
            // The item does not keep its provider alive, and the provider is asked after the drag has begun.
            objc_setAssociatedObject(item, &PictureProvider.key, provider, .OBJC_ASSOCIATION_RETAIN)
            return item
        }
    }
}

/// Encodes a held picture as a PNG at the moment a pasteboard item is read.
private final class PictureProvider: NSObject, NSPasteboardItemDataProvider {
    nonisolated(unsafe) static var key = 0
    private let image: CGImage
    init(_ image: CGImage) { self.image = image }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .png, let png = CaptureSession.encode(image, as: .png) else { return }
        item.setData(png, forType: .png)
    }
}

/// The thumbnail's own view: the drag's source, the pointer's tracking and the click, and the view the Share sheet is
/// anchored at. One AppKit view for the four: a drag session begins from the mouse event itself, and a tracking
/// area with `.activeAlways` is the option that asks nothing of the window's or the app's state (NSTrackingArea.h).
/// That a drag from a panel that is never key, and the hover over it, work as written is not measured: parked.
final class ShotDragView: NSView, NSDraggingSource {
    /// Asked when a drag begins, so a drag that begins after the file was written carries the file.
    var payload: () -> ShotDrag? = { nil }
    /// What the drag carries beside `payload`: the other shots of a folded pile, which leaves as one. Asked when a
    /// drag begins, after `payload` answered.
    var others: () -> [ShotDrag] = { [] }
    var preview: CGImage?
    /// The picture's own size and side inside this view, which is larger than the picture while the capsule is up
    /// over a small shot: what a drag shows as its frame is the picture, not the zone.
    var pictureSize: CGSize?
    var trailing = false
    /// Where the picture is in this view: on its lower edge, against its trailing edge or in its middle.
    var pictureFrame: NSRect {
        let size = pictureSize ?? bounds.size
        return NSRect(x: trailing ? bounds.maxX - size.width : bounds.midX - size.width / 2, y: bounds.minY,
                      width: size.width, height: size.height)
    }
    var onClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    /// A scroll over the view, in points toward the row's oldest shot, and whether they are points at all
    /// (`hasPreciseScrollingDeltas`) or a wheel's notches.
    var onScroll: (CGFloat, Bool) -> Void = { _, _ in }
    /// The view is on a window: the Share sheet may be shown relative to it.
    var onWindow: (ShotDragView) -> Void = { _ in }
    private var pressed: NSPoint?
    private static let slop: CGFloat = 4

    override var mouseDownCanMoveWindow: Bool { false }
    /// What AppKit asks of a click that lands on a window that is not key (NSView.h). Whether this nonactivating panel
    /// needs the answer is not measured: parked.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindow(self) }
    }

    /// **One area for the view's life.** `.inVisibleRect` keeps it on the view's rect through every change of frame, so
    /// there is nothing to rebuild; AppKit calls this on each such change. Measured: without the guard the area was
    /// rebuilt 7-12 times while the capsule came up over a shot lower or narrower than it (`ShotToast.picture`'s zone),
    /// 0 with it. Inferred, not measured (no test has a real pointer): that a rebuilt area under a still pointer is an
    /// exit, which takes the capsule away and starts the zone's change over.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) { pressed = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressed,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= Self.slop else { return }
        pressed = nil
        // The pile leaves under the pressed sheet's picture: the others are carried and not drawn. A pressed sheet that
        // is still being written carries nothing itself, and the finished shots under it leave all the same.
        let writers = ([payload()?.writer()] + others().map { $0.writer() }).compactMap { $0 }
        guard !writers.isEmpty else { return }
        let frame = pictureFrame
        let picture = preview.map { NSImage(cgImage: $0, size: frame.size) }
        let items = writers.enumerated().map { index, writer in
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(frame, contents: index == 0 ? picture : nil)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    /// Sideways as it comes; a wheel that only turns one way scrolls the row with it, down being toward the oldest.
    /// Which way a person expects a vertical wheel to move a row is not measured.
    override func scrollWheel(with event: NSEvent) {
        let across = event.scrollingDeltaX, along = event.scrollingDeltaY
        onScroll(abs(across) >= abs(along) ? across : -along, event.hasPreciseScrollingDeltas)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed != nil else { return }
        pressed = nil
        onClick()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// `ShotDragView` in one shot's picture, over it and under the capsule. A click on it is «Edit», or on a folded
/// pile the row (`ShotToastModel.clicked`). The newest shot's view is the model's anchor, in whichever shape.
struct ShotDragSource: NSViewRepresentable {
    let model: ShotToastModel
    let shot: ShotToastModel.Shot.ID
    let preview: CGImage
    let picture: CGSize
    let trailing: Bool
    let newest: Bool

    func makeNSView(context: Context) -> ShotDragView {
        let view = ShotDragView()
        let shot = shot
        view.payload = { [weak model] in model?.shots.first { $0.id == shot }.flatMap { model?.drag(of: $0) } }
        view.others = { [weak model] in model?.othersDragged(with: shot) ?? [] }
        view.onClick = { [weak model] in model?.clicked(shot) }
        view.onHover = { [weak model, weak view] over in model?.pointer(over: over, shot: shot, view: view) }
        view.onScroll = { [weak model] delta, precise in model?.scroll(delta, precise) }
        view.onWindow = { [weak model] view in
            if model?.shots.last?.id == shot { model?.anchor = view }
        }
        return view
    }

    func updateNSView(_ view: ShotDragView, context: Context) {
        view.preview = preview
        view.pictureSize = picture
        view.trailing = trailing
        // A shot becomes the newest without leaving its window: the one over it was closed.
        if newest, view.window != nil, model.anchor !== view { model.anchor = view }
    }
}
