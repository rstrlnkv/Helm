import SwiftUI
import Module_Island_Engine

/// SwiftUI content of the island window. Deep-black shape, no border, fluid
/// spring morphing. Three visual forms:
///  - compact "ears" pill hugging the notch: artwork in the left ear, animated
///    equalizer in the right (horizontal reveal, notch-height);
///  - full media card below the notch: artwork, title/artist, progress with
///    times, transport controls and a volume slider;
///  - the vertical drop card, only while a file drag is in flight.
struct IslandView: View {
    @ObservedObject var model: IslandModel
    var content: AnyView = AnyView(EmptyView())
    var chips: AnyView = AnyView(EmptyView())

    private let fluid = Animation.spring(response: 0.42, dampingFraction: 0.78)

    var body: some View {
        ZStack(alignment: .top) {
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
        .animation(fluid, value: model.state)
        .animation(fluid, value: model.mode)
        .animation(fluid, value: model.stage)
        .animation(fluid, value: model.receivingDrag)
    }

    private var expanded: Bool { model.state == .expanded }
    private var shelfMode: Bool { model.mode == .shelf }
    private var fullStage: Bool { expanded && model.stage == .full }

    private var islandShape: some View {
        VStack(spacing: 0) {
            if shelfMode && expanded {
                content
                    .frame(width: cardWidth - 32)
                    .padding(.top, model.notchHeight + 2)
                    .padding(.bottom, 16)
            } else if fullStage {
                mediaCard
                    .padding(.top, model.notchHeight + 6)
                    .padding(.bottom, 14)
                    .padding(.horizontal, 18)
            } else if expanded {
                earsRow
            } else {
                peekLine
            }
        }
        .frame(width: shapeWidth)
        .compositingGroup()
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: bottomRadius,
                                                      bottomTrailing: bottomRadius),
                                   style: .continuous)
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
        )
        .clipped()
    }

    private var shapeWidth: CGFloat {
        if shelfMode && expanded { return cardWidth }
        if fullStage { return cardWidth }
        if expanded { return model.notchWidth + 2 * earWidth }
        return model.notchWidth + 2 * earWidth   // peek shares the ears geometry
    }

    private var bottomRadius: CGFloat { (fullStage || (shelfMode && expanded)) ? 24 : 12 }
    private var cardWidth: CGFloat { model.notchWidth + 260 }
    private let earWidth: CGFloat = 56

    // MARK: - Compact ears (horizontal reveal / media peek)

    private var earsRow: some View {
        HStack(spacing: 0) {
            earArtwork
                .frame(width: earWidth)
            Color.clear.frame(width: model.notchWidth)
            EQBars(playing: model.nowPlayingPlaying)
                .frame(width: earWidth)
        }
        .frame(height: model.notchHeight + 6)
    }

    @ViewBuilder private var earArtwork: some View {
        if model.nowPlayingTitle != nil {
            artworkView(size: 18, corner: 5)
        } else {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Full media card

    private var mediaCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                artworkView(size: 44, corner: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.nowPlayingTitle ?? IsStr.notPlaying)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let artist = model.nowPlayingArtist {
                        Text(artist)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                EQBars(playing: model.nowPlayingPlaying)
            }

            if model.nowPlayingDuration > 0 {
                HStack(spacing: 8) {
                    Text(Self.time(model.nowPlayingPosition))
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.22))
                            Capsule().fill(Color.white.opacity(0.85))
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    Text("-" + Self.time(max(model.nowPlayingDuration - model.nowPlayingPosition, 0)))
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            HStack(spacing: 26) {
                if model.nowPlayingTitle != nil {
                    Button { model.previousTrack() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 15))
                    }
                    Button { model.playPause() } label: {
                        Image(systemName: model.nowPlayingPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 21))
                    }
                    Button { model.nextTrack() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 15))
                    }
                }
                if model.volumeAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: volumeSymbol)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        Slider(value: Binding(get: { model.volume },
                                              set: { model.setVolume($0) }), in: 0...1)
                            .controlSize(.mini)
                            .tint(.white)
                            .frame(width: model.nowPlayingTitle == nil ? 170 : 96)
                    }
                }
                chips
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .frame(width: cardWidth - 68)
    }

    private var progress: CGFloat {
        guard model.nowPlayingDuration > 0 else { return 0 }
        return CGFloat(min(model.nowPlayingPosition / model.nowPlayingDuration, 1))
    }

    @ViewBuilder private func artworkView(size: CGFloat, corner: CGFloat) -> some View {
        Group {
            if let url = model.nowPlayingArtwork {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    artworkPlaceholder
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        LinearGradient(colors: [Color(.sRGB, red: 0.45, green: 0.30, blue: 0.75, opacity: 1),
                                Color(.sRGB, red: 0.18, green: 0.12, blue: 0.35, opacity: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "music.note")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.9)))
    }

    private var volumeSymbol: String {
        model.volume == 0 ? "speaker.slash"
            : model.volume < 0.5 ? "speaker.wave.1" : "speaker.wave.2"
    }

    // MARK: - Peek (transient events while otherwise hidden)

    @ViewBuilder private var peekLine: some View {
        if model.eventIsVolume {
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
            .padding(.top, model.notchHeight + 2)
            .padding(.bottom, 7)
        } else if model.nowPlayingTitle != nil {
            // Media events reuse the ears geometry.
            earsRow
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
            .padding(.top, model.notchHeight + 2)
            .padding(.bottom, 7)
        }
    }

    private static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Animated equalizer: bouncing capsules while playing, dots at rest.
struct EQBars: View {
    var playing: Bool
    @State private var up = false

    private let tall: [CGFloat] = [10, 15, 8, 13]
    private let short: [CGFloat] = [5, 8, 12, 6]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2.5, height: playing ? (up ? tall[i] : short[i]) : 3)
            }
        }
        .frame(height: 16)
        .animation(playing ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true) : .default,
                   value: up)
        .onAppear { up = true }
        .onChange(of: playing) { _, p in up = p }
    }
}
