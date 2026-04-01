from __future__ import annotations

import threading
import time
from pathlib import Path
from typing import Callable

import serial
import serial.tools.list_ports

from serial_protocol import LabelEvent, PotSample, parse_serial_line
from runtime_serial_protocol import parse_runtime_line
from session_writer import CsvSessionWriter, make_session_dir


MessageCallback = Callable[[PotSample | LabelEvent], None]
LogCallback = Callable[[str], None]
StatusCallback = Callable[[str], None]


def list_serial_ports() -> list[str]:
    return [port.device for port in serial.tools.list_ports.comports()]


class PotSerialSession:
    def __init__(self, port: str, baud: int, base_output_dir: str | Path):
        self.port = port
        self.baud = baud
        self.base_output_dir = Path(base_output_dir)

        self.serial_port: serial.Serial | None = None
        self.session_dir: Path | None = None
        self.writer: CsvSessionWriter | None = None

        self._stop_event = threading.Event()
        self._reader_thread: threading.Thread | None = None

        self._message_callbacks: list[MessageCallback] = []
        self._log_callbacks: list[LogCallback] = []
        self._status_callbacks: list[StatusCallback] = []

    def add_message_callback(self, callback: MessageCallback):
        self._message_callbacks.append(callback)

    def add_log_callback(self, callback: LogCallback):
        self._log_callbacks.append(callback)

    def add_status_callback(self, callback: StatusCallback):
        self._status_callbacks.append(callback)

    def start(self):
        self.session_dir = make_session_dir(self.base_output_dir)
        self.writer = CsvSessionWriter(self.session_dir)
        self.serial_port = serial.Serial(self.port, baudrate=self.baud, timeout=0.2)
        time.sleep(2.0)

        self._stop_event.clear()
        self._reader_thread = threading.Thread(target=self._reader_loop, daemon=True)
        self._reader_thread.start()

        self._emit_status("connected")
        self._emit_log(f"[session] logging to {self.session_dir}")

    def stop(self):
        self._stop_event.set()
        if self._reader_thread is not None:
            self._reader_thread.join(timeout=2.0)
        if self.writer is not None:
            self.writer.close()
        if self.serial_port is not None and self.serial_port.is_open:
            self.serial_port.close()
        self._emit_status("stopped")

    def send_command(self, command: str):
        if self.serial_port is None or not self.serial_port.is_open:
            raise RuntimeError("Serial session is not active.")
        self.serial_port.write((command.strip() + "\n").encode("utf-8"))

    def _reader_loop(self):
        assert self.serial_port is not None
        assert self.writer is not None

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

            self.writer.write_raw_line(line)
            parsed = parse_serial_line(line)
            if parsed is not None:
                self.writer.write_message(parsed)
                self._emit_message(parsed)
            elif parse_runtime_line(line) is not None or line.startswith("FLEX_SAMPLE,") or line.startswith("IMU_SAMPLE,"):
                continue
            else:
                self._emit_log(line)

    def _emit_message(self, message: PotSample | LabelEvent):
        for callback in self._message_callbacks:
            callback(message)

    def _emit_log(self, line: str):
        for callback in self._log_callbacks:
            callback(line)

    def _emit_status(self, status: str):
        for callback in self._status_callbacks:
            callback(status)
