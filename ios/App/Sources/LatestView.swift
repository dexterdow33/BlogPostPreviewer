import GSRKit
import GSRUI
import SwiftUI

/// The newest stories from granitestatereport.com, opened in the app's browser sheet.
struct LatestView: View {
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
                    Button { page = WebPage(story.link) } label: { StoryRow(story: story) }
                        .buttonStyle(.plain)
                        .listRowBackground(GSRTheme.paper2)
                        .listRowSeparatorTint(GSRTheme.rule2)
                }
                if !stories.isEmpty {
                    Section {
                        Button { page = WebPage(GSRContact.billTracker) } label: {
                            Label("NH Bill Tracker: every bill and where it stands", systemImage: "list.bullet.rectangle")
                        }
                        Button { page = WebPage(GSRContact.site) } label: {
                            Label("Everything on granitestatereport.com", systemImage: "safari")
                        }
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
        do {
            stories = try await FeedClient().latest(count: 20)
            error = nil
        } catch {
            self.error = "The latest stories did not load. Pull down to try again."
        }
    }
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
