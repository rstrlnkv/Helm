import AppKit
import SwiftUI
import Module_Screenshots_Engine

/// What a person takes away by dragging the thumbnail: **the file when one was written, the picture as a PNG when the
/// shot is only on the clipboard.** Nil while the shot is still being written: neither exists yet, and a drag that
/// carried the thumbnail's reduced copy would drop a `ShotThumbnail.longestEdge`-pixel picture into somebody's document.
enum ShotDrag {
    case file(URL)
    case picture(CGImage)

    /// What the pasteboard gets. A PNG is encoded here, at the drag's start, and not before: most thumbnails are never dragged.
    func writer() -> NSPasteboardWriting? {
        switch self {
        case .file(let url): return url as NSURL
        case .picture(let image):
            guard let png = CaptureSession.encode(image, as: .png) else { return nil }
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            return item
        }
    }
}

/// The thumbnail's own view: the drag's source, the pointer's tracking and the click, and the view the Share sheet is
/// anchored at. One AppKit view for the four: a drag session begins from the mouse event itself, and a tracking
/// area with `.activeAlways` is the option that asks nothing of the window's or the app's state (NSTrackingArea.h).
/// That a drag from a panel that is never key, and the hover over it, work as written is not measured: parked.
final class ShotDragView: NSView, NSDraggingSource {
    /// Asked when a drag begins, so a drag that begins after the file was written carries the file.
    var payload: () -> ShotDrag? = { nil }
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
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
        guard let writer = payload()?.writer() else { return }
        let item = NSDraggingItem(pasteboardWriter: writer)
        let frame = pictureFrame
        let picture = preview.map { NSImage(cgImage: $0, size: frame.size) }
        item.setDraggingFrame(frame, contents: picture)
        beginDraggingSession(with: [item], event: event, source: self)
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

/// `ShotDragView` in the thumbnail's picture, over it and under the capsule. A click on it is «Edit».
struct ShotDragSource: NSViewRepresentable {
    let model: ShotToastModel
    let preview: CGImage
    let picture: CGSize
    let trailing: Bool

    func makeNSView(context: Context) -> ShotDragView {
        let view = ShotDragView()
        view.payload = { [weak model] in model?.dragPayload }
        view.onClick = { [weak model] in model?.edit() }
        view.onHover = { [weak model] over in model?.pointer(over: over) }
        view.onWindow = { [weak model] view in model?.anchor = view }
        return view
    }

    func updateNSView(_ view: ShotDragView, context: Context) {
        view.preview = preview
        view.pictureSize = picture
        view.trailing = trailing
    }
}
