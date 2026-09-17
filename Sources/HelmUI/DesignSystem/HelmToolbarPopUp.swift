import AppKit
import SwiftUI

/// **A switcher that has run out of room in the window's toolbar, drawn as a
/// pop-up button that still says which choice is showing.**
///
/// The toolbar strips the words from SwiftUI's own menus: photographed
/// 2026-09-17, a `.menu` picker, a `Menu` with a text label, one with a
/// title-only `Label` and one with a text-and-chevron `HStack` each came out as
/// an empty glass capsule or a lone chevron — the choice the person is looking
/// at, not said anywhere in the bar. An `NSPopUpButton` is hosted as a view of
/// its own and keeps its title.
public struct HelmToolbarPopUp<Value: Hashable>: NSViewRepresentable {
    private let name: String
    private let values: [Value]
    private let labels: [String]
    @Binding private var selection: Value

    /// - Parameters:
    ///   - name: what the control is called aloud — a pop-up's title is its
    ///     current value, which is not a name.
    ///   - options: each value with the words it is shown as, in menu order.
    public init(_ name: String, selection: Binding<Value>, options: [(Value, String)]) {
        self.name = name
        self.values = options.map(\.0)
        self.labels = options.map(\.1)
        self._selection = selection
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    public func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.pick = { index in
            guard values.indices.contains(index) else { return }
            selection = values[index]
        }
        if button.itemTitles != labels {
            button.removeAllItems()
            button.addItems(withTitles: labels)
        }
        if let index = values.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
        button.setAccessibilityLabel(name)
        button.toolTip = name
    }

    @MainActor public final class Coordinator: NSObject {
        var pick: (Int) -> Void = { _ in }

        @objc func picked(_ sender: NSPopUpButton) {
            pick(sender.indexOfSelectedItem)
        }
    }
}
