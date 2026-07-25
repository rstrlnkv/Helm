import SwiftUI
import Module_Island_Engine

/// SwiftUI content of the island window. Two expanded flavours:
///  - `.controls` (hover): a horizontal pill under the notch — now playing,
///    play/pause, volume slider, compact shelf chips. Grows sideways only.
///  - `.shelf` (drag in progress or a fresh drop): the vertical drop card.
/// The window frame is static — only this view animates.
struct IslandView: View {
    @ObservedObject var model: IslandModel
    /// Injected by the descriptor: shelf content inside the drop card.
    var content: AnyView = AnyView(EmptyView())
    /// Compact chips for the controls pill (drag-out access to parked files).
    var chips: AnyView = AnyView(EmptyView())

    var body: some View {
        ZStack(alignment: .top) {
            // Tap-away collapses while expanded (the window is ordered out in
            // hidden state, so this never blocks clicks when idle).
            if model.state == .expanded {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { model.dismiss() }
            }
            if model.state != .hidden {
                islandShape
                    .onHover { inside in model.hover(inside) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.28), value: model.state)
        .animation(.easeInOut(duration: 0.28), value: model.mode)
        .animation(.easeInOut(duration: 0.2), value: model.receivingDrag)
    }

    private var expanded: Bool { model.state == .expanded }
    private var shelfMode: Bool { model.mode == .shelf }

    private var islandShape: some View {
        VStack(spacing: 0) {
            if expanded {
                if shelfMode {
                    content
                        .frame(width: cardWidth - 32)
                        .padding(.top, model.notchHeight + 2)
                        .padding(.bottom, 16)
                } else {
                    controlsPill
                        .padding(.top, model.notchHeight + 2)
                        .padding(.bottom, 8)
                }
            } else {
                peekLine
                    .padding(.top, model.notchHeight + 2)
                    .padding(.bottom, 7)
            }
        }
        .frame(width: shapeWidth)
        .compositingGroup()
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 22, bottomTrailing: 22),
                                   style: .continuous)
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 22, bottomTrailing: 22),
                                           style: .continuous)
                        .strokeBorder(model.receivingDrag ? Color.accentColor : Color.white.opacity(0.12),
                                      lineWidth: model.receivingDrag ? 2 : 1)
                )
        )
        .clipped()
    }

    private var shapeWidth: CGFloat {
        guard expanded else { return model.notchWidth + 24 }
        return shelfMode ? cardWidth : model.notchWidth + 380
    }

    private var cardWidth: CGFloat { model.notchWidth + 260 }

    // MARK: - Controls pill (hover, horizontal growth only)

    private var controlsPill: some View {
        HStack(spacing: 12) {
            if let title = model.nowPlayingTitle {
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .leading)
                Button { model.playPause() } label: {
                    Image(systemName: model.nowPlayingPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                Divider().frame(height: 14)
            }
            if model.volumeAvailable {
                Image(systemName: volumeSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: Binding(get: { model.volume },
                                      set: { model.setVolume($0) }), in: 0...1)
                    .controlSize(.mini)
                    .frame(width: 130)
            }
            chips
        }
        .foregroundStyle(.white)
        .frame(height: 26)
        .padding(.horizontal, 18)
    }

    private var volumeSymbol: String {
        model.volume == 0 ? "speaker.slash"
            : model.volume < 0.5 ? "speaker.wave.1" : "speaker.wave.2"
    }

    // MARK: - Peek

    @ViewBuilder private var peekLine: some View {
        if model.eventIsVolume {
            // Mini volume HUD: icon + level bar instead of text.
            HStack(spacing: 8) {
                Image(systemName: volumeSymbol).font(.caption)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(model.volume))
                    }
                }
                .frame(width: 110, height: 4)
            }
            .foregroundStyle(.white)
            .frame(height: 16)
        } else {
            HStack(spacing: 6) {
                if let symbol = model.eventSymbol {
                    Image(systemName: symbol).font(.caption)
                }
                if let text = model.eventText {
                    Text(text).font(.caption)
                }
            }
            .foregroundStyle(.white)
        }
    }
}
