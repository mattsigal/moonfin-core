import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
    private var appleTvVideoChannel: AppleTvVideoChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = flutterViewController
        window.makeKeyAndVisible()
        self.window = window

        GeneratedPluginRegistrant.register(with: self)

        appleTvVideoChannel = AppleTvVideoChannel(
            messenger: flutterViewController.binaryMessenger,
            rootViewController: flutterViewController)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
