import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **In a window shaped like Settings, Homebrew's list scrolled to its end
/// stops at its last row.**
///
/// `TheListEndsAtItsLastRowTests` reads the page in a plain titled window. The
/// owner saw about three empty striped rows under `zcode` in the Settings
/// window itself — full-size content under an app-owned `NSToolbar`, the page
/// bleeding under the band (`HomebrewDescriptor.pageBleeds`), the page header
/// placed by `helmPageHeader`, the backdrop and the band choice — so this
/// reads the same list inside that shape, built the way
/// `SettingsSplitViewController` builds its detail pane, with the toolbar
/// attached as `LivePageToolbarFixture` attaches it. Scrolled to the furthest
/// offset the clip view allows (`StripedListEnd`), judged against the list's
/// own row step. Console absent and present, Light and Dark.
@MainActor
final class TheHomebrewListEndsAtItsLastRowInTheWindowTests: XCTestCase {

    private final class Cellar: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        let packages: [BrewPackage] = (0..<106).map {
            BrewPackage(name: String(format: "pkg-%03d", $0), version: "1.0.\($0)", isCask: $0 % 5 == 0)
        } + [BrewPackage(name: "zcode", version: "9.9", isCask: false)]

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode(packages)
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions:
                return try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: packages.map {
                    ($0.name, "A fixture description of \($0.name)")
                }))
            case .doctor: return try JSONEncoder().encode([DoctorIssue]())
            default: return Data()
            }
        }

        func say(_ line: String) {
            stream.continuation.yield(
                EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data(line.utf8)))
        }
    }

    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.orderOut(nil); $0.contentViewController = nil }
        windows = []
        super.tearDown()
    }

    private func settingsShaped(_ page: some View, appearance: NSAppearance.Name,
                                channel: HelmWindowToolbarChannel) -> NSWindow {
        _ = NSApplication.shared
        let split = NSSplitViewController()
        let sidebar = NSHostingController(rootView: Color.clear.frame(width: 220))
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 214
        sidebarItem.maximumThickness = 320
        let detail = NSHostingController(rootView: AnyView(
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .helmPageHeader(symbol: "shippingbox", tint: HomebrewDescriptor.tint.colour,
                                title: "Homebrew", subtitle: nil, bleeds: HomebrewDescriptor().pageBleeds)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.helmWindowToolbarChannel, channel)
                .helmToolbarBackdrop()
                .environment(\.helmBandChoice, .running)
                .helmTracksPageBarStyle { .moduleName }))
        detail.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)
        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.appearance = NSAppearance(named: appearance)
        window.titlebarAppearsTransparent = HelmBandChoice.running.titlebarAppearsTransparent
        window.titleVisibility = .hidden
        window.setContentSize(SettingsWindow.defaultSize)
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }

    private func settle(_ window: NSWindow, _ turns: Int) {
        for _ in 0..<turns {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private func read(_ appearance: NSAppearance.Name, console: Bool, onScreen: Bool) async throws {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        hb.select(nil)
        hb.segment = .installed
        hb.clearConsole()
        let channel = HelmWindowToolbarChannel()
        let model = SettingsModel(host: ModuleHost.shared)
        let window = settingsShaped(HomebrewSettingsPage(vm: mvm), appearance: appearance, channel: channel)
        let toolbar = SettingsToolbar(model: model, channel: channel)
        toolbar.window = window
        if onScreen { window.orderFrontRegardless() }
        settle(window, 40)
        await hb.loadIfNeeded()
        settle(window, 60)
        if console {
            transport.say("==> Pouring wget--1.25.0.arm64_tahoe.bottle.tar.gz")
            var yields = 0
            while hb.consoleLines.isEmpty && yields < 50_000 { await Task.yield(); yields += 1 }
            XCTAssertFalse(hb.consoleLines.isEmpty, "precondition: the console never came up")
            settle(window, 60)
        }
        let name = "window \(appearance == .aqua ? "Light" : "Dark") console \(console ? "on" : "off") "
            + (onScreen ? "on screen" : "off screen")
        let content = try XCTUnwrap(window.contentView)
        let table = try XCTUnwrap(StripedListEnd.table(in: content), "\(name): no table in the window")
        XCTAssertGreaterThanOrEqual(table.numberOfRows, transport.packages.count, """
            \(name): \(table.numberOfRows) rows for \(transport.packages.count) packages — the subject never arrived
            """)
        let reading = try XCTUnwrap(StripedListEnd.read(table, host: content), "\(name): no scroll view")
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        print("[list-end] \(name): \(reading) scrollFrameInWindow=\(scroll.convert(scroll.bounds, to: nil)) "
              + "scrollInsets=\(scroll.contentInsets.top)/\(scroll.contentInsets.bottom) "
              + "auto=\(scroll.automaticallyAdjustsContentInsets) "
              + "layoutRect=\(window.contentLayoutRect) content=\(content.bounds)")
        XCTAssertTrue(reading.scrollable, "\(name): the list did not scroll — \(reading)")
        XCTAssertLessThan(reading.overscroll, table.rowHeight / 2, """
            \(name): scrolled to its end the list shows \(reading.overscroll) pt of empty rows under \
            the last one (\(reading.overscroll / max(table.rowHeight, 1)) rows at \(table.rowHeight) pt) — \(reading)
            """)
        toolbar.window = nil
    }

    func testOffScreenLightWithoutTheConsole() async throws { try await read(.aqua, console: false, onScreen: false) }
    func testOffScreenDarkWithoutTheConsole() async throws { try await read(.darkAqua, console: false, onScreen: false) }
    func testOffScreenLightUnderTheConsole() async throws { try await read(.aqua, console: true, onScreen: false) }
    func testOffScreenDarkUnderTheConsole() async throws { try await read(.darkAqua, console: true, onScreen: false) }
    func testOnScreenDarkWithoutTheConsole() async throws { try await read(.darkAqua, console: false, onScreen: true) }
    func testOnScreenDarkUnderTheConsole() async throws { try await read(.darkAqua, console: true, onScreen: true) }
}
