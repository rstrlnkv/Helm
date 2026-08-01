// window-id.swift <owner> — prints the CGWindowID of a process's standard window.
//
// `screencapture -l<id>` then photographs that window wherever it is. The frame
// arithmetic this replaces read the window's position out of System Events and
// cropped a full-screen capture to it, which is correct on exactly one setup:
// a single display whose origin is (0, 0). On a Mac with an external screen the
// window sits at negative coordinates, `screencapture` grabs the *main* display
// regardless, and `sips` clamps the negative crop offset to zero — so every
// photograph came back as empty desktop, with no error anywhere.
//
// Only the window number and the owning process are read, so this needs no
// Screen Recording grant of its own; window *titles* would have needed one.
import CoreGraphics
import Foundation

// "Helm", not "HelmApp": `CGWindowOwnerName` is the bundle's display name, while
// System Events and `pkill` both want the executable's name. The two differ here
// and the difference is invisible until a lookup silently finds nothing.
let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Helm"

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
else {
    FileHandle.standardError.write(Data("window-id: the window list is unavailable\n".utf8))
    exit(1)
}

// Layer 0 is an ordinary window. The menu-bar panel sits above it, so asking
// for layer 0 is what distinguishes the settings window from the panel.
for window in windows {
    guard window[kCGWindowOwnerName as String] as? String == owner,
          window[kCGWindowLayer as String] as? Int == 0,
          let number = window[kCGWindowNumber as String] as? Int
    else { continue }
    print(number)
    exit(0)
}

FileHandle.standardError.write(Data("window-id: no layer-0 window owned by \(owner)\n".utf8))
exit(1)
