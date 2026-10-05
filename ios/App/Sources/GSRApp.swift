import GSRKit
import GSRUI
import SwiftUI
import UIKit

@main
struct GSRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter.shared
    @StateObject private var app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(app)
                .preferredColorScheme(.light)
                .tint(GSRTheme.rust)
        }
    }
}

/// Hands Home Screen quick actions to the router, at launch and while running.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            AppRouter.shared.handleShortcut(item.type)
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(AppRouter.shared.handleShortcut(shortcutItem.type))
    }
}
