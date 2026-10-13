import GSRKit
import GSRUI
import SwiftUI

/// The Audio Articles and Podcast pages, loaded once and shared by the Listen and Latest tabs.
@MainActor
final class ListenModel: ObservableObject {
    static let shared = ListenModel()

    @Published private(set) var library: AudioLibrary?
    @Published private(set) var podcast: Podcast?
    @Published private(set) var libraryError: String?
    @Published private(set) var podcastError: String?
    @Published private(set) var loading = false

    private let client = ListenClient()

    func load(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        async let lib: Void = loadLibrary(force: force)
        async let pod: Void = loadPodcast(force: force)
        _ = await (lib, pod)
    }

    func loadLibrary(force: Bool = false) async {
        guard force || library == nil else { return }
        do {
            library = try await client.audioLibrary()
            libraryError = nil
        } catch {
            libraryError = Self.message(error, page: "Audio Articles")
        }
    }

    private func loadPodcast(force: Bool) async {
        guard force || podcast == nil else { return }
        do {
            podcast = try await client.podcast()
            podcastError = nil
        } catch {
            podcastError = Self.message(error, page: "Podcast")
        }
    }

    private static func message(_ error: Error, page: String) -> String {
        if case ListenError.pageChanged = error {
            return "The \(page) page changed, and this version of the app cannot read it. Open the page to listen there."
        }
        return "The \(page) page did not load. Pull down to try again."
    }
}

/// Narrated articles and podcast episodes, played in the app, with the notes the site puts
/// on them about how they are made.
struct ListenView: View {
    enum Shelf: String, CaseIterable, Identifiable {
        case articles = "Audio articles"
        case podcast = "Podcast"
        var id: String { rawValue }
    }

    enum VoiceFilter: String, CaseIterable, Identifiable {
        // The site's own filter labels.
        case all = "All voices"
        case dexter = "Dexter Dow’s voice"
        case synthetic = "Synthetic voice"
        var id: String { rawValue }
    }

    @EnvironmentObject private var listen: ListenModel
    @EnvironmentObject private var player: AudioPlayer
    @State private var shelf: Shelf = .articles
    @State private var query = ""
    @State private var voice: VoiceFilter = .all
    @State private var page: WebPage?

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $shelf) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(GSRTheme.paper2)
                .listRowSeparator(.hidden)

                switch shelf {
                case .articles: articles
                case .podcast: episodes
                }

                Text("Audio articles play from ElevenLabs’ servers and podcast episodes from granitestatereport.com, as they do on the site. Those servers see your IP address. Where you stopped in each recording is kept on this phone only.")
                    .font(.caption)
                    .foregroundStyle(GSRTheme.ink3)
                    .listRowBackground(GSRTheme.paper2)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(GSRTheme.paper2.ignoresSafeArea())
            .navigationTitle("Listen")
            .searchable(text: $query, prompt: shelf == .articles ? "Title, month, or year" : "Episode title")
            .refreshable { await listen.load(force: true) }
            .task { await listen.load() }
            .navigationDestination(for: String.self) { id in
                if let ep = listen.podcast?.episodes.first(where: { $0.id == id }) {
                    EpisodeView(episode: ep)
                }
            }
            .sheet(item: $page) { p in SafariView(url: p.url).ignoresSafeArea() }
        }
    }

    // MARK: Audio articles

    @ViewBuilder
    private var articles: some View {
        if let lib = listen.library {
            Disclosure(text: lib.disclosure, page: ListenClient.audioLibraryPage) { page = WebPage($0) }
            Picker("Voice", selection: $voice) {
                ForEach(VoiceFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(GSRTheme.navy)
            .listRowBackground(GSRTheme.paper2)
            let shown = filtered(lib.articles)
            Text(shown.count == lib.articles.count ? "Showing all \(lib.articles.count) recordings." : "Showing \(shown.count) of \(lib.articles.count) recordings.")
                .font(.caption)
                .foregroundStyle(GSRTheme.ink3)
                .listRowBackground(GSRTheme.paper2)
            ForEach(shown) { a in
                ArticleAudioRow(article: a) { page = WebPage(a.articleURL) }
                    .listRowBackground(GSRTheme.paper2)
                    .listRowSeparatorTint(GSRTheme.rule2)
            }
        } else if let e = listen.libraryError {
            Failure(text: e) { page = WebPage(ListenClient.audioLibraryPage) }
        } else {
            ProgressView("Loading the audio articles…")
                .frame(maxWidth: .infinity)
                .listRowBackground(GSRTheme.paper2)
        }
    }

    private func filtered(_ all: [AudioArticle]) -> [AudioArticle] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { a in
            switch voice {
            case .all: break
            case .dexter: if a.isSynthetic { return false }
            case .synthetic: if !a.isSynthetic { return false }
            }
            return q.isEmpty || a.title.lowercased().contains(q) || a.date.lowercased().contains(q)
        }
    }

    // MARK: Podcast

    @ViewBuilder
    private var episodes: some View {
        if let pod = listen.podcast {
            Disclosure(text: pod.disclosure, page: ListenClient.podcastPage) { page = WebPage($0) }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            ForEach(pod.episodes.filter { q.isEmpty || $0.title.lowercased().contains(q) }) { ep in
                NavigationLink(value: ep.id) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ep.title)
                            .font(GSRTheme.serif(.headline, bold: true))
                            .foregroundStyle(GSRTheme.navy)
                        Text([ep.made, ep.hosts, ep.duration].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GSRTheme.ink3)
                        Text(ep.summary)
                            .font(GSRTheme.serif(.subheadline))
                            .foregroundStyle(GSRTheme.ink)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(GSRTheme.paper2)
                .listRowSeparatorTint(GSRTheme.rule2)
            }
        } else if let e = listen.podcastError {
            Failure(text: e) { page = WebPage(ListenClient.podcastPage) }
        } else {
            ProgressView("Loading the podcast…")
                .frame(maxWidth: .infinity)
                .listRowBackground(GSRTheme.paper2)
        }
    }
}

