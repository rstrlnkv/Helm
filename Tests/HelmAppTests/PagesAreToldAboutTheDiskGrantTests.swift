import AppKit
import HelmTestSupport
import HelmUI
import XCTest
@testable import HelmApp

/// **The pages that draw a Full Disk Access banner draw it off a reading, not off
/// this Mac.**
///
/// `ModulePageRender` calls `granting:` the third weather of that harness, and the
/// account was half true: it named Accessibility, and the other grant went on
/// being asked of whichever process ran the suite. It costs 61 pt of page — 72 in
/// French, where the sentence wraps and moves the list under it — and eight
/// layers, so every ratchet built on one of these renders moved with a checkbox in
/// System Settings.
///
/// **The list of pages is the tree's, not one written here.** They are found by
/// reading which pages call `helmTracksFullDiskAccess`: a sixth page that grows
/// the banner arrives in this check without anybody remembering it, and a hand
/// list would be the comment CLAUDE.md § A hand-written list warns about. That
/// scan is also the assertion that no page hand-rolls the probe — the modifier is
/// the one place the reading is read, and `ADiskGrantAReadingCanNameTests` in
/// `HelmUITests` is what proves the modifier honours it.
///
/// **Disk is measured for its floor and not for the difference**, and the reason
/// is not this grant: `DiskViewModel.shared(vm:)` restores the person's last scan
/// on a detached task, so two renders of that page in one process disagree by
/// themselves — 50 layers and then 23, in this test, before the pair was split
/// apart. `ModulePageRender.floors` carries the same story and
/// `TheSuiteDoesNotReadTheUsersLastScanTests` the seam that ends it.
@MainActor
final class PagesAreToldAboutTheDiskGrantTests: XCTestCase {

    /// The page renders whose difference is the banner and nothing else.
    private static let comparable = ["leftovers", "duplicates", "autopilot", "uninstaller"]

    func testTheBannerFollowsTheReadingRatherThanTheMachine() throws {
        let descriptors = try Self.descriptorsReadingTheDiskGrant()
        XCTAssertEqual(descriptors.count, 5, """
            \(descriptors.count) pages read the disk grant rather than five, so this scan is \
            looking for something that has changed shape: \
            \(descriptors.map { type(of: $0).id.rawValue }.sorted())
            """)

        for descriptor in descriptors
        where Self.comparable.contains(type(of: descriptor).id.rawValue) {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let granted = page(descriptor, appearance, ModulePageRender.granted)
                let withheld = page(descriptor, appearance,
                                    HelmGrants(accessibility: .granted, fullDisk: .denied))
                // First, that both readings drew a page at all: a comparison of
                // two empty bitmaps is satisfied by any difference and by none.
                granted.assertItDrewSomething()
                withheld.assertItDrewSomething()

                XCTAssertGreaterThan(withheld.layers.count, granted.layers.count, """
                    \(granted.id) draws \(withheld.layers.count) layers with the disk grant \
                    withheld and \(granted.layers.count) with it, in \(appearance.rawValue) — \
                    the same page either way, so the note is drawn off \
                    `PermissionCheck.fullDiskAccess()` and this reading is a fact about the \
                    process that took it.
                    """)
            }
        }
    }

    /// Disk's own page still has to have drawn something under a named reading,
    /// even though its pair cannot be compared.
    func testDisksPageDrawsUnderANamedReading() throws {
        let disk = try XCTUnwrap(ModuleRegistry.all.first { type(of: $0).id.rawValue == "disk" })
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            page(disk, appearance, ModulePageRender.granted).assertItDrewSomething()
        }
    }

    private func page(_ descriptor: any ModuleDescriptor, _ appearance: NSAppearance.Name,
                      _ grants: HelmGrants) -> ModulePageRender.Page {
        ModulePageRender.page(for: descriptor, in: appearance,
                              width: ModulePageRender.pageWidth, granting: grants)
    }

    /// The registry entries whose page asks for the grant, matched by the module
    /// folder its page lives in.
    private static func descriptorsReadingTheDiskGrant() throws -> [any ModuleDescriptor] {
        let modules = RepoSource.root.appendingPathComponent("Sources/Modules")
        var folders: Set<String> = []
        let files = FileManager.default.enumerator(at: modules, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  source.contains("helmTracksFullDiskAccess")
            else { continue }
            // Sources/Modules/<Folder>/UI/<file>.swift
            folders.insert(url.deletingLastPathComponent().deletingLastPathComponent()
                .lastPathComponent.lowercased())
        }
        return ModuleRegistry.all.filter {
            // «keep-awake» is one folder called KeepAwake: the id carries a hyphen
            // a folder name does not, and this is the whole difference.
            folders.contains(type(of: $0).id.rawValue.replacingOccurrences(of: "-", with: ""))
        }
    }
}
