import SwiftUI

/// Full-screen search on the TV, drawn over whatever is playing (the song keeps going). Back closes
/// the add sheet first, then the screen. Songs added here are ready at once, and search stays open.
struct SearchView: View {
    let session: KaraSession

    private enum Results {
        case empty, loading
        case loaded([SearchResult])
        case failed(String)
    }

    private enum Focus: Hashable {
        case field
        case result(String)
    }

    @State private var query = ""
    @State private var karaoke = true
    @State private var results = Results.empty
    @State private var picked: SearchResult?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HStack {
                Text("Search songs").font(.system(size: 60, weight: .black)).foregroundStyle(Theme.text)
                Spacer()
                Text("Back to close").font(.system(size: 28)).foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 32) {
                TextField("Song or artist", text: $query)
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                    .focused($focus, equals: .field)
                Button(karaoke ? "+ karaoke ✓" : "+ karaoke") {
                    karaoke.toggle()
                    if case .loaded = results { runSearch() }
                }
                Button("Search", action: runSearch)
            }
            content
        }
        .padding(.horizontal, 80)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .defaultFocus($focus, .field)
        .sheet(item: $picked) { result in
            QuickAddSheet(result: result, singers: session.recentSingers()) { singer, key in
                Task {
                    await session.addFromSearch(result, singer: singer, key: key)
                    picked = nil
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch results {
        case .empty:
            hint("Type a song or artist, then press Search on the keyboard.")
        case .loading:
            HStack(spacing: 24) {
                ProgressView()
                hint("Searching…")
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 24) {
                hint(message)
                Button("Retry", action: runSearch)
            }
        case let .loaded(items) where items.isEmpty:
            hint("No songs found. Try different words.")
        case let .loaded(items):
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 48), count: 4), spacing: 64) {
                    ForEach(items, id: \.url) { result in
                        Button { picked = result } label: { ResultCard(result: result) }
                            .buttonStyle(.card)
                            .focused($focus, equals: .result(result.url))
                    }
                }
                .padding(.vertical, 40)
            }
            .scrollClipDisabled()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 36)).foregroundStyle(Theme.textDim)
    }

    private func runSearch() {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searchTask?.cancel()
        results = .loading
        searchTask = Task {
            do {
                let items = try await session.search(q, addKaraoke: karaoke)
                guard !Task.isCancelled else { return }
                results = .loaded(items)
                if let first = items.first { focus = .result(first.url) }
            } catch {
                guard !Task.isCancelled else { return }
                results = .failed("Search didn't work. Check the connection and try again.")
            }
        }
    }
}

extension SearchResult: Identifiable {
    var id: String { url }
}

private struct ResultCard: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: result.thumb.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.surfaceHigh
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if result.durationSec > 0 {
                    Text(String(format: "%d:%02d", result.durationSec / 60, result.durationSec % 60))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(result.title).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                if let channel = result.channel {
                    Text(channel).font(.system(size: 24)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Theme.surface)
    }
}
