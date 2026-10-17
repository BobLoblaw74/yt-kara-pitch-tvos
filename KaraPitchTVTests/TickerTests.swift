import Testing
@testable import KaraPitchTV

struct TickerTests {
    @Test func formatsNextThreeSongs() {
        let entries = [
            QueueEntry(id: "1", url: "u", title: "Dancing Queen", singer: "Sam", presetKey: 2),
            QueueEntry(id: "2", url: "u", title: "Bohemian Rhapsody"),
            QueueEntry(id: "3", url: "u", title: "Africa", singer: "Kim", presetKey: -1),
            QueueEntry(id: "4", url: "u", title: "Not shown"),
        ]
        #expect(Ticker.text(entries) == "1. Sam — Dancing Queen (Key +2)\(Ticker.gap)2. Bohemian Rhapsody\(Ticker.gap)3. Kim — Africa (Key −1)")
    }
}
