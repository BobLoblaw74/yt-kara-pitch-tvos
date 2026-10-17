#if DEBUG
import Foundation
import SmartTubeIOSCore

/// Queues a few karaoke songs until phones can add them (Phase 3). Also run at launch with the
/// `-seed` launch argument, for driving the app from `simctl`.
enum DebugSeed {
    static let queries = ["Bohemian Rhapsody karaoke", "Dancing Queen karaoke", "Don't Stop Believin' karaoke"]
    static let singers = ["Alex", "Sam", ""]

    @MainActor
    static func addTestSongs(to session: KaraSession) async {
        let api = InnerTubeAPI()
        for (index, query) in queries.enumerated() {
            guard let video = try? await api.search(query: query).videos.first(where: { !$0.isLive && ($0.duration ?? 0) > 60 }) else {
                session.notify("Search failed for “\(query)”")
                continue
            }
            // The first goes through the background lookup (like a pasted link), the rest carry metadata.
            let meta = index == 0 ? nil : VideoMeta(video)
            _ = try? await session.store.add(
                url: "https://www.youtube.com/watch?v=\(video.id)", singer: singers[index], key: index == 1 ? 2 : 0, meta: meta)
        }
    }
}
#endif
