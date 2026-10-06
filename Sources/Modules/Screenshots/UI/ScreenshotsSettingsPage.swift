import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

struct ScreenshotsSettingsPage: View {
    /// The three tabs of the window's toolbar switcher: what a capture makes, what the editor opens with, and what macOS
    /// holds of the same shortcuts.
    enum Tab: String, CaseIterable { case capturing, editor, system }

    @ObservedObject private var model: ScreenshotsPageModel
    private let store: NamespacedStore
    /// Whether a folder may be written into: the one question a capture asks the
    /// disk that raises a protected-folder prompt. A seam so a test can count it.
    private let writable: (String) -> Bool

    @State private var tab = Tab.capturing
    @State private var screenRecording: PermissionState = .granted
    @State private var target: SaveTarget
    @State private var otherFolder: String?
    @State private var format: ShotFormat
    @State private var thumbnail: Bool
    @State private var shutterSound: Bool
    @State private var showCursor: Bool
    /// The colour a new object starts in, nil until one is picked (`EditorMemory`'s own key).
    @State private var ink: AnnotationColor?
    /// The items the person has not taken off (`PaletteItems.visible`), read again when the store says so; the page
    /// counts only those `EditorPalette.rowKinds` answer to.
    @State private var shownItems: Set<PaletteItem>
    /// The list of palette tools is open.
    @State private var choosing = false
    /// Set when the folder just chosen was refused, so the page says so instead
    /// of quietly keeping the old one.
    @State private var chosenRefused = false
    /// What the disk said about the folder the selected target names, asked from
    /// a task and never from the body: a body runs on every render, and asking
    /// about Documents or the Desktop is what raises the system's prompt.
    @State private var judged: SaveFolderRefusal?
    /// Bumped when a shortcut is recorded, so the conflict notes are judged
    /// against the combination now stored and not the one the page opened with.
    @State private var shortcutsRevision = 0
    @StateObject private var areaKey: HelmHotkeyRecorder
    @StateObject private var screenKey: HelmHotkeyRecorder
    @StateObject private var panelKey: HelmHotkeyRecorder

    /// `tab` is the one the page opens on: the window's switcher moves it afterwards, and a test names the tab it reads.
    init(vm: ModuleViewModel, store: NamespacedStore, tab: Tab = .capturing,
         writable: @escaping (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }) {
        model = ScreenshotsPageModel.shared(vm: vm)
        self.store = store
        self.writable = writable
        _tab = State(initialValue: tab)
        let settings = ScreenshotsSettings.read(store)
        _target = State(initialValue: settings.saveTarget)
        _otherFolder = State(initialValue: settings.otherFolder)
        _format = State(initialValue: settings.format)
        _thumbnail = State(initialValue: settings.thumbnail)
        _shutterSound = State(initialValue: settings.shutterSound)
        _showCursor = State(initialValue: settings.showCursor)
        _ink = State(initialValue: AnnotationColor(rawValue: store.string(ScreenshotsSettings.Key.editorColor, default: "")))
        _shownItems = State(initialValue: Set(PaletteItems.visible(store)))
        _areaKey = StateObject(wrappedValue: Self.recorder(.area, store))
        _screenKey = StateObject(wrappedValue: Self.recorder(.fullScreen, store))
        _panelKey = StateObject(wrappedValue: Self.recorder(.panel, store))
    }

    private static func recorder(_ hotkey: ScreenshotsHotkey, _ store: NamespacedStore) -> HelmHotkeyRecorder {
        HelmHotkeyRecorder(store: store, prefix: hotkey.storePrefix, fallbackLabel: hotkey.fallback.label)
    }

