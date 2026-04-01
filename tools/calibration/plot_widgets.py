from __future__ import annotations

from collections import deque
import tkinter as tk


class LiveTraceCanvas(tk.Canvas):
    def __init__(self, master, width=900, height=220, max_points=240, y_min=0.0, y_max=4095.0, **kwargs):
        super().__init__(master, width=width, height=height, bg="#111418", highlightthickness=1, highlightbackground="#2b2f36", **kwargs)
        self.max_points = max_points
        self.y_min = y_min
        self.y_max = y_max
        self.samples = deque(maxlen=max_points)
        self.labels = deque(maxlen=48)
        self.total_samples = 0
        self.bind("<Configure>", lambda event: self.redraw())

    def clear(self):
        self.samples.clear()
        self.labels.clear()
        self.total_samples = 0
        self.redraw()

    def add_sample(self, value: float):
        self.samples.append(value)
        self.total_samples += 1
        self.redraw()

    def start_label(self, label_deg: float):
        start_sample = max(0, self.total_samples - 1)
        self.labels.append({"start_sample": start_sample, "end_sample": None, "label_deg": label_deg})
        self.redraw()

    def end_label(self):
        for label in reversed(self.labels):
            if label["end_sample"] is None:
                label["end_sample"] = max(0, self.total_samples - 1)
                break
        self.redraw()

    def redraw(self):
        self.delete("all")
        width = max(1, self.winfo_width())
        height = max(1, self.winfo_height())

        self._draw_grid(width, height)
        self._draw_label_regions(width, height)
        self._draw_trace(width, height)
        self._draw_axes_text(width, height)

    def _draw_grid(self, width: int, height: int):
        grid_color = "#28303a"
        for i in range(1, 5):
            y = int((height - 20) * i / 5)
            self.create_line(40, y, width - 10, y, fill=grid_color)

    def _draw_label_regions(self, width: int, height: int):
        if self.max_points <= 1 or self.total_samples == 0:
            return

        plot_left = 40
        plot_right = width - 10
        plot_width = max(1, plot_right - plot_left)
        visible_start = max(0, self.total_samples - len(self.samples))
        visible_end = self.total_samples - 1

        for label in self.labels:
            label_start = label["start_sample"]
            label_end = label["end_sample"] if label["end_sample"] is not None else visible_end
            clipped_start = max(label_start, visible_start)
            clipped_end = min(label_end, visible_end)
            if clipped_end < visible_start or clipped_start > visible_end or clipped_end < clipped_start:
                continue

            start_index = clipped_start - visible_start
            end_index = clipped_end - visible_start
            x0 = plot_left + (start_index / max(1, self.max_points - 1)) * plot_width
            x1 = plot_left + (end_index / max(1, self.max_points - 1)) * plot_width
            self.create_rectangle(x0, 10, x1, height - 20, fill="#5a4320", outline="", stipple="gray25")
            self.create_text((x0 + x1) / 2.0, 18, text=f"{label['label_deg']:.0f} deg", fill="#f3d7a3", font=("Segoe UI", 9, "bold"))

    def _draw_trace(self, width: int, height: int):
        if len(self.samples) < 2:
            return

        plot_left = 40
        plot_right = width - 10
        plot_top = 10
        plot_bottom = height - 20
        plot_width = max(1, plot_right - plot_left)
        plot_height = max(1, plot_bottom - plot_top)

        points = []
        for index, value in enumerate(self.samples):
            x = plot_left + (index / max(1, self.max_points - 1)) * plot_width
            normalized = (value - self.y_min) / max(1e-6, self.y_max - self.y_min)
            normalized = min(1.0, max(0.0, normalized))
            y = plot_bottom - (normalized * plot_height)
            points.extend([x, y])

        self.create_line(*points, fill="#53c7ff", width=2.0, smooth=True)

    def _draw_axes_text(self, width: int, height: int):
        self.create_text(20, 12, text=f"{self.y_max:.0f}", fill="#a7b0bb", font=("Segoe UI", 9))
        self.create_text(20, height - 20, text=f"{self.y_min:.0f}", fill="#a7b0bb", font=("Segoe UI", 9))
        self.create_text(width - 60, height - 8, text="recent", fill="#7f8892", font=("Segoe UI", 9))


