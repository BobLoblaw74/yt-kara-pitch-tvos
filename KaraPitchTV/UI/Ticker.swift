import SwiftUI

/// The strip across the top of the video and the search screen: the song playing now, then the
/// next three that haven't failed, with the phone address and QR code at the right end. Always
/// shown, so phones can join at any time.
struct Ticker: View {
    static let velocity: Double = 100  // points per second
    static let gap = "      ♪      "
    static let emptyText = "Nothing queued yet. Scan the code to add songs from your phone."

    let state: QueueState

    var body: some View {
        let text = Self.text(nowPlaying: state.nowPlaying, upcoming: state.queue.filter { $0.status != .error })
        HStack(spacing: 32) {
            Text("QUEUE").font(.system(size: 28, weight: .bold)).kerning(4).foregroundStyle(Theme.pink)
            Marquee(text: text.isEmpty ? Self.emptyText : text)
            PhoneQRBadge()
        }
        .padding(.leading, 64)
        .padding(.trailing, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.opacity(0.78))
    }

    /// `Now: Singer — Title`, then `1. Singer — Title (Key +2)`, joined with a note between songs.
    static func text(nowPlaying: QueueEntry?, upcoming: [QueueEntry]) -> String {
        let now = nowPlaying.map { "Now: " + line($0) }
        let next = upcoming.prefix(3).enumerated().map { index, entry in "\(index + 1). " + line(entry) }
        return ([now].compactMap { $0 } + next).joined(separator: gap)
    }

    private static func line(_ entry: QueueEntry) -> String {
        var line = entry.singer.isEmpty ? "" : "\(entry.singer) — "
        line += entry.title
        if entry.presetKey != 0 { line += " (\(Key.label(entry.presetKey)))" }
        return line
    }
}

/// One line of text scrolling left forever, drawn twice so the loop has no seam.
private struct Marquee: View {
    let text: String
    @State private var width: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = width + 240
            let offset = cycle > 240 ? -(context.date.timeIntervalSinceReferenceDate * Ticker.velocity).truncatingRemainder(dividingBy: cycle) : 0
            HStack(spacing: 240) {
                label
                label
            }
            .offset(x: offset)
        }
        // minWidth 0: without it the frame takes on the text's full width, which pushes the whole ticker,
        // and anything sized with it, off both sides of the screen.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 36))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }
}
