import SwiftUI

@main
struct KaraPitchTVApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = KaraSession()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .task {
                    session.start()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-seed") { await DebugSeed.addTestSongs(to: session) }
                    #endif
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keeps the screensaver away on every screen, idle included.
            UIApplication.shared.isIdleTimerDisabled = phase == .active
            session.setActive(phase == .active)
        }
    }
}
