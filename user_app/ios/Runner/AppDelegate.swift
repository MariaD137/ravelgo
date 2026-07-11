import UIKit
import Flutter
import GoogleMaps   // 👈 Add this import


@main
@objc class AppDelegate: FlutterAppDelegate {
    lazy var flutterEngine = FlutterEngine(name: "my_engine")

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
            GMSServices.provideAPIKey(apiKey)
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