/// The page's note on how its recordings are made, word for word, always above the list.
private struct Disclosure: View {
    let text: String
    let page: URL
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(GSRTheme.ink)
            Button("From the page, word for word. Open it") { open(page) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(GSRTheme.rust)
        }
        .padding(12)
        .background(GSRTheme.paper3)
        .overlay(alignment: .leading) { Rectangle().fill(GSRTheme.navy).frame(width: 3) }
        .listRowBackground(GSRTheme.paper2)
        .listRowSeparator(.hidden)
    }
}

private struct Failure: View {
    let text: String
    let open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.footnote).foregroundStyle(GSRTheme.rust)
            Button("Open the page", action: open)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .tint(GSRTheme.rust)
        }
        .listRowBackground(GSRTheme.paper2)
    }
}

struct ArticleAudioRow: View {
    let article: AudioArticle
    let read: () -> Void
    @EnvironmentObject private var player: AudioPlayer

    private var playable: Playable {
        Playable(url: article.audioURL, title: article.title, voice: article.voice,
                 page: article.articleURL, listedDuration: Clock.seconds(article.duration))
    }

    var body: some View {
        let isCurrent = player.current?.url == article.audioURL
        HStack(alignment: .top, spacing: 12) {
            Button {
                if isCurrent { player.toggle() } else { player.play(playable) }
            } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(GSRTheme.rust)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isCurrent && player.isPlaying ? "Pause" : "Play \(article.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(GSRTheme.serif(.headline, bold: true))
                    .foregroundStyle(GSRTheme.navy)
                Text([article.date, article.voice, article.duration].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(article.isSynthetic ? GSRTheme.rust : GSRTheme.ink3)
                if let note = article.note {
                    Text(note).font(.caption).foregroundStyle(GSRTheme.ink2)
                }
                if !isCurrent, let at = player.resumePoint(article.audioURL) {
                    Text("Resumes at \(Clock.text(at))").font(.caption).foregroundStyle(GSRTheme.ink2)
                }
                Button("Read the article", action: read)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(GSRTheme.rust)
            }
        }
        .padding(.vertical, 6)
    }
}

/// One podcast episode: what it covers, the listener's note, the articles, the transcript.
struct EpisodeView: View {
    let episode: PodcastEpisode
    @EnvironmentObject private var player: AudioPlayer
    @State private var page: WebPage?
    @State private var showTranscript = false

    private var playable: Playable {
        Playable(url: episode.audioURL, title: episode.title, voice: episode.hosts,
                 page: ListenClient.podcastPage, listedDuration: Clock.seconds(episode.duration))
    }

