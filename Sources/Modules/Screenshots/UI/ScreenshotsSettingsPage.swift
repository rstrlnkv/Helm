import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

struct ScreenshotsSettingsPage: View {
    @ObservedObject private var model: ScreenshotsPageModel
    private let store: NamespacedStore

    @State private var screenRecording: PermissionState = .granted
    @State private var after: ScreenDestination
    @State private var thumbnail: Bool
    /// Bumped when a shortcut is recorded, so the conflict notes are judged
    /// against the combination now stored and not the one the page opened with.
    @State private var shortcutsRevision = 0
    @StateObject private var areaKey: HelmHotkeyRecorder
    @StateObject private var screenKey: HelmHotkeyRecorder

    init(vm: ModuleViewModel, store: NamespacedStore) {
        model = ScreenshotsPageModel.shared(vm: vm)
        self.store = store
        let settings = ScreenshotsSettings.read(store)
        _after = State(initialValue: settings.afterFullScreen)
        _thumbnail = State(initialValue: settings.thumbnail)
        _areaKey = StateObject(wrappedValue: Self.recorder(.area, store))
        _screenKey = StateObject(wrappedValue: Self.recorder(.fullScreen, store))
    }

    private static func recorder(_ hotkey: ScreenshotsHotkey, _ store: NamespacedStore) -> HelmHotkeyRecorder {
        HelmHotkeyRecorder(store: store, prefix: hotkey.storePrefix, fallbackLabel: hotkey.fallback.label)
    }

    var body: some View {
        Form {
            if screenRecording == .denied {
                Section { HelmPermissionNote(need: .screenRecording, text: ScStr.needsAccess) }
            }
            shortcutsSection
            systemSection
            afterSection
            folderSection
        }
        .formStyle(.grouped)
        .helmIdlesOffScreen()
        .helmTracksScreenRecording($screenRecording)
        .task { model.refresh() }
        .helmOnAppActive { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .helmHotkeyChanged)) { _ in
            shortcutsRevision += 1
        }
        .animation(HelmMotion.interface, value: screenRecording)
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
    static func offersToUseSystemKeys(_ boxes: [SystemBoxReading]) -> Bool {
        SystemBox.replaced.allSatisfy { box in boxes.first { $0.box == box }?.state == .off }
    }

    private var systemSection: some View {
        Section {
            HelmSettingRow(ScStr.replaceTitle, note: ScStr.replaceBody)
            ForEach(drawnBoxes, id: \.box) { reading in
                HelmSettingRow(ScStr.boxName(reading.box)) {
                    Text(Self.say(reading.state))
                        .font(HelmText.rowDetail)
                        .foregroundStyle(conflicts(reading) ? HelmSignal.warning : HelmText.quiet)
                }
            }
            HStack(spacing: HelmSpace.s4) {
                Spacer()
                Button(ScStr.openSystemSettings) { PermissionCheck.openKeyboardSettings() }
                    .controlSize(.small)
                if bothOff {
                    Button(ScStr.useSystemKeys) { useSystemKeys() }
                        .controlSize(.small)
                }
            }
        } header: {
            HelmSectionTitle(ScStr.systemSection)
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

    static func say(_ state: BoxState) -> String {
        switch state {
        case .on: ScStr.stillOn
        case .off: ScStr.isOff
        case .unknown: ScStr.unknown
        }
    }

    /// ⇧⌘3 and ⇧⌘4, through the recorder's own writer. Only offered once both
    /// boxes are read as off: registering a combination macOS still holds answers
    /// success and does nothing, which is the row this page exists to not draw.
    private func useSystemKeys() {
        for (recorder, pair) in [(screenKey, Self.systemScreenKey), (areaKey, Self.systemAreaKey)] {
            recorder.assign(keyCode: pair.keyCode, carbonModifiers: pair.modifiers, label: pair.label)
        }
    }

    /// The system's own two, spelled by `HotkeyCombination.label` and not by
    /// hand, so the row, the button and the heading cannot drift apart.
    static let systemScreenKey = systemKey(keyCode: 20), systemAreaKey = systemKey(keyCode: 21)

    private static func systemKey(keyCode: Int) -> (keyCode: Int, modifiers: Int, label: String) {
        let modifiers = CarbonModifier.cmd | CarbonModifier.shift
        return (keyCode, modifiers, HotkeyCombination(keyCode: keyCode, modifiers: modifiers)?.label ?? "")
    }

    // MARK: - After a capture

    private var afterSection: some View {
        Section {
            HelmSettingRow(ScStr.afterFullScreen) {
                Picker(ScStr.afterFullScreen, selection: $after) {
                    ForEach(ScreenDestination.allCases, id: \.self) { destination in
                        Text(ScStr.after(destination)).tag(destination)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .onChange(of: after) { _, value in
                    store.set(value.rawValue, for: ScreenshotsSettings.Key.afterFullScreen)
                }
            }
            HelmSettingRow(ScStr.thumbnail) {
                Toggle(ScStr.thumbnail, isOn: $thumbnail)
                    .labelsHidden()
                    .onChange(of: thumbnail) { _, value in
                        store.set(value, for: ScreenshotsSettings.Key.thumbnail)
                    }
            }
        }
    }

    // MARK: - The folder

    private var folderSection: some View {
        Section {
            HelmSettingRow(ScStr.folder,
                           note: model.state.folderRefused == nil ? ScStr.folderNote : ScStr.folderRefused) {
                Text(Self.shown(model.state.folder))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// The home as «~», the way the person types it.
    static func shown(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
