import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// What the toast says. One floating panel for both: the thumbnail that follows
/// a capture, and the refusal that follows one that did not happen.
@MainActor final class ShotToastModel: ObservableObject {
    enum Content {
        case picture(CGImage, caption: String?, file: URL?)
        case refusal(title: String, body: String, offersSettings: Bool)
    }
    @Published var content: Content?
    @Published var shown = false
    /// The pointer is over the picture: the capsule is up.
    @Published var hovering = false
    /// What the close control does: the toast's own `dismiss`, set by its owner.
    var dismiss: () -> Void = {}
    /// What the capsule's Copy and Pin do, and what the pointer's coming and going tells the toast's clock: set by its owner.
    var copy: () -> Void = {}
    var pin: () -> Void = {}
    var hoverChanged: (Bool) -> Void = { _ in }
    /// The thumbnail's own view, which the Share sheet is shown relative to; set by that view once it is on a window.
    weak var anchor: NSView? { didSet { if anchor != nil { anchorAttached() } } }
    var anchorAttached: () -> Void = {}
    /// The full picture of a shot that was only copied: a thumbnail is a reduced copy, and a drag or a share of it
    /// would hand over `ShotThumbnail.longestEdge` pixels. A shot with a file holds none, and is read back from the file when asked.
    var full: CGImage?

    /// The pointer's coming and going, from the thumbnail's view.
    func pointer(over: Bool) {
        hovering = over
        hoverChanged(over)
    }

    /// What a drag carries, nil until the shot is written or copied.
    var dragPayload: ShotDrag? {
        guard case .picture(_, let caption, let file)? = content, caption != nil else { return nil }
        // A path that is gone is not carried: the drop would receive a name with nothing behind it.
        if let file { return FileManager.default.fileExists(atPath: file.path) ? .file(file) : nil }
        return full.map { .picture($0) }
    }

    /// A click on the thumbnail: the file in the system's own viewer, until the editor opens from here.
    func open() {
        guard case .picture(_, _, let file?)? = content else { return }
        NSWorkspace.shared.open(file)
    }
}

/// What the capsule over a thumbnail offers, in order; the ✕ stands after a divider. «Show in Finder» only for a
/// shot that has a file, and Pin only while `PinEntry.isOffered`.
enum ShotCapsule {
    enum Cell: Equatable { case copy, reveal, pin, close }

    static func cells(hasFile: Bool, pinOffered: Bool = PinEntry.isOffered) -> [Cell] {
        var cells: [Cell] = [.copy]
        if hasFile { cells.append(.reveal) }
        if pinOffered { cells.append(.pin) }
        return cells + [.close]
    }

    /// Between a cell and the capsule's edge: the mockup's 4 pt, so a 28 pt cell makes a capsule 36 pt high.
    static let inset = HelmSpace.s2
    /// The divider's height and each side's air. The mockup's 22 pt is on no step of `HelmSpace`, whose steps are
    /// 2 · 4 · 6 · 8 · 12 · 18 · 28 · 40.
    static let separatorHeight: CGFloat = 22
    static let separatorGap = HelmSpace.s2
    private static let dividerWidth: CGFloat = 1

    /// The capsule's width for a number of cells, the ✕ counted. Computed from the numbers the capsule is laid out by.
    static func width(cellCount: Int) -> CGFloat {
        CGFloat(cellCount) * HelmSpace.s7 + dividerWidth + 2 * separatorGap + 2 * inset
    }

    /// The widest the capsule can be while the picture is not wider: the room the window keeps for it.
    static var widest: CGFloat { width(cellCount: cells(hasFile: true).count) }
}

