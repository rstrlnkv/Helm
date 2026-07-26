import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

public struct LayoutSettingsPage: View {
    @ObservedObject private var lvm: LayoutViewModel
    private let store: NamespacedStore

    @State private var automatic: Bool
    @State private var exceptions: String
    @State private var accessibility: PermissionState = .granted

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        lvm = LayoutViewModel.shared(vm: vm)
        self.store = store
        _automatic = State(initialValue: store.bool("automatic", default: true))
        _exceptions = State(initialValue: store.stringArray("exceptions").joined(separator: "\n"))
    }

    public var body: some View {
        Form {
            Section {
                HelmMetricStrip([
                    .init(lvm.state.suspended ? LyStr.paused : LyStr.on, LyStr.metricState,
                          tint: lvm.state.suspended ? .orange : .green),
                    .init("\(lvm.state.conversionsToday)", LyStr.metricToday),
                ])
            }

            Section {
                Toggle(LyStr.automatic, isOn: $automatic)
                    .onChange(of: automatic) { _, value in
                        store.set(value, for: "automatic")
                        lvm.vm.send("settingsChanged")
                    }
                Text(LyStr.automaticNote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // macOS gives a key tap nothing without this grant, so the
                // switch above would be on and silent.
                if accessibility == .denied {
                    HelmPermissionNote(need: .accessibility, text: LyStr.needsAccessibility)
                }
                if lvm.state.suspended {
                    Text(LyStr.suspended).font(.caption).foregroundStyle(.secondary)
                }
                if let last = lvm.state.lastConversion {
                    LabeledContent(LyStr.lastChange) {
                        HStack(spacing: 8) {
                            Text("\(last.before) → \(last.after)")
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Button(LyStr.undo) { lvm.undoLast() }
                                .controlSize(.small)
                        }
                    }
                }
            }

            Section(LyStr.exceptions) {
                Text(LyStr.exceptionsHint).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $exceptions)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 90)
                    .onChange(of: exceptions) { _, value in
                        store.set(value.split(separator: "\n").map(String.init), for: "exceptions")
                        lvm.vm.send("settingsChanged")
                    }
            }

            Section(LyStr.apps) {
                Text(LyStr.appsHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        // A grouped Form caps its content at 704 pt and centres it; capping it
        // keeps the system on its constant-20 branch, matching the page header.
        .frame(maxWidth: 744, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmOnAppActive { accessibility = PermissionCheck.currentAccessibility() }
        .task { accessibility = PermissionCheck.currentAccessibility() }
    }
}
