import HelmUI
import SwiftUI

/// A place to try it without risking anything you were writing.
///
/// The module works in Helm's own window like anywhere else, so this is a real
/// test rather than a simulation — which is the point: a demonstration that
/// cheats teaches the wrong thing about when it fires.
struct LayoutTestField: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            TextField("", text: $text, prompt: Text(LyStr.tryItPlaceholder))
                .accessibilityLabel(LyStr.tryItPlaceholder)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text(LyStr.tryItHint)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