@MainActor final class ShotToast {
    /// Not private: a test wires the close control through it without a panel.
    let model = ShotToastModel()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    /// One step of the lifetime's clock. A seam: a test passes a wait it controls, and the running app sleeps.
    private let tick: (Duration) async throws -> Void
    /// Whether to put a panel on the screen; a test builds none.
    private let windowed: Bool
    /// Whether the pointer is inside the anchor view's rect, in screen points. Asked by `advance`: under a hold that only
    /// the pointer keeps, to end it when the pointer is elsewhere, and when the time is up, to hold when it is there. A
    /// seam for a test.
    var pointerIsOver: () -> Bool
    /// What the capsule's Copy and Pin ask of whoever owns the session and the board.
    var onCopy: () -> Void = {}
    var onPin: (CGImage, CGRect) -> Void = { _, _ in }
    /// Closes a sheet that is open. A seam: a test reads which sheet was closed, and the running app asks the picker.
    var closePicker: (NSSharingServicePicker) -> Void = { $0.close() }
    /// Shows the sheet relative to the thumbnail's view. A seam: a test must not open a system sheet.
    var presentPicker: (NSSharingServicePicker, NSView) -> Void = { picker, view in
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    /// What keeps the lifetime from running: the pointer over the picture, the Share sheet open.
    enum Hold: Hashable { case pointer, sheet }
    private(set) var holds: Set<Hold> = []
    /// Seconds of life left, counted only while nothing holds it.
    private(set) var remaining: Double = 0
    private var wantsShare = false
    private var picker: NSSharingServicePicker?
    private var pickerDelegate: PickerDelegate?

    private static let step = 0.1

    init(tick: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, windowed: Bool = true) {
        self.tick = tick
        self.windowed = windowed
        let model = self.model
        self.pointerIsOver = { [weak model] in
            guard let anchor = model?.anchor, let window = anchor.window else { return false }
            return window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).contains(NSEvent.mouseLocation)
        }
        model.dismiss = { [weak self] in self?.dismiss() }
        model.hoverChanged = { [weak self] over in self?.setHover(over) }
        model.copy = { [weak self] in self?.onCopy() }
        model.pin = { [weak self] in self?.pin() }
        model.anchorAttached = { [weak self] in self?.attemptShare() }
    }

    /// The picture at once, before the write has finished: encoding a
    /// full-resolution frame is not instant, and the person is waiting to see that
    /// something happened. The caption arrives with the result.
    func showWorking(_ image: CGImage) {
        present(.picture(Self.thumbnail(of: image), caption: nil, file: nil), lasting: 6)
    }

    /// `share` also opens the system's Share sheet at the thumbnail once it is up.
    func showDone(_ image: CGImage, caption: String, file: URL?, share: Bool = false) {
        present(.picture(Self.thumbnail(of: image), caption: caption, file: file), lasting: 5)
        model.full = file == nil ? image : nil
        if share { requestShare() }
    }

    func showRefusal(_ reason: CaptureRefusal) {
        present(Self.refusalContent(reason), lasting: 9)
    }

    /// What a refusal says, and whether it offers «Open Settings» — **only for
    /// the grant**. A button that cannot do what it says is worse than none: a
    /// full disk is not mended in the Privacy pane. Its own function so the
    /// decision is one a test can ask without a window.
    static func refusalContent(_ reason: CaptureRefusal) -> ShotToastModel.Content {
        let permission = reason == .noPermission
        return .refusal(title: permission ? ScStr.noPermissionTitle : ScStr.failedTitle,
                        body: ScStr.refusal(reason), offersSettings: permission)
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        // A sheet left open under a window that is gone would sit beside the one the next Share opens.
        if let picker { closePicker(picker) }
        resetHolds()
        model.shown = false
        panel?.orderOut(nil)
        panel = nil
        model.content = nil
        model.full = nil
    }

    // MARK: - How long it lives

    /// The pointer came onto the picture or left it. The lifetime that was running goes on from what was left.
    func setHover(_ over: Bool) {
        model.hovering = over
        if over { holds.insert(.pointer) } else { holds.remove(.pointer) }
    }

    /// One step of the clock: true when the toast's time is up. **The pointer's events are not trusted either way.** A
    /// pointer that is over the picture when the time runs out holds it, though no enter was sent; and a hold that only
    /// the pointer keeps ends at the first step that finds the pointer elsewhere, though no exit was sent. Whether
    /// AppKit sends an exit when the panel moves from under a still pointer or the view is removed is not measured;
    /// `pointerIsOver` is asked instead of relying on it.
    func advance(by seconds: Double = ShotToast.step) -> Bool {
        if holds == [.pointer], !pointerIsOver() { setHover(false) }
        guard holds.isEmpty else { return false }
        // A step is time that passed: one that is not a number passed none, a negative one gave nothing back, and an
        // endless one ends the life.
        remaining -= seconds.clamped(to: 0...Double.infinity, whenNotANumber: 0)
        guard remaining <= 0 else { return false }
        if pointerIsOver() { setHover(true); return false }
        return true
    }