class DualTraceCanvas(tk.Canvas):
    def __init__(
        self,
        master,
        width=900,
        height=260,
        max_points=240,
        y_min=0.0,
        y_max=145.0,
        trace_a_name="Flex Angle",
        trace_a_color="#46d676",
        trace_b_name="POT Angle",
        trace_b_color="#53c7ff",
        **kwargs,
    ):
        super().__init__(master, width=width, height=height, bg="#111418", highlightthickness=1, highlightbackground="#2b2f36", **kwargs)
        self.max_points = max_points
        self.y_min = y_min
        self.y_max = y_max
        self.trace_a_name = trace_a_name
        self.trace_a_color = trace_a_color
        self.trace_b_name = trace_b_name
        self.trace_b_color = trace_b_color
        self.trace_a = deque(maxlen=max_points)
        self.trace_b = deque(maxlen=max_points)
        self.bind("<Configure>", lambda event: self.redraw())

    def clear(self):
        self.trace_a.clear()
        self.trace_b.clear()
        self.redraw()

    def add_sample(self, trace_a_value: float, trace_b_value: float):
        self.trace_a.append(trace_a_value)
        self.trace_b.append(trace_b_value)
        self.redraw()

    def redraw(self):
        self.delete("all")
        width = max(1, self.winfo_width())
        height = max(1, self.winfo_height())

        self._draw_grid(width, height)
        self._draw_trace(width, height, self.trace_a, self.trace_a_color)
        self._draw_trace(width, height, self.trace_b, self.trace_b_color)
        self._draw_axes_text(width, height)
        self._draw_legend(width)

    def _draw_grid(self, width: int, height: int):
        grid_color = "#28303a"
        for i in range(1, 5):
            y = int((height - 24) * i / 5)
            self.create_line(40, y, width - 10, y, fill=grid_color)

    def _draw_trace(self, width: int, height: int, samples: deque, color: str):
        if len(samples) < 2:
            return

        plot_left = 40
        plot_right = width - 10
        plot_top = 10
        plot_bottom = height - 24
        plot_width = max(1, plot_right - plot_left)
        plot_height = max(1, plot_bottom - plot_top)

        points = []
        for index, value in enumerate(samples):
            x = plot_left + (index / max(1, self.max_points - 1)) * plot_width
            normalized = (value - self.y_min) / max(1e-6, self.y_max - self.y_min)
            normalized = min(1.0, max(0.0, normalized))
            y = plot_bottom - (normalized * plot_height)
            points.extend([x, y])

        self.create_line(*points, fill=color, width=2.0, smooth=True)

    def _draw_axes_text(self, width: int, height: int):
        self.create_text(20, 12, text=f"{self.y_max:.0f}", fill="#a7b0bb", font=("Segoe UI", 9))
        self.create_text(20, height - 24, text=f"{self.y_min:.0f}", fill="#a7b0bb", font=("Segoe UI", 9))
        self.create_text(width - 60, height - 8, text="recent", fill="#7f8892", font=("Segoe UI", 9))

    def _draw_legend(self, width: int):
        self.create_line(width - 220, 16, width - 198, 16, fill=self.trace_a_color, width=3)
        self.create_text(width - 152, 16, text=self.trace_a_name, fill="#d8dde5", font=("Segoe UI", 9))
        self.create_line(width - 102, 16, width - 80, 16, fill=self.trace_b_color, width=3)
        self.create_text(width - 38, 16, text=self.trace_b_name, fill="#d8dde5", font=("Segoe UI", 9))


