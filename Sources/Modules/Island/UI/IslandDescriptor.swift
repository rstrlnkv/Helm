import AppKit
import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Island_Engine

@MainActor public final class IslandDescriptor: ModuleDescriptor {
    public static let id = ModuleID("island")
    public static let metadata = ModuleMetadata(
        id: id, name: IsStr.moduleName, summary: IsStr.summary,
        sfSymbol: "sparkles.rectangle.stack", permissions: [])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .appearance

    private var controller: IslandWindowController?
    private var shelf: ShelfViewModel?
    private var dragMonitor: IslandDragMonitor?
    private var powerSource: IslandPowerSource?
    private var audioSource: IslandAudioSource?
    private var mediaSource: IslandMediaSource?
    private var hidTap: IslandHIDTap?
    private var store: NamespacedStore?

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        return IslandEngine(
            onActivate: { [weak self] in self?.start() },
            onDeactivate: { [weak self] in self?.stop() })
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { nil }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        guard let store else { return AnyView(EmptyView()) }
        return AnyView(IslandSettingsPage(store: store, hasNotch: IslandDescriptor.hasNotch))
    }

    static var hasNotch: Bool {
        guard let s = NSScreen.main else { return false }
        return NotchMetrics.compute(screen: s.frame, topInset: s.safeAreaInsets.top,
                                    auxTopLeftWidth: s.auxiliaryTopLeftArea?.width ?? 0) != nil
    }

    // MARK: - Lifecycle

    private func start() {
        guard controller == nil, let store else { return }
        let shelfStore = ShelfStore(store: store, bookmarks: FileBookmarkPort())
        let shelfVM = ShelfViewModel(store: shelfStore)
        self.shelf = shelfVM

        let content: (IslandModel) -> AnyView = { model in
            AnyView(IslandShelfView(shelf: shelfVM, model: model,
                                    onDropped: { [weak self] in self?.controller?.apply(.dropped) }))
        }
        let chips: (IslandModel) -> AnyView = { _ in AnyView(IslandShelfChips(shelf: shelfVM)) }
        guard let controller = IslandWindowController(makeContent: content, makeChips: chips) else { return }
        self.controller = controller
        controller.onDrop = { [weak shelfVM] urls in shelfVM?.add(urls) }

        // Reveal on drag-start anywhere (primary path; avoids Mission Control's
        // top-edge dwell). The sensor over the notch stays as a secondary path.
        if store.bool("revealOnDrag", default: true) {
            dragMonitor = IslandDragMonitor(
                onDragStarted: { [weak self] in self?.controller?.apply(.dragEntered) },
                onDragEnded: { [weak self] in self?.controller?.apply(.dragExited) })
        }
        controller.hoverEnabled = store.bool("hoverToOpen", default: true)
        controller.model.playPause = { [weak self] in
            self?.mediaSource?.playPause()
            self?.controller?.model.nowPlayingPlaying.toggle()
        }
        controller.model.setVolume = { [weak self] level in
            self?.audioSource?.setVolume(level)
            self?.controller?.model.volume = level
        }

        syncSources(store)

        NotificationCenter.default.addObserver(forName: .helmStoreChanged, object: nil,
                                               queue: .main) { [weak self] note in
            let key = note.userInfo?["key"] as? String
            MainActor.assumeIsolated { self?.settingsChanged(key) }
        }
    }

    private func stop() {
        controller?.teardown()
        controller = nil
        shelf = nil
        dragMonitor?.stop()
        dragMonitor = nil
        powerSource = nil
        audioSource?.stop(); audioSource = nil
        mediaSource?.stop(); mediaSource = nil
        hidTap?.stop(); hidTap = nil
        NotificationCenter.default.removeObserver(self, name: .helmStoreChanged, object: nil)
    }

    /// Creates/tears down event sources to match the store's toggles.
    private func syncSources(_ store: NamespacedStore) {
        if store.bool("powerEvents", default: true) {
            if powerSource == nil {
                powerSource = IslandPowerSource { [weak self] text, symbol in
                    self?.controller?.showEvent(id: "power", text: text, symbol: symbol, ttl: 3.0)
                }
            }
        } else {
            powerSource = nil
        }
        if store.bool("audioEvents", default: true) {
            if audioSource == nil {
                audioSource = IslandAudioSource(
                    onDeviceEvent: { [weak self] text, symbol in
                        self?.controller?.showEvent(id: "audio-device", text: text, symbol: symbol, ttl: 3.0)
                    },
                    onVolumeEvent: { [weak self] level in
                        self?.controller?.showVolume(level)
                    })
                controller?.model.volumeAvailable = audioSource?.volumeControlAvailable ?? false
                if let v = audioSource?.currentVolume() { controller?.model.volume = v }
            }
        } else {
            audioSource?.stop(); audioSource = nil
            controller?.model.volumeAvailable = false
        }
        if store.bool("mediaEvents", default: true) {
            if mediaSource == nil {
                mediaSource = IslandMediaSource(
                    onEvent: { [weak self] text, symbol in
                        self?.controller?.showEvent(id: "media", text: text, symbol: symbol, ttl: 4.0)
                    },
                    onState: { [weak self] title, playing in
                        self?.controller?.model.nowPlayingTitle = title
                        self?.controller?.model.nowPlayingPlaying = playing
                    })
            }
        } else {
            mediaSource?.stop(); mediaSource = nil
            controller?.model.nowPlayingTitle = nil
        }
        // Replace the system volume HUD: consume the volume keys, apply the
        // change ourselves, show the island's bar instead. Needs Accessibility.
        if store.bool("replaceVolumeHUD", default: false), audioSource != nil {
            if hidTap == nil, IslandHIDTap.ensureAccessibility(prompt: false) {
                hidTap = IslandHIDTap { [weak self] key in self?.volumeKey(key) }
            }
        } else {
            hidTap?.stop(); hidTap = nil
        }
    }

    private func volumeKey(_ key: IslandHIDTap.Key) {
        guard let audio = audioSource else { return }
        switch key {
        case .mute:
            let muted = !audio.isMuted()
            audio.setMuted(muted)
            controller?.showVolume(muted ? 0 : (audio.currentVolume() ?? 0))
        case .volumeUp, .volumeDown:
            let step: Float = key == .volumeUp ? 1.0 / 16 : -1.0 / 16
            let level = min(max((audio.currentVolume() ?? 0) + step, 0), 1)
            audio.setVolume(level)
            controller?.showVolume(level)
        }
    }

    private func settingsChanged(_ key: String?) {
        guard let key, key.hasPrefix("island."),
              let store, controller != nil else { return }
        controller?.hoverEnabled = store.bool("hoverToOpen", default: true)
        if store.bool("revealOnDrag", default: true) {
            if dragMonitor == nil {
                dragMonitor = IslandDragMonitor(
                    onDragStarted: { [weak self] in self?.controller?.apply(.dragEntered) },
                    onDragEnded: { [weak self] in self?.controller?.apply(.dragExited) })
            }
        } else {
            dragMonitor?.stop()
            dragMonitor = nil
        }
        syncSources(store)
    }
}

