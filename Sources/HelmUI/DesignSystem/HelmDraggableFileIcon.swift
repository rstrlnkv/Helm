import AppKit
import SwiftUI

/// A file's own icon that can be dragged out as the file: onto the Dock, into a Finder window.
///
/// For a thing the person must put somewhere themselves, as the Launchpad Dock helper is. The drag carries the file URL
/// and nothing else, so what lands is the file, not a copy of the picture. VoiceOver cannot drag, so the name is the
/// whole of what it says; the button beside the icon is the way that reaches the file without a drag.
public struct HelmDraggableFileIcon: View {
    private let url: URL
    private let size: CGFloat
    private let name: String

    public init(_ url: URL, size: CGFloat, name: String) {
        self.url = url
        self.size = size
        self.name = name
    }

    public var body: some View {
        Image(nsImage: AppInfo.icon(forFile: url.path)).resizable()
            .frame(width: size, height: size)
            .onDrag { NSItemProvider(object: url as NSURL) }
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isImage)
    }
}