class TripleTraceCanvas(tk.Canvas):
    def __init__(
        self,
        master,
        width=900,
        height=280,
        max_points=240,
        y_min=0.0,
        y_max=145.0,
        trace_a_name="Flex Angle",
        trace_a_color="#46d676",
        trace_b_name="POT Angle",
        trace_b_color="#53c7ff",
        trace_c_name="IMU Angle",
        trace_c_color="#ffb84d",
        **kwargs,
    ):
        super().__init__(master, width=width, height=height, bg="#111418", highlightthickness=1, highlightbackground="#2b2f36", **kwargs)
        self.max_points = max_points
        self.y_min = y_min
        self.y_max = y_max
        self.trace_a_name = trace_a_name
        self.trace_a_color = trace_a_color
        self.trace_b_name = trace_b_name
        self.trace_b_color = trace_b_color
        self.trace_c_name = trace_c_name
        self.trace_c_color = trace_c_color
        self.trace_a = deque(maxlen=max_points)
        self.trace_b = deque(maxlen=max_points)
        self.trace_c = deque(maxlen=max_points)
        self.bind("<Configure>", lambda event: self.redraw())

    def clear(self):
        self.trace_a.clear()
        self.trace_b.clear()
        self.trace_c.clear()
        self.redraw()

    def add_sample(self, trace_a_value: float, trace_b_value: float, trace_c_value: float):
        self.trace_a.append(trace_a_value)
        self.trace_b.append(trace_b_value)
        self.trace_c.append(trace_c_value)
        self.redraw()

    def redraw(self):
        self.delete("all")
        width = max(1, self.winfo_width())
        height = max(1, self.winfo_height())

        self._draw_grid(width, height)
        self._draw_trace(width, height, self.trace_a, self.trace_a_color)
        self._draw_trace(width, height, self.trace_b, self.trace_b_color)
        self._draw_trace(width, height, self.trace_c, self.trace_c_color)
        self._draw_axes_text(width, height)
        self._draw_legend(width)

    def _draw_grid(self, width: int, height: int):
        grid_color = "#28303a"
        for i in range(1, 5):
            y = int((height - 24) * i / 5)
            self.create_line(40, y, width - 10, y, fill=grid_color)

    def _draw_trace(self, width: int, height: int, samples: deque, color: str):
        if len(samples) < 2:
            return

        plot_left = 40
        plot_right = width - 10
        plot_top = 10
        plot_bottom = height - 24
        plot_width = max(1, plot_right - plot_left)
        plot_height = max(1, plot_bottom - plot_top)

        points = []
        for index, value in enumerate(samples):
            x = plot_left + (index / max(1, self.max_points - 1)) * plot_width
            normalized = (value - self.y_min) / max(1e-6, self.y_max - self.y_min)
            normalized = min(1.0, max(0.0, normalized))
            y = plot_bottom - (normalized * plot_height)
            points.extend([x, y])

        self.create_line(*points, fill=color, width=2.0, smooth=True)

    def _draw_axes_text(self, width: int, height: int):
        self.create_text(20, 12, text=f"{self.y_max:.0f}", fill="#a7b0bb", font=("Segoe UI", 9))
        self.create_text(20, height - 24, text=f"{self.y_min:.0f}", fill="#a7b0bb", font=("Segoe UI", 9))
        self.create_text(width - 60, height - 8, text="recent", fill="#7f8892", font=("Segoe UI", 9))

    def _draw_legend(self, width: int):
        self.create_line(width - 320, 16, width - 298, 16, fill=self.trace_a_color, width=3)
        self.create_text(width - 252, 16, text=self.trace_a_name, fill="#d8dde5", font=("Segoe UI", 9))
        self.create_line(width - 200, 16, width - 178, 16, fill=self.trace_b_color, width=3)
        self.create_text(width - 132, 16, text=self.trace_b_name, fill="#d8dde5", font=("Segoe UI", 9))
        self.create_line(width - 92, 16, width - 70, 16, fill=self.trace_c_color, width=3)
        self.create_text(width - 32, 16, text=self.trace_c_name, fill="#d8dde5", font=("Segoe UI", 9))