// MARK: - Settings page

struct IslandSettingsPage: View {
    let store: NamespacedStore
    let hasNotch: Bool
    @State private var hoverToOpen = true
    @State private var revealOnDrag = true
    @State private var powerEvents = true
    @State private var audioEvents = true
    @State private var mediaEvents = true
    @State private var replaceVolumeHUD = false

    var body: some View {
        Form {
            if !hasNotch {
                Section {
                    Label(IsStr.noNotch, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            Section(IsStr.behavior) {
                Toggle(IsStr.hoverToOpen, isOn: $hoverToOpen)
                    .onChange(of: hoverToOpen) { _, v in store.set(v, for: "hoverToOpen") }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(IsStr.revealOnDrag, isOn: $revealOnDrag)
                        .onChange(of: revealOnDrag) { _, v in store.set(v, for: "revealOnDrag") }
                    Text(IsStr.revealOnDragNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(IsStr.eventsSection) {
                Toggle(IsStr.systemEvents, isOn: $powerEvents)
                    .onChange(of: powerEvents) { _, v in store.set(v, for: "powerEvents") }
                Toggle(IsStr.audioEvents, isOn: $audioEvents)
                    .onChange(of: audioEvents) { _, v in store.set(v, for: "audioEvents") }
                Toggle(IsStr.mediaEvents, isOn: $mediaEvents)
                    .onChange(of: mediaEvents) { _, v in store.set(v, for: "mediaEvents") }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(IsStr.replaceHUD, isOn: $replaceVolumeHUD)
                        .onChange(of: replaceVolumeHUD) { _, v in
                            if v { _ = IslandHIDTap.ensureAccessibility(prompt: true) }
                            store.set(v, for: "replaceVolumeHUD")
                        }
                    Text(IsStr.replaceHUDNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hoverToOpen = store.bool("hoverToOpen", default: true)
            revealOnDrag = store.bool("revealOnDrag", default: true)
            powerEvents = store.bool("powerEvents", default: true)
            audioEvents = store.bool("audioEvents", default: true)
            mediaEvents = store.bool("mediaEvents", default: true)
            replaceVolumeHUD = store.bool("replaceVolumeHUD", default: false)
        }
    }
}
