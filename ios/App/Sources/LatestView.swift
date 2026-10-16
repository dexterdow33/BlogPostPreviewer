import GSRKit
import GSRUI
import SwiftUI

/// The newest stories from granitestatereport.com, opened in the app's browser sheet, with
/// a Listen button on the ones the Audio Articles page has a narration for.
struct LatestView: View {
    @EnvironmentObject private var listen: ListenModel
    @State private var stories: [Story] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page: WebPage?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(GSRTheme.rust)
                        .listRowBackground(GSRTheme.paper2)
                }
                ForEach(stories) { story in
                    VStack(alignment: .leading, spacing: 0) {
                        Button { page = WebPage(story.link) } label: { StoryRow(story: story) }
                            .buttonStyle(.plain)
                        if let narration = listen.library?.narration(for: story.link) {
                            ListenButton(article: narration)
                        }
                    }
                    .listRowBackground(GSRTheme.paper2)
                    .listRowSeparatorTint(GSRTheme.rule2)
                }
                if !stories.isEmpty {
                    Section {
                        ForEach(GSRTools.all, id: \.name) { tool in
                            Button { page = WebPage(tool.url) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tool.name + (tool.subscribers ? " · subscribers" : ""))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(GSRTheme.navy)
                                    Text(tool.blurb).font(.footnote).foregroundStyle(GSRTheme.ink2)
                                }
                            }
                        }
                        Button { page = WebPage(GSRContact.site) } label: {
                            Label("Everything on granitestatereport.com", systemImage: "safari")
                        }
                    } header: {
                        Text("GSR tools")
                    } footer: {
                        Text(GSRTools.note)
                    }
                    .listRowBackground(GSRTheme.paper)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(GSRTheme.paper2.ignoresSafeArea())
            .overlay {
                if loading && stories.isEmpty { ProgressView("Loading the latest stories…") }
            }
            .navigationTitle("Latest")
            .refreshable { await load() }
            .task { if stories.isEmpty { await load() } }
            .sheet(item: $page) { p in SafariView(url: p.url).ignoresSafeArea() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let narrations: Void = listen.loadLibrary()
        do {
            stories = try await FeedClient().latest(count: 20)
            error = nil
        } catch {
            self.error = "The latest stories did not load. Pull down to try again."
        }
        await narrations
    }
}

/// "Listen · 11:07 · Dexter Dow’s voice", under a story with a narration.
struct ListenButton: View {
    let article: AudioArticle
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        let isCurrent = player.current?.url == article.audioURL
        Button {
            if isCurrent {
                player.toggle()
            } else {
                player.play(Playable(url: article.audioURL, title: article.title, voice: article.voice,
                                     page: article.articleURL, listedDuration: Clock.seconds(article.duration)))
            }
        } label: {
            Label(isCurrent && player.isPlaying ? "Pause" : "Listen · \(article.duration) · \(article.voice)",
                  systemImage: isCurrent && player.isPlaying ? "pause.fill" : "headphones")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .tint(GSRTheme.rust)
        .padding(.bottom, 8)
    }
}

/// The site's GSR tools, as its Send menu lists them (granitestatereport.com, October 2026).
enum GSRTools {
    struct Tool {
        let name: String
        let blurb: String
        let url: URL
        let subscribers: Bool
    }

    static let note = "Free, built by this newsroom. The three marked open with a free email subscription."

    static let all: [Tool] = [
        Tool(name: "91-A Request Builder", blurb: "Writes a Right-to-Know request that cites RSA 91-A:4 and computes the five-business-day response date.",
             url: URL(string: "https://granitestatereport.com/91a-request-builder/")!, subscribers: true),
        Tool(name: "Redact", blurb: "Black out a document so the text underneath is gone, not covered.",
             url: URL(string: "https://granitestatereport.com/2026/09/19/redact/")!, subscribers: true),
        Tool(name: "The Noncompliance List", blurb: "Which public bodies meet their RSA 91-A duties, and which do not.",
             url: URL(string: "https://granitestatereport.com/noncompliance-list/")!, subscribers: false),
        Tool(name: "Granite State Record Room", blurb: "The catalog of every document GSR holds, with the source named on each.",
             url: URL(string: "https://granitestatereport.com/2026/09/17/record-room/")!, subscribers: true),
        Tool(name: "Granite State Archive", blurb: "Every public record, statute and cited report behind this newsroom, free to download.",
             url: URL(string: "https://granitestatereport.com/archive/")!, subscribers: false),
        Tool(name: "NH Bill Tracker", blurb: "Every 2026 New Hampshire bill, where it stands, and the record behind it.",
             url: GSRContact.billTracker, subscribers: false),
    ]
}

struct StoryRow: View {
    let story: Story

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = story.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        GSRTheme.paper3
                    }
                }
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)
            }
            Text(story.title)
                .font(GSRTheme.serif(.title3, bold: true))
                .foregroundStyle(GSRTheme.navy)
            if story.published.timeIntervalSince1970 > 0 {
                Text(story.published, format: .dateTime.month(.wide).day().year())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GSRTheme.ink3)
            }
            if !story.excerpt.isEmpty {
                Text(story.excerpt)
                    .font(GSRTheme.serif(.subheadline))
                    .foregroundStyle(GSRTheme.ink)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the story")
    }
}
