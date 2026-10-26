import SwiftUI

struct ContentView: View {
    @EnvironmentObject var probe: BeaconProbe
    @State private var condition = UserDefaults.standard.string(forKey: "condition") ?? ""
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("實驗條件") {
                    TextField("條件標籤，例如 C3-B-1", text: $condition)
                        .autocorrectionDisabled()
                        .onChange(of: condition) { value in
                            UserDefaults.standard.set(value, forKey: "condition")
                            Logger.shared.conditionLabel = value
                            Logger.shared.log("condition_set", ["label": value])
                        }
                    Toggle("背景定位（模式 B）", isOn: $probe.bgLocation)
                }
                Section("狀態") {
                    Text(probe.status)
                    Text("有效 ranging：\(probe.rangeCount) 筆")
                    Text(probe.lastBeacon).font(.footnote.monospaced())
                }
                Section {
                    if probe.running {
                        Button("停止", role: .destructive) { probe.stop() }
                    } else {
                        Button("開始") { probe.start() }
                    }
                    ShareLink("匯出日誌", item: Logger.shared.fileURL)
                    Button("清除日誌", role: .destructive) { confirmClear = true }
                }
            }
            .navigationTitle("Ranging Probe")
            .confirmationDialog("確定清除所有日誌？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除", role: .destructive) { Logger.shared.clear() }
            }
        }
    }
}