    /// A sheet that is open stays open across a new shot or a refusal: it is still on the screen at this very view,
    /// and only `dismiss` takes it, and closes it.
    private func resetHolds(keepingSheet: Bool = false) {
        let sheet = keepingSheet && holds.contains(.sheet)
        holds = sheet ? [.sheet] : []
        model.hovering = false
        wantsShare = false
        if !sheet {
            picker = nil
            pickerDelegate = nil
        }
    }

    // MARK: - Share

    /// Asks for the system's Share sheet at this shot's thumbnail, as soon as the thumbnail's view is on a window. The
    /// toast holds from the sheet's opening to its end: the lifetime would otherwise close the panel under the
    /// sheet. How the pointer's events go while the sheet is up is not measured.
    func requestShare() {
        wantsShare = true
        attemptShare()
    }

    /// What the sheet shares: the file when there is one, else the picture.
    func shareItems() -> [Any]? {
        guard case .picture(_, _, let file)? = model.content else { return nil }
        if let file { return [file] }
        return model.full.map { [NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))] }
    }

    private func attemptShare() {
        guard wantsShare, let anchor = model.anchor else { return }
        // One sheet at a time; a second request is the first one's.
        guard picker == nil else { wantsShare = false; return }
        // No sheet over a path that is gone.
        if case .picture(_, _, let file?)? = model.content, !FileManager.default.fileExists(atPath: file.path) {
            wantsShare = false
            return
        }
        guard let items = shareItems() else { return }
        wantsShare = false
        let picker = NSSharingServicePicker(items: items)
        let delegate = PickerDelegate()
        // The end of a sheet that was dismissed or replaced is not the end of the one that stands.
        delegate.ended = { [weak self, weak delegate] in
            guard let self, let delegate, self.pickerDelegate === delegate else { return }
            self.sheetEnded()
        }
        picker.delegate = delegate
        self.picker = picker
        pickerDelegate = delegate
        holds.insert(.sheet)
        presentPicker(picker, anchor)
    }

    /// The sheet is over, chosen from or cancelled.
    func sheetEnded() {
        holds.remove(.sheet)
        picker = nil
        pickerDelegate = nil
    }

    private final class PickerDelegate: NSObject, NSSharingServicePickerDelegate {
        var ended: () -> Void = {}
        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) { ended() }
    }

    // MARK: - What the capsule does

    /// The shot's full picture: held for a shot that was only copied, read back from its file for a saved one.
    func fullPicture() -> CGImage? {
        if let full = model.full { return full }
        guard case .picture(_, _, let file?)? = model.content,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The picture as a pin, where the thumbnail stands; the toast goes.
    private func pin() {
        guard let image = fullPicture(), let anchor = model.anchor, let window = anchor.window else { return }
        onPin(image, window.convertToScreen(anchor.convert(anchor.bounds, to: nil)))
        dismiss()
    }

    // MARK: -

    private func present(_ content: ShotToastModel.Content, lasting seconds: Double) {
        dismissal?.cancel()
        model.full = nil
        // The pointer stays held across a picture that replaces a picture, the write's result over its working
        // thumbnail above all: the view is the same one. Whether AppKit sends a new enter for a pointer that never
        // left is not measured, and a hold dropped here would not come back.
        var pictures = 0
        for shown in [model.content, content] { if case .picture? = shown { pictures += 1 } }
        let stillOver = model.hovering && pictures == 2
        resetHolds(keepingSheet: true)
        if stillOver { setHover(true) }
        remaining = seconds
        model.content = content
        if windowed {
            let panel = self.panel ?? makePanel()
            self.panel = panel
            place(panel)
            panel.orderFrontRegardless()
        }
        model.shown = true
        dismissal = Task { [weak self] in
            while true {
                do { try await self?.tick(.milliseconds(Int(Self.step * 1000))) } catch { return }
                guard !Task.isCancelled, let self else { return }
                if self.advance() { break }
            }
            self?.model.shown = false
            // After the fade, not at the same moment.
            try? await self?.tick(.milliseconds(Int(HelmMotion.interfaceDuration * 1000)))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.model.content = nil
            self?.model.full = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: ShotToastView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }

    /// Lower right of the screen the pointer is on, inside the visible frame; a picture stands 20 pt from the edges
    /// itself, the room round it that its shadow is drawn in not counted.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        let size = panel.frame.size
        var inset: CGFloat = 20
        if case .picture? = model.content { inset -= Self.shadowRoom }
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset))
    }

    /// The refusal's width.
    static let width: CGFloat = 252
    /// Clear round the picture for its shadow: the panel's own is off, and the picture's is drawn in this room. The
    /// shadow's blur and its offset down, both of the mockup's, fit in it.
    static let shadowRoom = HelmSpace.s8

    /// Small enough to hold for the few seconds the toast lives without holding
    /// the frame: a 5K picture is tens of megabytes and this is a small fraction of that.
    static func thumbnail(of image: CGImage) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        let target = ShotThumbnail.longestEdge
        guard longest > target else { return image }
        let scale = target / longest
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

