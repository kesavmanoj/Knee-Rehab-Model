from __future__ import annotations

import os
import queue
import tkinter as tk
from tkinter import messagebox, ttk

from flex_calibration_analysis import AnalysisResult, analyze_csv_logs
from flex_serial_protocol import FlexSample, LabelEvent
from flex_serial_session import FlexSerialSession, list_serial_ports
from plot_widgets import LiveTraceCanvas


PRESET_LABELS = [0, 15, 30, 45, 60, 75, 90, 105, 120, 135, 145]


class FlexCalibrationGui:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Flex Sensor Calibration Tool")
        self.root.geometry("1040x780")
        self.root.minsize(900, 640)

        self.message_queue: queue.Queue = queue.Queue()
        self.session: FlexSerialSession | None = None
        self.latest_sample: FlexSample | None = None
        self.current_label: float | None = None
        self.sample_count = 0
        self.analysis_result: AnalysisResult | None = None

        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="115200")
        self.output_dir_var = tk.StringVar(value="calibration_sessions")
        self.status_var = tk.StringVar(value="Idle")
        self.session_dir_var = tk.StringVar(value="-")
        self.raw_adc_var = tk.StringVar(value="-")
        self.filtered_adc_var = tk.StringVar(value="-")
        self.voltage_var = tk.StringVar(value="-")
        self.resistance_var = tk.StringVar(value="-")
        self.flex_angle_var = tk.StringVar(value="-")
        self.label_var = tk.StringVar(value="-")
        self.sample_count_var = tk.StringVar(value="0")
        self.mapping_adc_var = tk.StringVar(value="-")
        self.mapping_resistance_var = tk.StringVar(value="-")
        self.summary_var = tk.StringVar(value="No analysis yet.")
        self.custom_label_var = tk.StringVar()
        self.time_plot_path_var = tk.StringVar(value="-")
        self.fit_plot_path_var = tk.StringVar(value="-")

        self._build_ui()
        self.refresh_ports()
        self.root.after(100, self._poll_queue)

    def _build_ui(self):
        container = ttk.Frame(self.root)
        container.pack(fill="both", expand=True)

        self.scroll_canvas = tk.Canvas(container, highlightthickness=0)
        scrollbar = ttk.Scrollbar(container, orient="vertical", command=self.scroll_canvas.yview)
        self.scroll_canvas.configure(yscrollcommand=scrollbar.set)

        scrollbar.pack(side="right", fill="y")
        self.scroll_canvas.pack(side="left", fill="both", expand=True)

        main = ttk.Frame(self.scroll_canvas, padding=12)
        self.scroll_window = self.scroll_canvas.create_window((0, 0), window=main, anchor="nw")

        main.bind("<Configure>", self._on_main_frame_configure)
        self.scroll_canvas.bind("<Configure>", self._on_canvas_configure)
        self.scroll_canvas.bind_all("<MouseWheel>", self._on_mousewheel)

        connection = ttk.LabelFrame(main, text="Connection", padding=10)
        connection.pack(fill="x")

        ttk.Label(connection, text="Port").grid(row=0, column=0, sticky="w")
        self.port_combo = ttk.Combobox(connection, textvariable=self.port_var, width=18, state="readonly")
        self.port_combo.grid(row=0, column=1, sticky="w", padx=(6, 10))
        ttk.Button(connection, text="Refresh Ports", command=self.refresh_ports).grid(row=0, column=2, sticky="w")

        ttk.Label(connection, text="Baud").grid(row=0, column=3, sticky="w", padx=(20, 0))
        ttk.Entry(connection, textvariable=self.baud_var, width=10).grid(row=0, column=4, sticky="w", padx=(6, 10))

        ttk.Label(connection, text="Output Dir").grid(row=1, column=0, sticky="w", pady=(10, 0))
        ttk.Entry(connection, textvariable=self.output_dir_var, width=40).grid(row=1, column=1, columnspan=2, sticky="we", padx=(6, 10), pady=(10, 0))

        ttk.Button(connection, text="Start Session", command=self.start_session).grid(row=1, column=3, sticky="we", padx=(0, 10), pady=(10, 0))
        ttk.Button(connection, text="Stop + Analyze", command=self.stop_and_analyze).grid(row=1, column=4, sticky="we", pady=(10, 0))

        status = ttk.LabelFrame(main, text="Live Flex Sensor Reading", padding=10)
        status.pack(fill="x", pady=(12, 0))

        self._add_reading_row(status, 0, "Status", self.status_var)
        self._add_reading_row(status, 1, "Session Dir", self.session_dir_var)
        self._add_reading_row(status, 2, "Raw ADC", self.raw_adc_var)
        self._add_reading_row(status, 3, "Filtered ADC", self.filtered_adc_var)
        self._add_reading_row(status, 4, "Voltage", self.voltage_var)
        self._add_reading_row(status, 5, "Resistance", self.resistance_var)
        self._add_reading_row(status, 6, "Mapped Flex Angle", self.flex_angle_var)
        self._add_reading_row(status, 7, "Active Label", self.label_var)
        self._add_reading_row(status, 8, "Samples Logged", self.sample_count_var)

        plot_frame = ttk.LabelFrame(main, text="Live Flex Trace (D0)", padding=10)
        plot_frame.pack(fill="x", pady=(12, 0))
        self.trace_canvas = LiveTraceCanvas(plot_frame)
        self.trace_canvas.pack(fill="x", expand=True)

        labels = ttk.LabelFrame(main, text="Label Capture", padding=10)
        labels.pack(fill="x", pady=(12, 0))

        presets_frame = ttk.Frame(labels)
        presets_frame.pack(fill="x")
        for index, label in enumerate(PRESET_LABELS):
            ttk.Button(
                presets_frame,
                text=str(label),
                command=lambda value=label: self.send_label(value),
                width=6,
            ).grid(row=index // 6, column=index % 6, padx=4, pady=4, sticky="w")

        custom_frame = ttk.Frame(labels)
        custom_frame.pack(fill="x", pady=(10, 0))
        ttk.Label(custom_frame, text="Custom Angle").pack(side="left")
        ttk.Entry(custom_frame, textvariable=self.custom_label_var, width=10).pack(side="left", padx=(8, 8))
        ttk.Button(custom_frame, text="Send Label", command=self.send_custom_label).pack(side="left")
        ttk.Button(custom_frame, text="Board Help", command=lambda: self._send_command("h")).pack(side="left", padx=(12, 0))

        analysis = ttk.LabelFrame(main, text="Analysis", padding=10)
        analysis.pack(fill="x", pady=(12, 0))
        self._add_reading_row(analysis, 0, "ADC Mapping", self.mapping_adc_var)
        self._add_reading_row(analysis, 1, "Resistance Mapping", self.mapping_resistance_var)
        self._add_reading_row(analysis, 2, "Summary", self.summary_var)

        generated = ttk.LabelFrame(main, text="Generated Files", padding=10)
        generated.pack(fill="x", pady=(12, 0))
        self._add_reading_row(generated, 0, "Time Plot", self.time_plot_path_var)
        self._add_reading_row(generated, 1, "Fit Plot", self.fit_plot_path_var)

        buttons = ttk.Frame(generated)
        buttons.grid(row=2, column=0, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Button(buttons, text="Open Session Folder", command=self.open_session_folder).pack(side="left")
        ttk.Button(buttons, text="Open Time Plot", command=self.open_time_plot).pack(side="left", padx=(8, 0))
        ttk.Button(buttons, text="Open Fit Plot", command=self.open_fit_plot).pack(side="left", padx=(8, 0))

        logs = ttk.LabelFrame(main, text="Event Log", padding=10)
        logs.pack(fill="both", expand=True, pady=(12, 0))
        self.log_text = tk.Text(logs, height=16, wrap="word")
        self.log_text.pack(fill="both", expand=True)

    def _add_reading_row(self, parent, row: int, label: str, value_var: tk.StringVar):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="nw", padx=(0, 12), pady=3)
        ttk.Label(parent, textvariable=value_var).grid(row=row, column=1, sticky="nw", pady=3)

    def _on_main_frame_configure(self, _event=None):
        self.scroll_canvas.configure(scrollregion=self.scroll_canvas.bbox("all"))

    def _on_canvas_configure(self, event):
        self.scroll_canvas.itemconfigure(self.scroll_window, width=event.width)

    def _on_mousewheel(self, event):
        if self.scroll_canvas.winfo_exists():
            self.scroll_canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")

    def refresh_ports(self):
        ports = list_serial_ports()
        self.port_combo["values"] = ports
        if ports and not self.port_var.get():
            self.port_var.set(ports[0])
        self._append_log(f"Detected ports: {', '.join(ports) if ports else 'none'}")

    def start_session(self):
        if self.session is not None:
            messagebox.showinfo("Session Active", "A session is already running.")
            return
        if not self.port_var.get():
            messagebox.showerror("Missing Port", "Select a serial port first.")
            return

        try:
            baud = int(self.baud_var.get())
        except ValueError:
            messagebox.showerror("Invalid Baud", "Baud rate must be an integer.")
            return

        self.analysis_result = None
        self.mapping_adc_var.set("-")
        self.mapping_resistance_var.set("-")
        self.summary_var.set("Session running.")
        self.time_plot_path_var.set("-")
        self.fit_plot_path_var.set("-")
        self.sample_count = 0
        self.sample_count_var.set("0")
        self.current_label = None
        self.label_var.set("-")
        self.trace_canvas.clear()

        self.session = FlexSerialSession(self.port_var.get(), baud, self.output_dir_var.get())
        self.session.add_message_callback(lambda message: self.message_queue.put(("message", message)))
        self.session.add_log_callback(lambda line: self.message_queue.put(("log", line)))
        self.session.add_status_callback(lambda status: self.message_queue.put(("status", status)))

        try:
            self.session.start()
        except Exception as exc:
            self.session = None
            messagebox.showerror("Connection Error", str(exc))
            return

        self.status_var.set("Connected")
        self.session_dir_var.set(str(self.session.session_dir))
        self._append_log(f"Session started: {self.session.session_dir}")

    def stop_and_analyze(self):
        if self.session is None:
            messagebox.showinfo("No Session", "Start a session first.")
            return

        session = self.session
        self.session = None
        session.stop()
        self.status_var.set("Stopped")
        self._append_log("Session stopped. Running analysis...")

        try:
            assert session.writer is not None
            result = analyze_csv_logs(session.writer.samples_path, session.writer.events_path, session.session_dir)
        except Exception as exc:
            self._append_log(f"Analysis failed: {exc}")
            messagebox.showerror("Analysis Failed", str(exc))
            return

        self.analysis_result = result
        self.mapping_adc_var.set(
            f"knee_angle_deg = ({result.adc_mapping.slope:.8f} * filtered_adc) + ({result.adc_mapping.intercept:.8f})"
        )
        self.mapping_resistance_var.set(
            f"knee_angle_deg = ({result.resistance_mapping.slope:.8f} * resistance_ohms) + ({result.resistance_mapping.intercept:.8f})"
        )
        self.summary_var.set(f"{len(result.label_summary)} labeled angle groups analyzed.")
        self.time_plot_path_var.set(str(result.time_plot_path))
        self.fit_plot_path_var.set(str(result.calibration_plot_path))
        self._append_log(f"Analysis complete. Summary: {result.summary_text_path}")
        messagebox.showinfo(
            "Analysis Complete",
            "Graphs generated successfully.\nUse 'Open Time Plot' and 'Open Fit Plot' in the Generated Files section.",
        )

    def send_label(self, value: int | float):
        self._send_command(str(value))

    def send_custom_label(self):
        label_text = self.custom_label_var.get().strip()
        if not label_text:
            return
        self._send_command(label_text)

    def _send_command(self, command: str):
        if self.session is None:
            messagebox.showinfo("No Session", "Start a session first.")
            return
        try:
            self.session.send_command(command)
            self._append_log(f"Sent command: {command}")
        except Exception as exc:
            messagebox.showerror("Send Failed", str(exc))

    def _poll_queue(self):
        while True:
            try:
                kind, payload = self.message_queue.get_nowait()
            except queue.Empty:
                break

            if kind == "message":
                self._handle_message(payload)
            elif kind == "log":
                self._append_log(payload)
            elif kind == "status":
                self.status_var.set(payload.title())

        self.root.after(100, self._poll_queue)

    def _handle_message(self, message: FlexSample | LabelEvent):
        if isinstance(message, FlexSample):
            self.latest_sample = message
            self.raw_adc_var.set(str(message.raw_adc))
            self.filtered_adc_var.set(f"{message.filtered_adc:.2f}")
            self.voltage_var.set(f"{message.voltage:.4f} V")
            self.resistance_var.set("-" if message.resistance_ohms is None else f"{message.resistance_ohms:.2f} ohm")
            self.flex_angle_var.set(f"{message.flex_angle_deg:.2f} deg")
            self.current_label = message.label_deg
            self.label_var.set("-" if message.label_deg is None else f"{message.label_deg:.1f} deg")
            self.sample_count += 1
            self.sample_count_var.set(str(self.sample_count))
            self.trace_canvas.add_sample(message.filtered_adc)
        elif isinstance(message, LabelEvent):
            if message.kind == "start":
                self.current_label = message.label_deg
                self.label_var.set(f"{message.label_deg:.1f} deg")
                self.trace_canvas.start_label(message.label_deg)
            elif message.kind == "end":
                self.current_label = None
                self.label_var.set("-")
                self.trace_canvas.end_label()
            self._append_log(f"Board label {message.kind}: {message.label_deg:.1f} deg")

    def _append_log(self, text: str):
        self.log_text.insert("end", text + "\n")
        self.log_text.see("end")

    def open_session_folder(self):
        if self.session_dir_var.get() and self.session_dir_var.get() != "-":
            os.startfile(self.session_dir_var.get())

    def open_time_plot(self):
        if self.analysis_result is not None:
            os.startfile(self.analysis_result.time_plot_path)

    def open_fit_plot(self):
        if self.analysis_result is not None:
            os.startfile(self.analysis_result.calibration_plot_path)


def main():
    root = tk.Tk()
    FlexCalibrationGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
