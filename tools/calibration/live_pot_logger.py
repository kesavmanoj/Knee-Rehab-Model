from __future__ import annotations

import argparse
import threading

from pot_serial_session import PotSerialSession, list_serial_ports
from serial_protocol import LabelEvent


def main():
    parser = argparse.ArgumentParser(description="Live potentiometer CSV logger and label sender.")
    parser.add_argument("--port", help="Serial port for the master node, for example COM6")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate")
    parser.add_argument("--output-dir", default="calibration_sessions", help="Directory where session CSV files will be stored")
    parser.add_argument("--list-ports", action="store_true", help="List detected serial ports and exit")
    args = parser.parse_args()

    if args.list_ports:
        for port in list_serial_ports():
            print(port)
        return
    if not args.port:
        parser.error("--port is required unless --list-ports is used")

    stop_event = threading.Event()
    session = PotSerialSession(args.port, args.baud, args.output_dir)
    session.add_log_callback(print)

    def on_message(message):
        if isinstance(message, LabelEvent):
            print(f"[board] label {message.kind}: {message.label_deg:.1f} deg")

    session.add_message_callback(on_message)

    session.start()
    print("Type angle labels 0..145 and press Enter. Type 'h' for board help. Type 'q' to quit.")
    print(f"[logger] session directory: {session.session_dir}")
    print(f"[logger] samples csv: {session.writer.samples_path}")
    print(f"[logger] events csv: {session.writer.events_path}")
    print(f"[logger] raw log: {session.writer.raw_log_path}")

    try:
        while not stop_event.is_set():
            user_input = input("> ").strip()
            if not user_input:
                continue
            if user_input.lower() in ("q", "quit", "exit"):
                stop_event.set()
                break
            session.send_command(user_input)
    finally:
        session.stop()
        print("[logger] closed.")


if __name__ == "__main__":
    main()