struct ShotToastView: View {
    @ObservedObject var model: ShotToastModel

    var body: some View {
        Group {
            switch model.content {
            case .picture(let image, let caption, let file):
                picture(image, caption: caption, file: file)
                    .padding(ShotToast.shadowRoom)
            case .refusal(let title, let body, let offersSettings):
                refusal(title: title, body: body, offersSettings: offersSettings)
                    .padding(HelmSpace.s5)
                    .frame(width: ShotToast.width)
                    // Glass and no edge of our own: it carries its own.
                    .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
            case nil:
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .opacity(model.shown ? 1 : 0)
        .offset(x: model.shown ? 0 : 24)
        .animation(HelmMotion.interface, value: model.shown)
    }

    /// The shot alone, in a white frame: the thumbnail macOS shows. The caption is not on the screen; it is the value
    /// a screen reader reads. The capsule comes up from the lower edge while the pointer is over it, and only when
    /// the result is in, since Copy and Show in Finder need what was written.
    private func picture(_ image: CGImage, caption: String?, file: URL?) -> some View {
        let size = ShotThumbnail.fitted(pixels: CGSize(width: image.width, height: image.height))
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Self.pictureRadius))
            .overlay { ShotDragSource(model: model, preview: image) }
            .overlay(alignment: .bottom) {
                if model.hovering, caption != nil { capsule(hasFile: file != nil) }
            }
            .padding(Self.frameWidth)
            // The shadow belongs to the ring's own shape: the capsule's glass and glyphs on the picture cast none.
            .background {
                RoundedRectangle(cornerRadius: Self.pictureRadius + Self.frameWidth)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
            }
            // Room for the capsule where the picture is narrower than it; the ring stays round the picture.
            .frame(minWidth: ShotCapsule.widest)
            .animation(HelmMotion.interface, value: model.hovering)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ScStr.thumbnailLabel)
            .accessibilityValue(caption ?? "")
    }

    /// The mockup's 3 pt white ring and 5 pt picture corner (the ring's outer corner is 8). `HelmRadius` has
    /// 4 · 6 · 10 · 14 · 26, so neither corner is on the ladder, and the ring has no token.
    private static let frameWidth: CGFloat = 3
    private static let pictureRadius: CGFloat = 5

    /// «Copy · Show in Finder (· Pin) | ✕», on glass, 8 pt up from the picture's lower edge.
    private func capsule(hasFile: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(ShotCapsule.cells(hasFile: hasFile), id: \.self) { cell in
                switch cell {
                case .copy: GlassCell(symbol: "doc.on.doc", name: ScStr.copy) { model.copy() }
                case .reveal: GlassCell(symbol: "folder", name: ScStr.showInFinder) { reveal() }
                case .pin: GlassCell(symbol: "pin", name: ScStr.pin) { model.pin() }
                case .close:
                    Divider().frame(height: ShotCapsule.separatorHeight).padding(.horizontal, ShotCapsule.separatorGap)
                    closeCell
                }
            }
        }
        .padding(ShotCapsule.inset)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, HelmSpace.s4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func reveal() {
        guard case .picture(_, _, let file?)? = model.content else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// The way off the screen: the capsule's ✕ on a thumbnail whose result is in, and the refusal's, which stays up
    /// nine seconds in the corner where the next click goes. A thumbnail still being written has none.
    private var closeCell: some View {
        GlassCell(symbol: "xmark", name: ScStr.dismissToast) { model.dismiss() }
    }

    private func refusal(title: String, body: String, offersSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            // Clear of the close control in the corner.
            Text(title).font(HelmText.rowTitle).padding(.trailing, HelmSpace.s7)
            Text(body)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if offersSettings {
                Button(ScStr.openSettings) { PermissionNeed.screenRecording.openSettings() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { closeCell }
    }
}
