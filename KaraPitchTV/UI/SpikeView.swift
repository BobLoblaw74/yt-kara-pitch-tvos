import SwiftUI

/// Spike 0 on the device: up/down = key, left/right = ∓10 s, Select or Play/Pause = pause.
struct SpikeView: View {
    /// A ~5-minute karaoke track; the first search hit is played.
    static let query = "Bohemian Rhapsody karaoke"

    @State private var player = SpikePlayer()

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlayerHost(player: player.player, onPress: handle)
                .ignoresSafeArea()
            HUD(status: player.status, hud: player.hud)
                .padding(40)
                .allowsHitTesting(false)
        }
        .task { await player.start(query: Self.query) }
        .onDisappear { player.player.pause() }
    }

    private func handle(_ press: UIPress.PressType) {
        switch press {
        case .upArrow: player.adjustKey(+1)
        case .downArrow: player.adjustKey(-1)
        case .leftArrow: player.seek(by: -10)
        case .rightArrow: player.seek(by: +10)
        case .select, .playPause: player.togglePause()
        default: break
        }
    }
}

private struct HUD: View {
    let status: String
    let hud: SpikeHUD

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(status).font(.headline)
            Text(hud.streams)
            Text("\(Key.label(hud.key))  ·  \(time(hud.position)) / \(time(hud.duration))")
            Text("A/V offset \(hud.avOffsetMillis.map { "\($0) ms" } ?? "–")  ·  tap load \(hud.tapLoadPercent, specifier: "%.1f")%")
            Text("Tap: \(hud.tapStatus) · \(hud.tapBuffers) buffers")
            if let code = hud.lastHTTPError { Text("HTTP error \(code)").foregroundStyle(.red) }
        }
        .font(.callout.monospaced())
        .padding(24)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func time(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
