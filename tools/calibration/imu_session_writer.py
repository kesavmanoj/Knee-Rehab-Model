from __future__ import annotations

import csv
import threading
import time
from datetime import datetime
from pathlib import Path

from imu_serial_protocol import ImuSample, LabelEvent


class ImuCsvSessionWriter:
    def __init__(self, output_dir: Path):
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.samples_path = self.output_dir / "imu_samples.csv"
        self.events_path = self.output_dir / "imu_label_events.csv"
        self.raw_log_path = self.output_dir / "serial_raw.log"

        self._samples_handle = self.samples_path.open("w", encoding="utf-8", newline="")
        self._events_handle = self.events_path.open("w", encoding="utf-8", newline="")
        self._raw_handle = self.raw_log_path.open("w", encoding="utf-8")

        self._samples_writer = csv.writer(self._samples_handle)
        self._events_writer = csv.writer(self._events_handle)
        self._samples_writer.writerow(
            [
                "host_iso_time",
                "host_time_s",
                "board_time_ms",
                "master_imu_deg",
                "slave_imu_deg",
                "imu_raw_knee_angle_deg",
                "imu_angle_deg",
                "label_deg",
            ]
        )
        self._events_writer.writerow(["host_iso_time", "host_time_s", "board_time_ms", "kind", "label_deg", "window_ms"])

        self._lock = threading.Lock()

    def close(self):
        self._samples_handle.close()
        self._events_handle.close()
        self._raw_handle.close()

    def write_raw_line(self, line: str):
        with self._lock:
            self._raw_handle.write(line + "\n")
            self._raw_handle.flush()

    def write_message(self, message: ImuSample | LabelEvent):
        host_iso = datetime.now().isoformat(timespec="milliseconds")
        host_time_s = time.time()

        with self._lock:
            if isinstance(message, ImuSample):
                self._samples_writer.writerow(
                    [
                        host_iso,
                        f"{host_time_s:.3f}",
                        message.time_ms,
                        f"{message.master_imu_deg:.2f}",
                        f"{message.slave_imu_deg:.2f}",
                        f"{message.imu_raw_knee_angle_deg:.2f}",
                        f"{message.imu_angle_deg:.2f}",
                        "" if message.label_deg is None else f"{message.label_deg:.1f}",
                    ]
                )
                self._samples_handle.flush()
            elif isinstance(message, LabelEvent):
                self._events_writer.writerow(
                    [
                        host_iso,
                        f"{host_time_s:.3f}",
                        message.time_ms,
                        message.kind,
                        f"{message.label_deg:.1f}",
                        "" if message.window_ms is None else message.window_ms,
                    ]
                )
                self._events_handle.flush()


def make_session_dir(base_dir: Path, session_prefix: str = "imu_session") -> Path:
    session_name = datetime.now().strftime(f"{session_prefix}_%Y%m%d_%H%M%S")
    return base_dir / session_name