    var body: some View {
        let isCurrent = player.current?.url == episode.audioURL
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(episode.title)
                    .font(GSRTheme.serif(.title, bold: true))
                    .foregroundStyle(GSRTheme.navy)
                    .accessibilityAddTraits(.isHeader)
                Text([episode.made, episode.hosts, episode.duration].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GSRTheme.ink3)
                Text(episode.summary).font(GSRTheme.serif(.body)).foregroundStyle(GSRTheme.ink)
                Button(isCurrent && player.isPlaying ? "Pause" : "Play the episode") {
                    if isCurrent { player.toggle() } else { player.play(playable) }
                }
                .buttonStyle(GSRButtonStyle())

                if !episode.note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Listener’s note")
                            .font(GSRTheme.serif(.headline, bold: true))
                            .foregroundStyle(GSRTheme.navy)
                        ForEach(episode.note, id: \.self) { n in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(GSRTheme.rust)
                                Text(n)
                            }
                            .font(GSRTheme.serif(.subheadline))
                            .foregroundStyle(GSRTheme.ink)
                        }
                    }
                    .padding(14)
                    .background(GSRTheme.rustSoft)
                    .overlay(alignment: .leading) { Rectangle().fill(GSRTheme.rust).frame(width: 4) }
                }

                if !episode.articles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Articles discussed in this episode")
                            .font(GSRTheme.serif(.headline, bold: true))
                            .foregroundStyle(GSRTheme.navy)
                        ForEach(episode.articles, id: \.url) { a in
                            Button { page = WebPage(a.url) } label: {
                                Text(a.text)
                                    .font(GSRTheme.serif(.subheadline))
                                    .multilineTextAlignment(.leading)
                            }
                            .tint(GSRTheme.rust)
                        }
                    }
                }

                if !episode.transcript.isEmpty {
                    DisclosureGroup("Read the transcript", isExpanded: $showTranscript) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(episode.transcript.enumerated()), id: \.offset) { _, line in
                                (Text(line.speaker.map { $0 + ": " } ?? "").bold() + Text(line.text))
                                    .font(GSRTheme.serif(.subheadline))
                                    .foregroundStyle(GSRTheme.ink)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(GSRTheme.serif(.headline, bold: true))
                    .tint(GSRTheme.rust)
                }
            }
            .padding(18)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(GSRTheme.paper2.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $page) { p in SafariView(url: p.url).ignoresSafeArea() }
    }
}

/// The bar above the tabs while something is loaded in the player.
struct MiniPlayer: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var showPlayer = false

    var body: some View {
        if let c = player.current {
            HStack(spacing: 12) {
                Button { showPlayer = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(c.voice).font(.caption).foregroundStyle(GSRTheme.ink3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the player")
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.stop() } label: {
                    Image(systemName: "xmark").font(.subheadline)
                }
                .accessibilityLabel("Stop and close the player")
            }
            .foregroundStyle(GSRTheme.navy)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GSRTheme.paper)
            .overlay(alignment: .top) { Rectangle().fill(GSRTheme.rule2).frame(height: 1) }
            .sheet(isPresented: $showPlayer) { PlayerSheet() }
        }
    }
}

struct PlayerSheet: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var scrub: Double?
    @State private var page: WebPage?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                if let c = player.current {
                    Text(c.title)
                        .font(GSRTheme.serif(.title2, bold: true))
                        .foregroundStyle(GSRTheme.navy)
                    Text(c.voice).font(.subheadline).foregroundStyle(GSRTheme.ink2)
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }),
                               in: 0...max(player.duration, 1)) { editing in
                            if !editing, let s = scrub {
                                player.seek(to: s)
                                scrub = nil
                            }
                        }
                        .tint(GSRTheme.rust)
                        .accessibilityLabel("Position")
                        .accessibilityValue(Clock.text(scrub ?? player.position))
                        HStack {
                            Text(Clock.text(scrub ?? player.position))
                            Spacer()
                            Text(player.duration > 0 ? "-" + Clock.text(max(0, player.duration - (scrub ?? player.position))) : "")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(GSRTheme.ink3)
                    }
                    HStack(spacing: 40) {
                        Spacer()
                        Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.title) }
                            .accessibilityLabel("Back 15 seconds")
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 60))
                        }
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                        Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15").font(.title) }
                            .accessibilityLabel("Forward 15 seconds")
                        Spacer()
                    }
                    .foregroundStyle(GSRTheme.navy)
                    if player.isBuffering { ProgressView().frame(maxWidth: .infinity) }
                    if let f = player.failed {
                        Text(f).font(.footnote).foregroundStyle(GSRTheme.rust)
                    }
                    Picker("Speed", selection: $player.rate) {
                        ForEach(AudioPlayer.rates, id: \.self) { r in
                            Text(r == 1 ? "1×" : String(format: "%g×", r)).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button { page = WebPage(c.page) } label: {
                        Label(c.page == ListenClient.podcastPage ? "Open the podcast page" : "Read the article", systemImage: "safari")
                    }
                    .tint(GSRTheme.rust)
                    Spacer()
                } else {
                    Text("Nothing is playing.").font(GSRTheme.serif(.body))
                    Spacer()
                }
            }
            .padding(22)
            .background(GSRTheme.paper2.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $page) { p in SafariView(url: p.url).ignoresSafeArea() }
        }
        .presentationDetents([.large])
    }
}
