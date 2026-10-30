import SwiftUI

/// A row's own menu of further actions, named with what the row is about, because VoiceOver reads
/// several of them on a page.
public struct HelmRowMenu<Items: View>: View {
    private let subject: String
    private let items: Items

    public init(subject: String, @ViewBuilder items: () -> Items) {
        self.subject = subject
        self.items = items()
    }

    public var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("\(HelmA11y.moreActions), \(subject)")
        .fixedSize()
    }
}
