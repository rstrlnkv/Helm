import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

extension LiftRig {
    /// Puts the arrow keys' choice on the tile with this id, as the arrow keys do (the first press chooses the first tile).
    func choose(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let flat = state.pages.joined().map(\.id)
        guard let at = flat.firstIndex(of: id) else { return XCTFail("no tile \(id)", file: file, line: line) }
        for _ in 0...at where state.selection.map({ flat[$0] }) != id { state.move(dx: 1, dy: 0) }
        XCTAssertEqual(state.selection.map { flat[$0] }, id, "subject: the choice is on \(id)", file: file, line: line)
    }

    /// The layout the engine holds now.
    var layout: LaunchpadLayout { engine.read().layout }

    /// Every app the layout places, in order, one entry for each occurrence: a lost app is missing, a copied one is there twice.
    var placedApps: [String] {
        layout.items.flatMap { item -> [String] in
            switch item {
            case .app(let id): [id]
            case .folder(let f): f.apps
            case .pageBreak: []
            }
        }
    }
}
