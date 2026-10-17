import Testing
@testable import KaraPitchTV

@MainActor
struct TickerTests {
    @Test func formatsNextThreeSongs() {
        let entries = [
            QueueEntry(id: "1", url: "u", title: "Dancing Queen", singer: "Sam", presetKey: 2),
            QueueEntry(id: "2", url: "u", title: "Bohemian Rhapsody"),
            QueueEntry(id: "3", url: "u", title: "Africa", singer: "Kim", presetKey: -1),
            QueueEntry(id: "4", url: "u", title: "Not shown"),
        ]
        #expect(Ticker.text(nowPlaying: nil, upcoming: entries) == "1. Sam — Dancing Queen (Key +2)\(Ticker.gap)2. Bohemian Rhapsody\(Ticker.gap)3. Kim — Africa (Key −1)")
    }

    @Test func putsTheSongPlayingNowFirst() {
        let now = QueueEntry(id: "0", url: "u", title: "Hello", singer: "Ana", presetKey: -2)
        let next = [QueueEntry(id: "1", url: "u", title: "Africa")]
        #expect(Ticker.text(nowPlaying: now, upcoming: next) == "Now: Ana — Hello (Key −2)\(Ticker.gap)1. Africa")
        #expect(Ticker.text(nowPlaying: now, upcoming: []) == "Now: Ana — Hello (Key −2)")
        #expect(Ticker.text(nowPlaying: nil, upcoming: []) == "")
    }
}
