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
    /// What the close control does: the toast's own `dismiss`, set by its owner.
    var dismiss: () -> Void = {}
}

@MainActor final class ShotToast {
    /// Not private: a test wires the close control through it without a panel.
    let model = ShotToastModel()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    init() {
        model.dismiss = { [weak self] in self?.dismiss() }
    }

    /// The picture at once, before the write has finished: encoding a
    /// full-resolution frame is not instant, and the person is waiting to see that
    /// something happened. The caption arrives with the result.
    func showWorking(_ image: CGImage) {
        present(.picture(Self.thumbnail(of: image), caption: nil, file: nil), lasting: 6)
    }

    func showDone(_ image: CGImage, caption: String, file: URL?) {
        present(.picture(Self.thumbnail(of: image), caption: caption, file: file), lasting: 5)
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
        model.shown = false
        panel?.orderOut(nil)
        panel = nil
        model.content = nil
    }

    // MARK: -

    private func present(_ content: ShotToastModel.Content, lasting seconds: Double) {
        dismissal?.cancel()
        model.content = content
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        model.shown = true
        dismissal = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.model.shown = false
            // After the fade, not at the same moment.
            try? await Task.sleep(nanoseconds: UInt64(HelmMotion.interfaceDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.model.content = nil
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

    /// Lower right of the screen the pointer is on, inside the visible frame.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 20, y: visible.minY + 20))
    }

    static let width: CGFloat = 252

    /// Small enough to hold for the few seconds the toast lives without holding
    /// the frame: a 5K picture is tens of megabytes and this is a small fraction of that.
    static func thumbnail(of image: CGImage) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        let target: CGFloat = 520
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
            case .refusal(let title, let body, let offersSettings):
                refusal(title: title, body: body, offersSettings: offersSettings)
            case nil:
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .padding(HelmSpace.s5)
        .frame(width: ShotToast.width)
        // Glass and no edge of our own: it carries its own.
        .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
        .opacity(model.shown ? 1 : 0)
        .offset(x: model.shown ? 0 : 24)
        .animation(HelmMotion.interface, value: model.shown)
    }

    private func picture(_ image: CGImage, caption: String?, file: URL?) -> some View {
        let content = VStack(alignment: .leading, spacing: HelmSpace.s3) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 150)
                .clipShape(.rect(cornerRadius: HelmRadius.tiny))
            // The caption's line is there from the first frame, empty until the
            // result arrives: the plate is pinned by its bottom edge, and a
            // line that appeared after the picture moved the picture up by its
            // own height a moment after it was shown.
            Text(caption ?? " ").font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .opacity(caption == nil ? 0 : 1)
                .accessibilityHidden(caption == nil)
        }
        return Group {
            if let file {
                // A click opens the file: the one thing a person does with a
                // thumbnail they have just taken.
                Button { NSWorkspace.shared.open(file) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ScStr.thumbnailLabel)
            } else {
                content.accessibilityElement(children: .combine)
                    .accessibilityLabel(ScStr.thumbnailLabel)
            }
        }
        // A way off the screen that is not the open-file target: a click meant
        // for what lies under the corner would otherwise open the picture.
        .overlay(alignment: .topTrailing) { closeControl }
    }

    /// The way off the screen, for both kinds of toast: the refusal stays up
    /// nine seconds in the corner where the next click goes.
    private var closeControl: some View {
        Button { model.dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(HelmText.rowDetail)
                .foregroundStyle(.white, .black.opacity(0.55))
                .frame(width: HelmSpace.s7, height: HelmSpace.s7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ScStr.dismissToast)
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
        .overlay(alignment: .topTrailing) { closeControl }
    }
}
