import Foundation

/// Where the keyboard is in the result list.
///
/// A `List` with no selection has no focusable rows at all — the disk list
/// learned this the hard way — so the rows carry their path as a tag and the
/// view holds the selected one. The list underneath changes while it is on
/// screen: emptying the basket takes rows away, and a group that drops to a
/// single copy stops being a group.
public enum DuplicateSelection {

    /// The selection to keep after the list has changed: the same row if it is
    /// still there, and nothing if it is not. A keyboard pointing at a row that
    /// no longer exists makes Return do nothing, which reads as the app
    /// ignoring the key.
    public static func surviving(_ selection: String?,
                                 in groups: [DuplicateGroup]) -> String? {
        guard let selection,
              groups.contains(where: { $0.paths.contains(selection) }) else { return nil }
        return selection
    }
}
