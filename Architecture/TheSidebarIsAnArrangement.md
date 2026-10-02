# The sidebar is an arrangement

`Sources/HelmUI/SidebarLayout.swift` is sections of module ids: a `Codable` value
whose invariant is that every registered module appears exactly once.
`Sources/HelmApp/SidebarLayoutStore.swift` reads and writes it, and reading is
where the invariant is enforced rather than trusted — the bytes were written by a
build that is not necessarily this one.

The window's sidebar and the status item's menu both draw the same store, so there
is one arrangement rather than two that agree by habit. Neither observes
`UserDefaults`; both listen for `.helmModuleOrderChanged`.

The drop arithmetic is pure and lives in `Sources/HelmUI/SidebarLayoutDrag.swift`
(`SidebarLayout.flattened`, `SidebarLayout.applyingDrag(of:toFlatIndex:)`).
`Sources/HelmApp/SidebarComposerSheet.swift` is the only way into the composer, and
why the composer is not an `NSTableView` is the doc comment of `SidebarComposerList`.
