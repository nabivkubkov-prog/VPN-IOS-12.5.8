import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = HomeController()
        window.tintColor = Theme.accent
        window.makeKeyAndVisible(); self.window = window
        return true
    }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        do {
            let profiles = try ProfileParser.parseBatch(url.absoluteString)
            try ProfileStore.shared.add(profiles)
            return true
        } catch {
            (window?.rootViewController as? HomeController)?.showError(error.localizedDescription)
            return false
        }
    }
}

