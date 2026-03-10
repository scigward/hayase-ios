import UIKit
import CoreData


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Create window programmatically — WebViewController as the sole root.
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.overrideUserInterfaceStyle = .dark          // Hayase is `color-scheme: only dark`
        w.rootViewController = WebViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

