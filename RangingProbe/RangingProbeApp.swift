import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 若是被區域事件從背景喚醒，launchOptions 會帶 .location
        Logger.shared.log("app_launch", ["by_location_event": launchOptions?[.location] != nil])
        _ = BeaconProbe.shared
        return true
    }
}

@main
struct RangingProbeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(BeaconProbe.shared)
        }
    }
}
