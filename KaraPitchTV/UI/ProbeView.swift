import SmartTubeIOSCore
import SwiftUI

/// Runs `StreamProbe` over a fresh set of karaoke videos and shows one line per video × client.
struct ProbeView: View {
    @State private var rows: [ProbeRow] = []
    @State private var status = "Searching…"

    var body: some View {
        List {
            Section(status) {
                ForEach(StreamProbe.summary(rows), id: \.client) { line in
                    Text("\(line.client.rawValue): usable for \(line.usable)/\(line.total)").font(.headline)
                }
            }
            Section("Rows") {
                ForEach(rows) { row in
                    Button {} label: { Text(row.summary).font(.caption.monospaced()) }
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        let api = InnerTubeAPI()
        do {
            let ids = try await StreamProbe.karaokeVideoIDs(api: api)
            status = "Probing \(ids.count) videos…"
            for id in ids {
                for client in StreamClient.allCases {
                    rows.append(await StreamProbe.probe(videoID: id, client: client, api: api))
                }
            }
            status = "Done: \(ids.count) videos"
        } catch {
            status = "Search failed: \(error)"
        }
    }
}
