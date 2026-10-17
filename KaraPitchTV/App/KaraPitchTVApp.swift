import SwiftUI

@main
struct KaraPitchTVApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // `-autoSpike` (launch argument) skips the menu, for driving the spike from simctl.
            if ProcessInfo.processInfo.arguments.contains("-autoSpike") {
                SpikeView()
            } else {
                SpikeMenu()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
    }
}

/// Spike 0 entry point: the pitch spike, plus the stream probe in debug builds.
private struct SpikeMenu: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Text("Kara Pitch — Spike 0").font(.largeTitle.bold())
                NavigationLink("Pitch spike") { SpikeView() }
                #if DEBUG
                NavigationLink("Stream probe") { ProbeView() }
                #endif
            }
        }
    }
}
