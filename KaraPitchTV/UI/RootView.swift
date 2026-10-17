import SwiftUI

struct RootView: View {
    let session: KaraSession

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            switch session.phase {
            case .idle:
                IdleView(session: session)
            case let .upNext(entry, secondsLeft):
                UpNextCard(entry: entry, secondsLeft: secondsLeft, onStartNow: session.startNow)
            case let .playing(entry):
                PlayerScreen(session: session, entry: entry)
            }
            if let notice = session.notice {
                NoticeView(text: notice).padding(.top, 144).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.notice)
    }
}

private struct PlayerScreen: View {
    let session: KaraSession
    let entry: QueueEntry

    var body: some View {
        let snapshot = session.player.snapshot
        ZStack {
            PlayerHost(player: session.player.player, onAction: handle).ignoresSafeArea()
            if snapshot.durationMs == 0 { LoadingCard(entry: entry).ignoresSafeArea() }
            if snapshot.paused && snapshot.durationMs > 0 { NoticeView(text: "Paused") }
        }
    }

    private func handle(_ action: RemoteAction) {
        switch action {
        case .keyUp: session.adjustKey(+1)
        case .keyDown: session.adjustKey(-1)
        case .seekBack: session.player.seek(by: -10)
        case .seekForward: session.player.seek(by: +10)
        case .skip: session.skip(notice: "Skipped")
        case .togglePause: session.player.togglePause()
        case .back: session.backPressed()
        }
    }
}
