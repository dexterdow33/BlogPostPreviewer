import GSRKit
import GSRUI
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView(selection: $router.tab) {
            SendHomeView()
                .tabItem { Label("Send", systemImage: "paperplane") }
                .tag(AppRouter.Tab.send)
            LatestView()
                .tabItem { Label("Latest", systemImage: "newspaper") }
                .tag(AppRouter.Tab.latest)
            ContactView()
                .tabItem { Label("Contact", systemImage: "lock.shield") }
                .tag(AppRouter.Tab.contact)
        }
        // What a source was typing should not show in the app switcher.
        .overlay {
            if phase != .active { PrivacyCover() }
        }
        .onChange(of: phase) { _, p in
            if p == .active { app.refreshUnsent() }
        }
    }
}

/// Covers the screen whenever the app is not in front.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            GSRTheme.paper2.ignoresSafeArea()
            Masthead().padding(32)
        }
        .accessibilityHidden(true)
    }
}
