from __future__ import annotations

import queue
import tkinter as tk
from tkinter import messagebox, ttk

from plot_widgets import TripleTraceCanvas
from runtime_monitor_session import RuntimeMonitorSession, list_serial_ports
from runtime_serial_protocol import RuntimeSensorSample


class RuntimeMonitorGui:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Flex + POT Runtime Monitor")
        self.root.geometry("1040x760")
        self.root.minsize(900, 620)

        self.message_queue: queue.Queue = queue.Queue()
        self.session: RuntimeMonitorSession | None = None
        self.sample_count = 0

        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="115200")
        self.status_var = tk.StringVar(value="Idle")
        self.flex_raw_var = tk.StringVar(value="-")
        self.flex_angle_var = tk.StringVar(value="-")
        self.pot_raw_var = tk.StringVar(value="-")
        self.pot_angle_var = tk.StringVar(value="-")
        self.master_imu_var = tk.StringVar(value="-")
        self.slave_imu_var = tk.StringVar(value="-")
        self.imu_angle_var = tk.StringVar(value="-")
        self.sample_count_var = tk.StringVar(value="0")

        self._build_ui()
        self.refresh_ports()
        self.root.after(100, self._poll_queue)

    def _build_ui(self):
        main = ttk.Frame(self.root, padding=12)
        main.pack(fill="both", expand=True)

        connection = ttk.LabelFrame(main, text="Connection", padding=10)
        connection.pack(fill="x")

        ttk.Label(connection, text="Port").grid(row=0, column=0, sticky="w")
        self.port_combo = ttk.Combobox(connection, textvariable=self.port_var, width=18, state="readonly")
        self.port_combo.grid(row=0, column=1, sticky="w", padx=(6, 10))
        ttk.Button(connection, text="Refresh Ports", command=self.refresh_ports).grid(row=0, column=2, sticky="w")

        ttk.Label(connection, text="Baud").grid(row=0, column=3, sticky="w", padx=(20, 0))
        ttk.Entry(connection, textvariable=self.baud_var, width=10).grid(row=0, column=4, sticky="w", padx=(6, 10))

        ttk.Button(connection, text="Start Monitor", command=self.start_monitor).grid(row=0, column=5, sticky="we", padx=(10, 10))
        ttk.Button(connection, text="Stop Monitor", command=self.stop_monitor).grid(row=0, column=6, sticky="we")

        live = ttk.LabelFrame(main, text="Live Readings", padding=10)
        live.pack(fill="x", pady=(12, 0))
        self._add_reading_row(live, 0, "Status", self.status_var)
        self._add_reading_row(live, 1, "Flex Raw ADC", self.flex_raw_var)
        self._add_reading_row(live, 2, "Flex Angle", self.flex_angle_var)
        self._add_reading_row(live, 3, "POT Raw ADC", self.pot_raw_var)
        self._add_reading_row(live, 4, "POT Angle", self.pot_angle_var)
        self._add_reading_row(live, 5, "Master IMU", self.master_imu_var)
        self._add_reading_row(live, 6, "Slave IMU", self.slave_imu_var)
        self._add_reading_row(live, 7, "IMU Knee Angle", self.imu_angle_var)
        self._add_reading_row(live, 8, "Samples Received", self.sample_count_var)

        graph = ttk.LabelFrame(main, text="Converted Angle Graph", padding=10)
        graph.pack(fill="both", expand=True, pady=(12, 0))
        self.trace_canvas = TripleTraceCanvas(
            graph,
            y_min=0.0,
            y_max=145.0,
            trace_a_name="Flex Angle",
            trace_b_name="POT Angle",
            trace_c_name="IMU Angle",
        )
        self.trace_canvas.pack(fill="both", expand=True)

        logs = ttk.LabelFrame(main, text="Serial Log", padding=10)
        logs.pack(fill="both", expand=True, pady=(12, 0))
        self.log_text = tk.Text(logs, height=10, wrap="word")
        self.log_text.pack(fill="both", expand=True)

    def _add_reading_row(self, parent, row: int, label: str, value_var: tk.StringVar):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="nw", padx=(0, 12), pady=3)
        ttk.Label(parent, textvariable=value_var).grid(row=row, column=1, sticky="nw", pady=3)

    def refresh_ports(self):
        ports = list_serial_ports()
        self.port_combo["values"] = ports
        if ports and not self.port_var.get():
            self.port_var.set(ports[0])
        self._append_log(f"Detected ports: {', '.join(ports) if ports else 'none'}")

    def start_monitor(self):
        if self.session is not None:
            messagebox.showinfo("Monitor Active", "A live monitor session is already running.")
            return
        if not self.port_var.get():
            messagebox.showerror("Missing Port", "Select a serial port first.")
            return

        try:
            baud = int(self.baud_var.get())
        except ValueError:
            messagebox.showerror("Invalid Baud", "Baud rate must be an integer.")
            return

        self.sample_count = 0
        self.sample_count_var.set("0")
        self.trace_canvas.clear()

        self.session = RuntimeMonitorSession(self.port_var.get(), baud)
        self.session.add_sample_callback(lambda sample: self.message_queue.put(("sample", sample)))
        self.session.add_log_callback(lambda line: self.message_queue.put(("log", line)))
        self.session.add_status_callback(lambda status: self.message_queue.put(("status", status)))

        try:
            self.session.start()
        except Exception as exc:
            self.session = None
            messagebox.showerror("Connection Error", str(exc))
            return

        self.status_var.set("Connected")
        self._append_log("Runtime monitor started.")

    def stop_monitor(self):
        if self.session is None:
            return

        session = self.session
        self.session = None
        session.stop()
        self.status_var.set("Stopped")
        self._append_log("Runtime monitor stopped.")

    def _poll_queue(self):
        while True:
            try:
                kind, payload = self.message_queue.get_nowait()
            except queue.Empty:
                break

            if kind == "sample":
                self._handle_sample(payload)
            elif kind == "log":
                self._append_log(payload)
            elif kind == "status":
                self.status_var.set(payload.title())

        self.root.after(100, self._poll_queue)

    def _handle_sample(self, sample: RuntimeSensorSample):
        self.flex_raw_var.set(str(sample.flex_raw_adc))
        self.flex_angle_var.set(f"{sample.flex_angle_deg:.2f} deg")
        self.pot_raw_var.set(str(sample.pot_raw_adc))
        self.pot_angle_var.set(f"{sample.pot_angle_deg:.2f} deg")
        self.master_imu_var.set("-" if sample.master_imu_deg is None else f"{sample.master_imu_deg:.2f} deg")
        self.slave_imu_var.set("-" if sample.slave_imu_deg is None else f"{sample.slave_imu_deg:.2f} deg")
        self.imu_angle_var.set("-" if sample.imu_angle_deg is None else f"{sample.imu_angle_deg:.2f} deg")
        self.sample_count += 1
        self.sample_count_var.set(str(self.sample_count))
        self.trace_canvas.add_sample(sample.flex_angle_deg, sample.pot_angle_deg, sample.imu_angle_deg or 0.0)

    def _append_log(self, text: str):
        self.log_text.insert("end", text + "\n")
        self.log_text.see("end")


def main():
    root = tk.Tk()
    RuntimeMonitorGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
