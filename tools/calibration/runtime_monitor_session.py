from __future__ import annotations

import threading
import time
from typing import Callable

import serial
import serial.tools.list_ports

from runtime_serial_protocol import RuntimeSensorSample, parse_runtime_line


SampleCallback = Callable[[RuntimeSensorSample], None]
LogCallback = Callable[[str], None]
StatusCallback = Callable[[str], None]


def list_serial_ports() -> list[str]:
    return [port.device for port in serial.tools.list_ports.comports()]


class RuntimeMonitorSession:
    def __init__(self, port: str, baud: int):
        self.port = port
        self.baud = baud
        self.serial_port: serial.Serial | None = None

        self._stop_event = threading.Event()
        self._reader_thread: threading.Thread | None = None

        self._sample_callbacks: list[SampleCallback] = []
        self._log_callbacks: list[LogCallback] = []
        self._status_callbacks: list[StatusCallback] = []

    def add_sample_callback(self, callback: SampleCallback):
        self._sample_callbacks.append(callback)

    def add_log_callback(self, callback: LogCallback):
        self._log_callbacks.append(callback)

    def add_status_callback(self, callback: StatusCallback):
        self._status_callbacks.append(callback)

    def start(self):
        self.serial_port = serial.Serial(self.port, baudrate=self.baud, timeout=0.2)
        time.sleep(2.0)

        self._stop_event.clear()
        self._reader_thread = threading.Thread(target=self._reader_loop, daemon=True)
        self._reader_thread.start()

        self._emit_status("connected")
        self._emit_log(f"[runtime] connected to {self.port} @ {self.baud}")

    def stop(self):
        self._stop_event.set()
        if self._reader_thread is not None:
            self._reader_thread.join(timeout=2.0)
        if self.serial_port is not None and self.serial_port.is_open:
            self.serial_port.close()
        self._emit_status("stopped")

    def _reader_loop(self):
        assert self.serial_port is not None

        while not self._stop_event.is_set():
            try:
                raw = self.serial_port.readline()
            except serial.SerialException as exc:
                self._emit_log(f"[serial] read error: {exc}")
                self._emit_status("error")
                self._stop_event.set()
                return

            if not raw:
                continue

            line = raw.decode("utf-8", errors="ignore").strip()
            if not line:
                continue

            parsed = parse_runtime_line(line)
            if parsed is not None:
                self._emit_sample(parsed)
            elif line.startswith("FLEX_SAMPLE,") or line.startswith("POT_SAMPLE,") or line.startswith("IMU_SAMPLE,") or line.startswith("LABEL_START,") or line.startswith("LABEL_END,"):
                continue
            else:
                self._emit_log(line)

    def _emit_sample(self, sample: RuntimeSensorSample):
        for callback in self._sample_callbacks:
            callback(sample)

    def _emit_log(self, line: str):
        for callback in self._log_callbacks:
            callback(line)

    def _emit_status(self, status: str):
        for callback in self._status_callbacks:
            callback(status)
