import HelmUI
import SwiftUI

/// The pop-up a condition or an action row draws for a choice of two to four short words: the same label hidden, the
/// same floor, widened to the longest label in the current language.
struct ShortPicker<Value: Hashable>: View {
    let name: String
    let selected: Value
    let options: [(value: Value, label: String)]
    let set: @MainActor (Value) -> Void

    var body: some View {
        Picker(name, selection: Binding(get: { selected }, set: set)) {
            ForEach(options, id: \.label) { Text($0.label).tag($0.value) }
        }
        .labelsHidden()
        .frame(width: HelmPickerWidth.fitting(options.map(\.label), minimum: AutopilotLayout.shortPicker))
    }
}
