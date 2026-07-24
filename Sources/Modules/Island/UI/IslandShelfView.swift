import AppKit
import SwiftUI
import Module_Island_Engine

/// Observable adapter over the engine's ShelfStore.
@MainActor final class ShelfViewModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    let store: ShelfStore

    init(store: ShelfStore) {
        self.store = store
        items = store.items
        store.onChange = { [weak self] in self?.items = self?.store.items ?? [] }
    }

    func add(_ urls: [URL]) { store.add(urls) }
    func remove(_ id: UUID) { store.remove(id) }
    func clear() { store.clear() }
}

/// The shelf inside the expanded island: drop zone + item grid; items drag out
/// with standard file semantics (the destination decides copy vs move).
struct IslandShelfView: View {
    @ObservedObject var shelf: ShelfViewModel
    @ObservedObject var model: IslandModel
    var onDropped: () -> Void = {}

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: 10)]

    var body: some View {
        VStack(spacing: 8) {
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(IsStr.dropHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(shelf.items) { item in
                            shelfCell(item)
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxHeight: 190)
                HStack {
                    Text(IsStr.itemCount(shelf.items.count))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(IsStr.clear) { shelf.clear() }
                        .controlSize(.small)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            onDropped()
            return true
        } isTargeted: { targeted in
            model.receivingDrag = targeted
        }
    }

    private func shelfCell(_ item: ShelfItem) -> some View {
        VStack(spacing: 4) {
            Group {
                if let url = item.url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.missing ? .secondary : .primary)
        }
        .frame(width: 84)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .opacity(item.missing ? 0.55 : 1)
        .onDrag {
            guard let url = item.url else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .contextMenu {
            if let url = item.url {
                Button(IsStr.revealInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button(IsStr.remove) { shelf.remove(item.id) }
        }
        .help(item.url?.path ?? item.name)
    }
}
