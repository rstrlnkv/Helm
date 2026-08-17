import HelmUI
import SwiftUI

/// The page, until the tab that fills it is written.
///
/// It keeps the view model it is handed rather than dropping it, because the
/// page's whole content arrives through that one wire and every other module's
/// page is built the same way — `ModulePageRender` carries a floor of 1 for
/// this module, and removing that entry is what says the page has landed.
struct HostsSettingsPage: View {
    private let vm: ModuleViewModel
    init(vm: ModuleViewModel) { self.vm = vm }
    var body: some View { EmptyView() }
}
