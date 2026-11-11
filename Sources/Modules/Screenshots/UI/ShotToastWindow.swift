import SwiftUI
import HelmUI
import Module_Screenshots_Engine

extension ShotToast {
    func makePanel() -> ShotPanel {
        let panel = ShotPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isUnfolded = { [weak model] in model?.unfolded ?? false }
        panel.onEscape = { [weak self] in self?.fold() }
        // The shots stand against the panel's lower trailing corner whatever its size: a row that folds is drawn
        // inside the row's panel until the fold is over, and must not be centred in it meanwhile.
        let host = NSHostingView(rootView: ShotToastView(model: model).helmRoot())
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        let ground = NSView()
        ground.addSubview(host)
        NSLayoutConstraint.activate([host.trailingAnchor.constraint(equalTo: ground.trailingAnchor),
                                     host.bottomAnchor.constraint(equalTo: ground.bottomAnchor)])
        panel.contentView = ground
        self.host = host
        return panel
    }

    /// The picture's distance from the screen's edge, off the ladder on purpose.
    static let edgeInset: CGFloat = 20

    /// Lower right of the screen the pointer is on, inside the visible frame; a picture stands `edgeInset` from the edges
    /// itself, the room round it that its shadow is drawn in not counted.
    func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if let host { panel.setContentSize(host.fittingSize) }
        let size = panel.frame.size
        var inset = Self.edgeInset
        if model.showsShots { inset -= Self.shadowRoom }
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset))
    }

    /// The panel takes the size of what it shows now and keeps its lower trailing corner: the row unfolding, a shot
    /// leaving it, the fold once it is drawn. The screen is not chosen again, as `place` would by the pointer.
    func refit() {
        guard let panel, let host else { return }
        let size = host.fittingSize, frame = panel.frame
        panel.setFrame(NSRect(x: frame.maxX - size.width, y: frame.minY, width: size.width, height: size.height),
                       display: true)
    }

    /// The refusal's width.
    static let width: CGFloat = 252
    /// Clear round the picture for its shadow: the panel's own is off, and the picture's is drawn in this room. The
    /// shadow's blur and its offset down fit in it.
    static let shadowRoom = HelmSpace.s8

    /// Small enough to hold for as long as the window lives without holding
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
