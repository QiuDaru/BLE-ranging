# RangingProbe — iOS 背景 ranging 實驗

驗證問題：iPhone 鎖定畫面時，能不能持續讀到主持人廣播的 iBeacon nonce？
模式 A＝只用區域監聽；模式 B＝再加上低精度背景定位。

```
RangingProbe/        Swift 實驗 App
broadcaster/         Windows 筆電廣播程式（Python）
project.yml          XcodeGen 設定（雲端產生 Xcode 專案）
.github/workflows/   GitHub Actions：雲端編譯出未簽章 .ipa
```

## 1. 雲端編譯（不需要 Mac）

1. 在 GitHub 建立一個**公開**的 repo，把整個資料夾上傳（網頁上傳或 GitHub Desktop 都可以）。
   注意 `.github` 是隱藏資料夾，要確認有一起上傳。
2. 上傳後 Actions 會自動執行；也可以到 Actions → build-ipa → Run workflow 手動觸發。
3. 完成後在該次執行的頁面下方 Artifacts 下載 `RangingProbe-ipa`，解壓縮得到 `RangingProbe.ipa`。
4. 編譯失敗時，把 Actions 的錯誤訊息貼給 Claude 修正（這份程式碼沒有在 Mac 上編譯過）。

## 2. 安裝到 iPhone（Windows + 免費 Apple ID）

1. 安裝 Sideloadly，以及 **Apple 官網版**（非 Microsoft Store 版）的 iTunes 和 iCloud。
2. iPhone 用 USB 接電腦，在手機上按「信任這部電腦」。
3. 把 `.ipa` 拖進 Sideloadly，輸入 Apple ID 後按 Start。
   建議使用**另外申請的 Apple ID**，不要用主要帳號。
4. iPhone 上：
   - 設定 → 隱私權與安全性 → 開啟「開發者模式」（手機會重新開機）
   - 設定 → 一般 → VPN 與裝置管理 → 信任你的 Apple ID
5. 免費 Apple ID 簽章 7 天後失效，到期重新用 Sideloadly 安裝即可（日誌會保留在手機上，但建議先匯出）。

## 3. App 權限（很重要）

設定 → RangingProbe → 位置：
- 允許位置取用：**永遠**
- **精確位置：開啟**（關閉時 iOS 不允許 Beacon ranging）

## 4. Windows 廣播端

```
pip install winsdk
python broadcaster/beacon_broadcaster.py
```

- 若顯示「不支援廣播」，代表筆電藍牙不支援 peripheral 角色，改借 Android 手機用 nRF Connect 廣播（無法測輪替）。
- Windows 是否允許廣播 Apple 公司代碼（0x004C）的封包，需要實測。若 iPhone 完全收不到，先回報這一點。
- 筆電要接電源，並把電源設定改成「永不睡眠」。
- 程式會產生 `nonces-*.csv`（每個時間窗的 nonce）與 `markers-*.csv`（C6 進出標記）。

## 5. 第一次測試（C1）

1. 筆電執行廣播程式。
2. App 輸入條件標籤 `C1-A-1`，按「開始」。
3. 畫面上的 major／minor 應該和筆電視窗顯示的值一致，並每 30 秒更新。
4. 一致就代表整條路通了，可以開始 C2～C6。

## 6. 匯出日誌

App →「匯出日誌」→ 用 LINE 傳給自己、存到 iCloud Drive 或寄 email，再下載到電腦。
日誌為 `probe-log.jsonl`，每行一個事件，搭配 `nonces-*.csv` 做分析。

## 日誌事件說明

| event | 意義 |
|---|---|
| app_launch | App 啟動；`by_location_event=true` 代表被區域事件從背景喚醒 |
| start / stop | 實驗開始／停止 |
| auth | 權限狀態；`precise=false` 時無法 ranging |
| region_state / region_enter / region_exit | 區域狀態與進出事件 |
| range | 一筆有效 ranging：major、minor、rssi |
| range_empty | 有回呼但沒有有效 Beacon |
| loc_tick | 收到背景定位更新（不記錄座標） |
| app_background / app_foreground / app_terminate | App 生命週期 |
| device_locked / device_unlocked | 鎖定／解鎖（需設有密碼） |
| power_state_change | 低電量模式切換 |
| condition_set | 變更條件標籤 |
