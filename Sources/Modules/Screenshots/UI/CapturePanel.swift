import AppKit
import Combine
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

/// What the bar shows and writes. The options are the module's own settings —
/// the same keys the settings page writes — so the bar and the page cannot hold
/// two answers: every change is written to the store and read back from it.
@MainActor final class CapturePanelModel: ObservableObject {
    @Published private(set) var settings: ScreenshotsSettings
    /// Seconds still to wait, while a countdown is running; nil otherwise.
    @Published var countdown: Int?
    private let store: NamespacedStore
    /// Capture in the mode shown; set by the controller.
    var capture: (PanelMode) -> Void = { _ in }
    /// Close the bar and everything behind it; set by the controller.
    var cancel: () -> Void = {}

    private var storeChanged: AnyCancellable?

    init(store: NamespacedStore) {
        self.store = store
        settings = ScreenshotsSettings.read(store)
        // The settings page writes the same keys while the bar is up; the bar
        // takes what the store holds now rather than what `show()` read.
        storeChanged = NotificationCenter.default.publisher(for: .helmStoreChanged)
            .sink { [weak self] _ in self?.reload() }
    }

    var mode: PanelMode { settings.panelMode }
    var counting: Bool { countdown != nil }

    func choose(_ mode: PanelMode) {
        store.set(mode.rawValue, for: ScreenshotsSettings.Key.panelMode)
        reload()
    }

    func choose(_ timer: CaptureTimer) {
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        reload()
    }

    /// «Other…» asks for the folder, and the target is written only once there
    /// is one the capture will accept — the page's own judgement, from the same
    /// function.
    func choose(_ target: SaveTarget) {
        if target == .other {
            guard case .chosen(let path) = ScreenshotsSettingsPage.askForFolder() else { reload(); return }
            store.set(path, for: ScreenshotsSettings.Key.otherFolder)
        }
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        reload()
    }

    func setThumbnail(_ on: Bool) { store.set(on, for: ScreenshotsSettings.Key.thumbnail); reload() }
    func setRemember(_ on: Bool) { ScreenshotsSettings.setRememberSelection(on, in: store); reload() }
    func setCursor(_ on: Bool) { store.set(on, for: ScreenshotsSettings.Key.showCursor); reload() }

    /// What the settings are now, from the store: the page may have changed one.
    func reload() {
        let now = ScreenshotsSettings.read(store)
        if now != settings { settings = now }
    }
}

/// The glass bar: Whole screen, Window, Area, the options and Capture, and a
/// close control. **A non-activating key panel** — it reads Esc and Return
/// without making Helm the active application, so the person's own app keeps
/// its focus and its menu bar — in every Space and over full-screen apps, at
/// the level the toast uses. Closed before the freeze, and the freeze excludes
/// Helm's own windows besides.
@MainActor final class CapturePanel {
    let model: CapturePanelModel
    private var panel: BarPanel?

    init(store: NamespacedStore) {
        model = CapturePanelModel(store: store)
    }

    /// Bottom centre of the screen the pointer is on, above the Dock.
    func show() {
        model.reload()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        model.countdown = nil
    }

    /// Not private: a test reads the content view without ordering anything in.
    func makePanel() -> BarPanel {
        let panel = BarPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 56))
        panel.onCancel = { [weak self] in self?.model.cancel() }
        panel.onCapture = { [weak self] in
            guard let self, !self.model.counting else { return }
            self.model.capture(self.model.mode)
        }
        let host = FirstMouseHostingView(rootView: CapturePanelView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }

    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 24))
    }
}

/// The bar's content, which acts on the click that reaches it. The bar is a
/// non-activating panel and may not be key when the pointer comes (another app
/// holds the keyboard), and a view that refuses first mouse spends that click
/// on becoming key — so ✕ would need two presses while a countdown runs.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class BarPanel: NSPanel {
    var onCancel: () -> Void = {}
    var onCapture: () -> Void = {}

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onCancel() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onCapture()
        // Esc is also `cancelOperation`, but only when the responder chain gets that far.
        case 53: onCancel()
        default: super.keyDown(with: event)
        }
    }
}

struct CapturePanelView: View {
    @ObservedObject var model: CapturePanelModel

    var body: some View {
        HStack(spacing: HelmSpace.s4) {
            closeControl
            HStack(spacing: HelmSpace.s1) {
                modeControl(.screen, symbol: "display", name: ScStr.panelScreen)
                modeControl(.window, symbol: "macwindow", name: ScStr.panelWindow)
                modeControl(.area, symbol: "rectangle.dashed", name: ScStr.panelArea)
            }
            .disabled(model.counting)
            optionsMenu
                .disabled(model.counting)
            trailing
        }
        .padding(HelmSpace.s4)
        // Glass and no edge of our own: it carries its own.
        .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
        .animation(HelmMotion.interface, value: model.countdown)
    }

    private var closeControl: some View {
        Button { model.cancel() } label: {
            Image(systemName: "xmark")
                .font(HelmText.rowDetail)
                .frame(width: HelmSpace.s7, height: HelmSpace.s7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(ScStr.closePanel)
        .accessibilityLabel(ScStr.closePanel)
    }

    private func modeControl(_ mode: PanelMode, symbol: String, name: String) -> some View {
        let selected = model.mode == mode
        return Button { model.choose(mode) } label: {
            Image(systemName: symbol)
                .font(HelmText.rowTitle)
                .frame(width: HelmSpace.s7 + HelmSpace.s4, height: HelmSpace.s7)
                .background(Color.primary.opacity(selected ? 0.14 : 0), in: .rect(cornerRadius: HelmRadius.ctl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var optionsMenu: some View {
        Menu {
            Picker(ScStr.saveTo, selection: Binding(get: { model.settings.saveTarget },
                                                    set: { model.choose($0) })) {
                ForEach(SaveTarget.allCases, id: \.self) { Text(ScStr.target($0)).tag($0) }
            }
            Picker(ScStr.timer, selection: Binding(get: { model.settings.timer },
                                                   set: { model.choose($0) })) {
                ForEach(CaptureTimer.allCases, id: \.self) { Text(ScStr.timer($0)).tag($0) }
            }
            Toggle(ScStr.floatingThumbnail, isOn: Binding(get: { model.settings.thumbnail },
                                                          set: { model.setThumbnail($0) }))
            Toggle(ScStr.rememberSelection, isOn: Binding(get: { model.settings.rememberSelection },
                                                          set: { model.setRemember($0) }))
            Toggle(ScStr.showCursor, isOn: Binding(get: { model.settings.showCursor },
                                                   set: { model.setCursor($0) }))
        } label: {
            Text(ScStr.options)
        }
        .menuStyle(.button)
        .fixedSize()
        .accessibilityLabel(ScStr.options)
    }

    /// The button, and — while a countdown runs — the seconds left laid over it.
    /// **The button stays in the layout, unseen and unpressable, and the number
    /// is centred on it**, so the content is exactly as wide counting as idle in
    /// every language and ✕ and the bar's edges stay where the pointer found
    /// them. A fixed minimum width for the digit was a guess at the button's
    /// width and was wrong wherever the word is longer; the button measures
    /// itself.
    @ViewBuilder private var trailing: some View {
        ZStack {
            Button(ScStr.captureButton) { model.capture(model.mode) }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(model.counting)
                .opacity(model.counting ? 0 : 1)
                .accessibilityHidden(model.counting)
            if let seconds = model.countdown {
                Text(String(seconds))
                    .font(HelmText.metricFont)
                    .accessibilityLabel(ScStr.timer)
                    .accessibilityValue(String(seconds))
            }
        }
    }
}
