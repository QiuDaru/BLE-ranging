import Foundation
import UIKit

/// 把每個事件寫成一行 JSON（JSONL），存在 App 的 Documents 資料夾。
final class Logger {
    static let shared = Logger()

    let fileURL: URL
    var conditionLabel: String = UserDefaults.standard.string(forKey: "condition") ?? ""

    private let queue = DispatchQueue(label: "probe.logger")
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("probe-log.jsonl")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // 不加檔案保護，鎖定畫面時也能寫入
            FileManager.default.createFile(atPath: fileURL.path, contents: nil,
                                           attributes: [.protectionKey: FileProtectionType.none])
        }
    }

    /// 請在主執行緒呼叫（CLLocationManager 的回呼本來就在主執行緒）
    func log(_ event: String, _ fields: [String: Any] = [:]) {
        var rec = fields
        rec["ts"] = iso.string(from: Date())
        rec["event"] = event
        rec["cond"] = conditionLabel
        rec["app_state"] = Logger.appState()
        rec["battery"] = Double(UIDevice.current.batteryLevel)
        rec["low_power"] = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let data = try? JSONSerialization.data(withJSONObject: rec, options: [.sortedKeys]) else { return }
        let url = fileURL
        queue.async {
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            h.write(data)
            h.write(Data([0x0A]))
        }
    }

    func clear() {
        let url = fileURL
        queue.async { try? Data().write(to: url) }
        log("log_cleared")
    }

    static func appState() -> String {
        let read: () -> String = {
            switch UIApplication.shared.applicationState {
            case .active: return "active"
            case .inactive: return "inactive"
            case .background: return "background"
            @unknown default: return "unknown"
            }
        }
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
    }
}