    var body: some View {
        Form {
            if screenRecording == .denied {
                Section { HelmPermissionNote(need: .screenRecording, text: ScStr.needsAccess) }
            }
            switch tab {
            case .capturing:
                shortcutsSection
                saveSection
                folderSection
            case .editor:
                editorSection
            case .system:
                systemSection
            }
        }
        .formStyle(.grouped)
        .helmWindowToolbar(toolbarContent, token: ScreenshotsDescriptor.id.rawValue)
        .helmIdlesOffScreen()
        .helmTracksScreenRecording($screenRecording)
        .task { model.refresh() }
        .helmOnAppActive { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .helmHotkeyChanged)) { _ in
            shortcutsRevision += 1
        }
        .animation(HelmMotion.interface, value: screenRecording)
        .task(id: JudgedFolder(target: target, other: otherFolder)) { judge() }
        // The panel's gear menu writes some of the same keys while this page may be up.
        .onReceive(NotificationCenter.default.publisher(for: .helmStoreChanged)) { note in
            if Self.keys.contains(where: { store.changed(note, is: $0) }) { mirror() }
        }
    }

    private static let keys = [
        ScreenshotsSettings.Key.saveTarget, ScreenshotsSettings.Key.otherFolder,
        ScreenshotsSettings.Key.format, ScreenshotsSettings.Key.thumbnail,
        ScreenshotsSettings.Key.shutterSound, ScreenshotsSettings.Key.showCursor,
        ScreenshotsSettings.Key.editorColor, ScreenshotsSettings.Key.paletteChoices,
    ]

    /// Takes what the store holds now, for each control another surface may have
    /// written. Assigning an equal value changes nothing, so the page's own
    /// writes come back as no-ops.
    private func mirror() {
        let settings = ScreenshotsSettings.read(store)
        if target != settings.saveTarget { target = settings.saveTarget }
        if otherFolder != settings.otherFolder { otherFolder = settings.otherFolder }
        if format != settings.format { format = settings.format }
        if thumbnail != settings.thumbnail { thumbnail = settings.thumbnail }
        if shutterSound != settings.shutterSound { shutterSound = settings.shutterSound }
        if showCursor != settings.showCursor { showCursor = settings.showCursor }
        let picked = AnnotationColor(rawValue: store.string(ScreenshotsSettings.Key.editorColor, default: ""))
        if ink != picked { ink = picked }
        let shown = Set(PaletteItems.visible(store))
        if shownItems != shown { shownItems = shown }
    }

    // MARK: - The tabs

    /// The switcher's three segments. **The dot on the system tab is `holdsSystemKeys`**, the reading beside the one that
    /// offers «Use ⇧⌘3 and ⇧⌘4» (`offersToUseSystemKeys`), so the tab and the page below it cannot say different things.
    private var toolbarContent: HelmPageToolbarContent {
        let holds = Self.holdsSystemKeys(model.state.boxes)
        return HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: Tab.capturing.rawValue, title: ScStr.tabCapturing, symbol: "camera.viewfinder"),
                   HelmToolbarTab(id: Tab.editor.rawValue, title: ScStr.tabEditor, symbol: "pencil.tip.crop.circle"),
                   HelmToolbarTab(id: Tab.system.rawValue, title: ScStr.systemSection, symbol: "command",
                                  needsAttention: holds, attentionNote: holds ? ScStr.stillOn : nil)],
            selectedTab: Binding(get: { tab.rawValue }, set: { tab = Tab(rawValue: $0) ?? tab }))
    }

    private struct JudgedFolder: Hashable { let target: SaveTarget; let other: String? }

    /// Asks the disk about the selected target's folder — Desktop, Documents or
    /// the chosen one; macOS's own is judged by the engine and the clipboard has
    /// none — and about no other.
    private func judge() {
        guard [.desktop, .documents, .other].contains(target) else { judged = nil; return }
        var settings = ScreenshotsSettings.defaults
        settings.saveTarget = target
        settings.otherFolder = otherFolder
        judged = SaveLocation.folder(for: settings, macOS: nil, locations: .system, writable: writable)?.refused
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        Section {
            HelmHotkeyRow(ScStr.captureArea, recorder: areaKey,
                          taken: HotkeyStatus.isTaken(ScreenshotsHotkey.area.slot),
                          note: conflictNote(.area))
            HelmHotkeyRow(ScStr.captureScreen, recorder: screenKey,
                          taken: HotkeyStatus.isTaken(ScreenshotsHotkey.fullScreen.slot),
                          note: conflictNote(.fullScreen))
            HelmHotkeyRow(ScStr.openPanel, recorder: panelKey,
                          taken: HotkeyStatus.isTaken(ScreenshotsHotkey.panel.slot),
                          note: conflictNote(.panel))
        } header: {
            HelmSectionTitle(ScStr.shortcuts)
        }
    }

    /// The combination a shortcut holds **now**: what was recorded, or — for a
    /// store nothing was ever recorded into — the one it ships with. Nil for one
    /// that was cleared.
    static func combination(of hotkey: ScreenshotsHotkey, in store: NamespacedStore) -> (keyCode: Int, modifiers: Int)? {
        guard store.object("\(hotkey.storePrefix)KeyCode") != nil else {
            return (hotkey.fallback.keyCode, hotkey.fallback.modifiers)
        }
        let key = store.int("\(hotkey.storePrefix)KeyCode", default: -1)
        let modifiers = store.int("\(hotkey.storePrefix)Modifiers", default: 0)
        guard key >= 0, modifiers > 0 else { return nil }
        return (key, modifiers)
    }

    /// The row's own note when a combination is one macOS holds — which
    /// `RegisterEventHotKey` cannot say, because it answers success for it.
    private func conflictNote(_ hotkey: ScreenshotsHotkey) -> String? {
        _ = shortcutsRevision
        guard let combination = Self.combination(of: hotkey, in: store),
              !SystemShortcuts.holding(keyCode: combination.keyCode, modifiers: combination.modifiers,
                                       in: model.state.boxes).isEmpty
        else { return nil }
        return ScStr.conflict
    }

    // MARK: - The system's own

    /// The boxes the section draws: the two Helm replaces always, and a
    /// clipboard twin (29, 31) only while it holds a combination Helm holds — recorded here or shipped as the default.
    /// The conflict note says «Untick it below first» for any box macOS holds, so
    /// the box it means has to be below — and a twin that conflicts with nothing
    /// stays out of a list that tells the person to untick "these two".
    static func drawnBoxes(_ boxes: [SystemBoxReading],
                           against combinations: [(keyCode: Int, modifiers: Int)]) -> [SystemBoxReading] {
        SystemBox.allCases.compactMap { box in
            guard let reading = boxes.first(where: { $0.box == box }) else { return nil }
            return SystemBox.replaced.contains(box) || conflicts(reading, with: combinations) ? reading : nil
        }
    }

    private var drawnBoxes: [SystemBoxReading] {
        _ = shortcutsRevision
        return Self.drawnBoxes(model.state.boxes,
                               against: ScreenshotsHotkey.allCases.compactMap { Self.combination(of: $0, in: store) })
    }

    private var bothOff: Bool { Self.offersToUseSystemKeys(model.state.boxes) }

    /// «Use ⇧⌘3 and ⇧⌘4» is offered when **both** boxes are read as off, and
    /// only then. A box that is on would make the registration answer success
    /// for a combination macOS still holds; one that is unknown is not known to
    /// be off, and offering on a guess is the row this page exists not to draw.
    /// Box 184 is not asked: a person who keeps macOS's panel is still offered
    /// the other two.
    static func offersToUseSystemKeys(_ boxes: [SystemBoxReading]) -> Bool {
        SystemBox.capture.allSatisfy { box in boxes.first { $0.box == box }?.state == .off }
    }

    /// Whether macOS is **read** as still holding ⇧⌘3 or ⇧⌘4: a capture box that is on. It is the other side of
    /// `offersToUseSystemKeys` — nothing is both — and a box that is unknown is neither, because a dot that says «Still on
    /// in macOS» over a reading nobody made is the claim the page exists not to draw.
    static func holdsSystemKeys(_ boxes: [SystemBoxReading]) -> Bool {
        SystemBox.capture.contains { box in boxes.first { $0.box == box }?.state == .on }
    }

    /// Whether ⇧⌘5 goes to the panel with the other two: only when box 184 is
    /// **read** as off. On and unknown are both "macOS may still hold it".
    static func offersThePanelItsKey(_ boxes: [SystemBoxReading]) -> Bool {
        boxes.first { $0.box == .panel }?.state == .off
    }

    private var systemSection: some View {
        Section {
            HelmSettingRow(ScStr.replaceTitle, note: ScStr.replaceBody)
            ForEach(drawnBoxes, id: \.box) { reading in
                BoxRow(reading: reading, warns: conflicts(reading))
            }
            HStack(spacing: HelmSpace.s4) {
                Spacer()
                Button(ScStr.openSystemSettings) { PermissionCheck.openKeyboardSettings() }
                    .controlSize(.small)
                if bothOff {
                    Button(Self.offersThePanelItsKey(model.state.boxes) ? ScStr.useSystemKeysAndPanel : ScStr.useSystemKeys) { useSystemKeys() }
                        .controlSize(.small)
                }
            }
        } header: {
            HelmSectionTitle(ScStr.systemSection)
        }
    }

    /// One box and what macOS says of it. **The status keeps its one line**: it
    /// is the short thing on the row, and a column asked to share the width
    /// otherwise wraps it ("Still on / in macOS") while the long warning under
    /// the name keeps its line; the warning is what wraps.
    struct BoxRow: View {
        let reading: SystemBoxReading
        let warns: Bool

        var body: some View {
            HelmSettingRow(ScStr.boxName(reading.box), note: ScreenshotsSettingsPage.note(for: reading.box)) {
                BoxStatus(state: reading.state, warns: warns)
            }
        }
    }

    struct BoxStatus: View {
        let state: BoxState
        let warns: Bool

        var body: some View {
            Text(ScreenshotsSettingsPage.say(state))
                .font(HelmText.rowDetail)
                .foregroundStyle(warns ? HelmSignal.warning : HelmText.quiet)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// The box is held against the combination a shortcut here holds **now**.
    private func conflicts(_ reading: SystemBoxReading) -> Bool {
        _ = shortcutsRevision
        return Self.conflicts(reading, with: ScreenshotsHotkey.allCases.compactMap { Self.combination(of: $0, in: store) })
    }

    /// **Warning ink is for a conflict and for nothing else.** A box that is on is
    /// macOS's ordinary state — it is on in every install that has not moved a
    /// shortcut — and painting it in the warning colour put the brightest thing on
    /// a page that accuses nothing, over a pair of shortcuts that did not collide.
    /// It is a warning only when a combination Helm holds is the one the box holds.
    static func conflicts(_ reading: SystemBoxReading,
                          with combinations: [(keyCode: Int, modifiers: Int)]) -> Bool {
        combinations.contains {
            !SystemShortcuts.holding(keyCode: $0.keyCode, modifiers: $0.modifiers, in: [reading]).isEmpty
        }
    }

    /// The words under a box's name. Only box 184 carries any, and **always**:
    /// whether or not a person unticks it, it is also how screen recording is
    /// reached from the keyboard, and the page is where they decide.
    static func note(for box: SystemBox) -> String? {
        box == .panel ? ScStr.panelBoxWarning : nil
    }

    static func say(_ state: BoxState) -> String {
        switch state {
        case .on: ScStr.stillOn
        case .off: ScStr.isOff
        case .unknown: ScStr.unknown
        }
    }

    /// ⇧⌘3 and ⇧⌘4 — and ⇧⌘5 for the panel when box 184 is read as off —
    /// through the recorder's own writer. Only offered once both capture boxes are
    /// read as off: registering a combination macOS still holds answers success
    /// and does nothing, which is the row this page exists to not draw.
    private func useSystemKeys() {
        for (hotkey, pair) in Self.systemKeys(for: model.state.boxes) {
            let recorder: HelmHotkeyRecorder
            switch hotkey {
            case .fullScreen: recorder = screenKey
            case .area: recorder = areaKey
            case .panel: recorder = panelKey
            }
            recorder.assign(keyCode: pair.keyCode, carbonModifiers: pair.modifiers, label: pair.label)
        }
    }

    /// What the button writes, as data so a test can ask without a recorder.
    static func systemKeys(for boxes: [SystemBoxReading])
        -> [(ScreenshotsHotkey, (keyCode: Int, modifiers: Int, label: String))] {
        var out: [(ScreenshotsHotkey, (keyCode: Int, modifiers: Int, label: String))] =
            [(.fullScreen, systemScreenKey), (.area, systemAreaKey)]
        if offersThePanelItsKey(boxes) { out.append((.panel, systemPanelKey)) }
        return out
    }

    /// The system's own three, spelled by `HotkeyCombination.label` and not by
    /// hand, so the row, the button and the heading cannot drift apart.
    static let systemScreenKey = systemKey(keyCode: 20), systemAreaKey = systemKey(keyCode: 21),
               systemPanelKey = systemKey(keyCode: 23)

    private static func systemKey(keyCode: Int) -> (keyCode: Int, modifiers: Int, label: String) {
        let modifiers = CarbonModifier.cmd | CarbonModifier.shift
        return (keyCode, modifiers, HotkeyCombination(keyCode: keyCode, modifiers: modifiers)?.label ?? "")
    }

    // MARK: - The editor

    /// The row objects with the item each answers to: what the list offers and what «N of M» counts. Read from the
    /// palette's own list, so an object added there is offered here with nothing said twice.
    private var paletteChoices: [(item: PaletteItem, kind: PaletteObject.Kind)] {
        EditorPalette.rowKinds.compactMap { kind in EditorPalette.item(of: kind).map { ($0, kind) } }
    }

    private var editorSection: some View {
        Section {
            HelmSettingRow(ScStr.defaultColour, note: ScStr.defaultColourNote) {
                HStack(spacing: HelmSpace.s3) {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        EditorSwatch(color: color, selected: ink == color) {
                            ink = color
                            store.set(color.rawValue, for: ScreenshotsSettings.Key.editorColor)
                            // The shared ink of before each tool kept its own would be read first and hide this pick.
                            store.set(nil, for: ScreenshotsSettings.Key.editorInk)
                        }
                    }
                }
            }
            HelmSettingRow(ScStr.toolsInPalette, note: ScStr.hiddenToolsNote) {
                HStack(spacing: HelmSpace.s4) {
                    let choices = paletteChoices
                    Text(ScStr.toolsShown(choices.filter { shownItems.contains($0.item) }.count, of: choices.count))
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                    Button(ScStr.choose) { choosing = true }
                        .controlSize(.small)
                        .popover(isPresented: $choosing) { toolList }
                }
                // The count and the button hold their line, as `BoxStatus` does; the note is what wraps.
                .fixedSize(horizontal: true, vertical: false)
            }
        } header: {
            HelmSectionTitle(ScStr.tabEditor)
        }
    }

    /// One checkbox per object of the row. Colours, Undo, Redo, ⋯, Done and ✕ are not in it: they are not
    /// `PaletteItem`s, so nothing written here can take them away.
    private var toolList: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            ForEach(paletteChoices, id: \.item) { choice in
                Toggle(EditorPalette.name(of: choice.kind), isOn: Binding(
                    get: { shownItems.contains(choice.item) },
                    set: { shown in
                        PaletteItems.set(choice.item, shown: shown, in: store)
                        shownItems = Set(PaletteItems.visible(store))
                    }))
            }
        }
        .padding(HelmSpace.s5)
    }

    // MARK: - What a capture makes

    private var saveSection: some View {
        Section {
            HelmSettingRow(ScStr.saveTo) {
                Picker(ScStr.saveTo, selection: $target) {
                    ForEach(SaveTarget.allCases, id: \.self) { choice in
                        Text(ScStr.target(choice)).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .onChange(of: target) { _, value in targetChanged(to: value) }
            }
            HelmSettingRow(ScStr.format) {
                Picker(ScStr.format, selection: $format) {
                    ForEach(ShotFormat.allCases, id: \.self) { choice in
                        Text(ScStr.format(choice)).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .onChange(of: format) { _, value in
                    store.set(value.rawValue, for: ScreenshotsSettings.Key.format)
                }
            }
            HelmSettingRow(ScStr.floatingThumbnail, note: ScStr.thumbnailNote) {
                Toggle(ScStr.floatingThumbnail, isOn: $thumbnail)
                    .labelsHidden()
                    .onChange(of: thumbnail) { _, value in
                        store.set(value, for: ScreenshotsSettings.Key.thumbnail)
                    }
            }
            HelmSettingRow(ScStr.shutterSound) {
                Toggle(ScStr.shutterSound, isOn: $shutterSound)
                    .labelsHidden()
                    .onChange(of: shutterSound) { _, value in
                        store.set(value, for: ScreenshotsSettings.Key.shutterSound)
                    }
            }
            HelmSettingRow(ScStr.showCursor) {
                Toggle(ScStr.showCursor, isOn: $showCursor)
                    .labelsHidden()
                    .onChange(of: showCursor) { _, value in
                        store.set(value, for: ScreenshotsSettings.Key.showCursor)
                    }
            }
        }
    }

    /// Picking «Other…» asks for the folder, and the setting is written only
    /// once there is one that passed the same judgement a capture will apply:
    /// a cancelled panel or a refused folder puts the picker back on what is
    /// stored, so the page never shows a choice the engine does not hold.
    private func targetChanged(to value: SaveTarget) {
        chosenRefused = false
        // The bar chose «Other…» and the mirror followed: it is already stored.
        if value == .other, ScreenshotsSettings.read(store).saveTarget == .other { return }
        guard value == .other else {
            store.set(value.rawValue, for: ScreenshotsSettings.Key.saveTarget)
            return
        }
        switch Self.askForFolder() {
        case .chosen(let path):
            otherFolder = path
            store.set(path, for: ScreenshotsSettings.Key.otherFolder)
            store.set(value.rawValue, for: ScreenshotsSettings.Key.saveTarget)
            return
        case .refused: chosenRefused = true
        case .cancelled: break
        }
        target = ScreenshotsSettings.read(store).saveTarget
    }

    private func chooseAnother() {
        chosenRefused = false
        switch Self.askForFolder() {
        case .chosen(let path):
            otherFolder = path
            store.set(path, for: ScreenshotsSettings.Key.otherFolder)
        case .refused: chosenRefused = true
        case .cancelled: break
        }
    }

    /// What the chooser came back with, judged: the page and the panel's menu
    /// both ask, and both write only a `.chosen` folder.
    enum FolderChoice { case chosen(String), refused, cancelled }

    /// Asks for a folder and judges it by the same `resolve` a capture applies.
    static func askForFolder() -> FolderChoice {
        guard let path = chooseFolder() else { return .cancelled }
        return refusal(of: path) == nil ? .chosen(path) : .refused
    }

    /// Why a chosen path would not be used as it is, by the same `resolve` the
    /// capture applies; nil when it would.
    static func refusal(of path: String) -> SaveFolderRefusal? {
        let locations = ScreenshotsLocations.system
        return SaveLocation.resolve(raw: path, desktop: locations.desktop, home: locations.home).refused
    }

    /// The system's folder chooser, run modally from the page. Activates Helm for
    /// as long as it is up — accepted: a panel of an inactive app is not reliably
    /// answered. Nil when cancelled.
    private static func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = ScStr.chooseFolder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    // MARK: - The folder

    /// The folder this setting means now, as the value spells it — nothing for
    /// the clipboard, which has none. The disk's verdict is `judged`, and a body
    /// asks the disk nothing.
    private var shownFolder: SaveFolder? {
        var settings = ScreenshotsSettings.defaults
        settings.saveTarget = target
        settings.otherFolder = otherFolder
        let macOS: Any? = model.state.folder.isEmpty ? nil : model.state.folder
        return SaveLocation.shownFolder(for: settings, macOS: macOS, locations: .system)
    }

    @ViewBuilder private var folderSection: some View {
        if let folder = shownFolder {
            Section {
                HelmSettingRow(ScStr.folder, note: folderNote(folder)) {
                    HStack(spacing: HelmSpace.s4) {
                        Text(Self.shown(folder.url.path))
                            .font(HelmText.rowDetail)
                            .foregroundStyle(HelmText.quiet)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if target == .other {
                            Button(ScStr.chooseFolder) { chooseAnother() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func folderNote(_ folder: SaveFolder) -> String? {
        if chosenRefused || (target != .macOS && (folder.refused ?? judged) != nil) { return ScStr.chosenRefused }
        guard target == .macOS else { return nil }
        return model.state.folderRefused == nil ? ScStr.folderNote : ScStr.folderRefused
    }

    /// The home as «~», the way the person types it.
    static func shown(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
