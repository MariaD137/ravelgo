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
        GMSServices.provideAPIKey("AIzaSyCgU5ni3lgFTdw77-q2uGQuc6P4Cunv1_U")
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
