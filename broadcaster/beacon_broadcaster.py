"""
Windows 筆電當主持人：廣播 iBeacon，每 30 秒輪替一次 Major/Minor（nonce）。

需求：Windows 10 以上、支援 BLE peripheral 角色的藍牙晶片、Python 3.9+
安裝：pip install winsdk
執行：python beacon_broadcaster.py
進出測試（C6）：在視窗輸入 l 按 Enter 標記「離開」，輸入 r 按 Enter 標記「回來」
"""
import asyncio
import csv
import hashlib
import hmac
import struct
import sys
import threading
import time
import uuid
from datetime import datetime, timezone

from winsdk.windows.devices.bluetooth import BluetoothAdapter
from winsdk.windows.devices.bluetooth.advertisement import (
    BluetoothLEAdvertisementPublisher,
    BluetoothLEManufacturerData,
)
from winsdk.windows.storage.streams import DataWriter

BEACON_UUID = uuid.UUID("8F3B1C2A-6D4E-4F7A-9B2C-3E1D5A7F9C10")  # 必須和 App 相同
WINDOW_SEC = 30
TX_POWER = -59                      # 1 公尺處的參考 RSSI，只是校正值
KEY = b"experiment-only-key"        # 實驗用；正式系統的密鑰只放在伺服器
APPLE_COMPANY_ID = 0x004C


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def nonce(window: int) -> tuple:
    mac = hmac.new(KEY, struct.pack(">Q", window), hashlib.sha256).digest()
    return int.from_bytes(mac[0:2], "big"), int.from_bytes(mac[2:4], "big")


def make_publisher(major: int, minor: int) -> BluetoothLEAdvertisementPublisher:
    payload = b"\x02\x15" + BEACON_UUID.bytes + struct.pack(">HHb", major, minor, TX_POWER)
    writer = DataWriter()
    writer.write_bytes(payload)
    md = BluetoothLEManufacturerData()
    md.company_id = APPLE_COMPANY_ID
    md.data = writer.detach_buffer()
    pub = BluetoothLEAdvertisementPublisher()
    pub.advertisement.manufacturer_data.append(md)
    return pub


def marker_thread(path: str) -> None:
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        while True:
            key = sys.stdin.readline().strip().lower()
            label = {"l": "left", "r": "returned"}.get(key)
            if label:
                w.writerow([now_iso(), label])
                f.flush()
                print(f"  [標記] {label}")


async def main() -> None:
    adapter = await BluetoothAdapter.get_default_async()
    if adapter is None:
        sys.exit("找不到藍牙介面卡")
    if not adapter.is_peripheral_role_supported:
        sys.exit("這台電腦的藍牙不支援廣播（peripheral 角色），請改用 Android 手機 + nRF Connect")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    nonce_log = f"nonces-{stamp}.csv"
    threading.Thread(target=marker_thread, args=(f"markers-{stamp}.csv",), daemon=True).start()

    with open(nonce_log, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ts", "window", "major", "minor"])
        pub = None
        last = None
        print(f"開始廣播 UUID {BEACON_UUID}，nonce 紀錄：{nonce_log}")
        try:
            while True:
                window = int(time.time() // WINDOW_SEC)
                if window != last:
                    if pub is not None:
                        pub.stop()
                    major, minor = nonce(window)
                    pub = make_publisher(major, minor)
                    pub.start()
                    w.writerow([now_iso(), window, major, minor])
                    f.flush()
                    print(f"{now_iso()}  window={window}  major={major}  minor={minor}  status={pub.status}")
                    last = window
                await asyncio.sleep(0.5)
        finally:
            if pub is not None:
                pub.stop()


if __name__ == "__main__":
    asyncio.run(main())
