import CoreLocation
import UIKit

/// 實驗核心：監聽固定 UUID 的 Beacon 區域，進入後做 ranging，讀出 Major/Minor（nonce）與 RSSI。
/// 模式 A：只用區域監聽 + ranging（系統官方行為）
/// 模式 B：再加上低精度背景定位，讓 App 在背景持續存活
final class BeaconProbe: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BeaconProbe()
    /// 必須和 broadcaster/beacon_broadcaster.py 裡的 UUID 相同
    static let uuid = UUID(uuidString: "8F3B1C2A-6D4E-4F7A-9B2C-3E1D5A7F9C10")!

    private let manager = CLLocationManager()
    private let region: CLBeaconRegion
    private let constraint: CLBeaconIdentityConstraint

    @Published private(set) var running: Bool
    @Published var bgLocation: Bool {
        didSet {
            UserDefaults.standard.set(bgLocation, forKey: "bgLocation")
            if running { restart() }
        }
    }
    @Published private(set) var status = "尚未啟動"
    @Published private(set) var rangeCount = 0
    @Published private(set) var lastBeacon = "—"

    private override init() {
        constraint = CLBeaconIdentityConstraint(uuid: BeaconProbe.uuid)
        region = CLBeaconRegion(uuid: BeaconProbe.uuid, identifier: "probe")
        running = UserDefaults.standard.bool(forKey: "running")
        bgLocation = UserDefaults.standard.bool(forKey: "bgLocation")
        super.init()
        region.notifyOnEntry = true
        region.notifyOnExit = true
        region.notifyEntryStateOnDisplay = true
        manager.delegate = self
        UIDevice.current.isBatteryMonitoringEnabled = true
        observeLifecycle()
        // 被系統從背景喚醒時，自動恢復實驗
        if running { startInternal(reason: "resume") }
    }

    // MARK: - 控制

    func start() {
        running = true
        UserDefaults.standard.set(true, forKey: "running")
        manager.requestAlwaysAuthorization()
        startInternal(reason: "user")
    }

    func stop() {
        running = false
        UserDefaults.standard.set(false, forKey: "running")
        manager.stopRangingBeacons(satisfying: constraint)
        manager.stopMonitoring(for: region)
        stopBackgroundLocation()
        status = "已停止"
        Logger.shared.log("stop")
    }

    private func restart() {
        stopBackgroundLocation()
        startInternal(reason: "mode_change")
    }

    private func startInternal(reason: String) {
        Logger.shared.log("start", ["reason": reason, "bg_location": bgLocation])
        manager.startMonitoring(for: region)
        manager.requestState(for: region)
        if bgLocation {
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = kCLDistanceFilterNone
            manager.pausesLocationUpdatesAutomatically = false
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
        }
        status = bgLocation ? "執行中（模式 B）" : "執行中（模式 A）"
    }

    private func stopBackgroundLocation() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: - 權限

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s: String
        switch m.authorizationStatus {
        case .authorizedAlways: s = "always"
        case .authorizedWhenInUse: s = "when_in_use"
        case .denied: s = "denied"
        case .restricted: s = "restricted"
        case .notDetermined: s = "not_determined"
        @unknown default: s = "unknown"
        }
        let precise = m.accuracyAuthorization == .fullAccuracy
        Logger.shared.log("auth", ["status": s, "precise": precise])
        if !precise {
            status = "請在設定中開啟「精確位置」，否則無法 ranging"
        } else if running && s != "always" {
            status = "請在設定中把位置權限改為「永遠」"
        }
    }

    // MARK: - 區域事件

    func locationManager(_ m: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let s = state == .inside ? "inside" : (state == .outside ? "outside" : "unknown")
        Logger.shared.log("region_state", ["state": s])
        if state == .inside {
            m.startRangingBeacons(satisfying: constraint)
        } else if state == .outside {
            m.stopRangingBeacons(satisfying: constraint)
        }
    }

    func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        Logger.shared.log("region_enter")
    }

    func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        Logger.shared.log("region_exit")
    }

    func locationManager(_ m: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Logger.shared.log("monitor_fail", ["error": error.localizedDescription])
    }

    // MARK: - Ranging

    func locationManager(_ m: CLLocationManager, didRange beacons: [CLBeacon],
                         satisfying c: CLBeaconIdentityConstraint) {
        guard let b = beacons.first(where: { $0.rssi != 0 }) else {
            Logger.shared.log("range_empty", ["n": beacons.count])
            return
        }
        rangeCount += 1
        let major = b.major.intValue
        let minor = b.minor.intValue
        lastBeacon = "major \(major)  minor \(minor)  rssi \(b.rssi)"
        Logger.shared.log("range", ["major": major, "minor": minor, "rssi": b.rssi,
                                    "proximity": b.proximity.rawValue, "accuracy_m": b.accuracy])
    }

    func locationManager(_ m: CLLocationManager, didFailRangingFor c: CLBeaconIdentityConstraint, error: Error) {
        Logger.shared.log("range_fail", ["error": error.localizedDescription])
    }

    // MARK: - 背景定位（只記錄有收到，不記錄座標）

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Logger.shared.log("loc_tick")
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Logger.shared.log("loc_fail", ["error": error.localizedDescription])
    }

    // MARK: - App 生命週期

    private func observeLifecycle() {
        let events: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "app_background"),
            (UIApplication.willEnterForegroundNotification, "app_foreground"),
            (UIApplication.willTerminateNotification, "app_terminate"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "device_locked"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "device_unlocked"),
            (Notification.Name.NSProcessInfoPowerStateDidChange, "power_state_change"),
        ]
        for (name, event) in events {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Logger.shared.log(event)
            }
        }
    }
}
