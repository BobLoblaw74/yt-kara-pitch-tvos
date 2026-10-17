import SwiftUI

/// The strip across the top of the video, scrolling the next three songs that haven't failed.
struct Ticker: View {
    static let velocity: Double = 100  // points per second
    static let gap = "      ♪      "

    let entries: [QueueEntry]

    var body: some View {
        let text = Self.text(entries)
        HStack(spacing: 32) {
            Text("UP NEXT").font(.system(size: 28, weight: .bold)).kerning(4).foregroundStyle(Theme.pink)
            Marquee(text: text)
        }
        .padding(.leading, 64)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.opacity(0.78))
    }

    /// `1. Singer — Title (Key +2)`, joined with a note between songs.
    static func text(_ entries: [QueueEntry]) -> String {
        entries.prefix(3).enumerated().map { index, entry in
            var line = "\(index + 1). "
            if !entry.singer.isEmpty { line += "\(entry.singer) — " }
            line += entry.title
            if entry.presetKey != 0 { line += " (\(Key.label(entry.presetKey)))" }
            return line
        }
        .joined(separator: gap)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
