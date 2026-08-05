import SwiftUI
import HelmUI
import Module_Autopilot_Engine

/// Autopilot in the panel: how many folders it is watching, and what it has
/// done today.
///
/// The view model is a `@StateObject` rather than one built per redraw: it asks
/// the engine for the folders and the history when it is created, and a widget
/// that rebuilt it in every body pass would ask again on every frame.
public struct AutopilotWidget: View {
    @StateObject private var vm: AutopilotViewModel
    private let size: PanelWidgetSize

    public init(vm: ModuleViewModel, size: PanelWidgetSize) {
        _vm = StateObject(wrappedValue: AutopilotViewModel(vm: vm))
        self.size = size
    }

    private var watched: Int { vm.folders.filter(\.enabled).count }

    private var today: [ActionRecord] {
        let start = Calendar.current.startOfDay(for: Date())
        return vm.history.filter { $0.at >= start }
    }

    public var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "location.north.circle",
                             tint: AutopilotDescriptor.tint.colour,
                             name: AutopilotDescriptor.metadata.shortName)
            if vm.folders.isEmpty {
                // Nothing measured, and nothing wrong: this module does not
                // watch anything until somebody points it at a folder, and
                // «0 today» would read as a quiet day rather than as an empty
                // one.
                HelmWidgetUnmeasured(ApStr.startHint)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    HelmWidgetFigure("\(watched)", L("FOLDERS"), small: size == .compact)
                    if size != .compact {
                        HelmWidgetFigure("\(today.count)", L("TODAY"), small: false)
                    }
                }
                if size == .tall {
                    // Why it is that number: the rules that fired, newest
                    // first. The name of a rule is the one word that says why
                    // without explaining anything.
                    ForEach(today.prefix(5)) { record in
                        HelmWidgetRow(record.rule, ApStr.historyVerb(record.kind))
                    }
                }
            }
        }
    }
}
