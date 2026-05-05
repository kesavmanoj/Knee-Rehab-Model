from __future__ import annotations

import csv
from pathlib import Path

try:
    from .flex_serial_protocol import FlexSample, LabelEvent, parse_serial_line
except ImportError:
    from flex_serial_protocol import FlexSample, LabelEvent, parse_serial_line


def parse_text_log(log_path: str | Path) -> tuple[list[FlexSample], list[LabelEvent]]:
    samples: list[FlexSample] = []
    events: list[LabelEvent] = []

    with Path(log_path).open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            parsed = parse_serial_line(raw_line)
            if parsed is None:
                continue
            if isinstance(parsed, FlexSample):
                samples.append(parsed)
            elif isinstance(parsed, LabelEvent):
                events.append(parsed)

    return samples, events


def parse_csv_logs(samples_csv_path: str | Path, events_csv_path: str | Path) -> tuple[list[FlexSample], list[LabelEvent]]:
    samples: list[FlexSample] = []
    events: list[LabelEvent] = []

    with Path(samples_csv_path).open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            resistance_text = row["flex_resistance_ohms"].strip().lower()
            label_text = row["label_deg"].strip().lower()
            samples.append(
                FlexSample(
                    time_ms=int(row["board_time_ms"]),
                    raw_adc=int(row["flex_raw_adc"]),
                    filtered_adc=float(row["flex_filtered_adc"]),
                    voltage=float(row["flex_voltage"]),
                    resistance_ohms=None if resistance_text in ("", "nan", "none") else float(row["flex_resistance_ohms"]),
                    flex_angle_deg=float(row["flex_angle_deg"]),
                    label_deg=None if label_text in ("", "nan", "none") else float(row["label_deg"]),
                )
            )

    with Path(events_csv_path).open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            events.append(
                LabelEvent(
                    kind=row["kind"],
                    time_ms=int(row["board_time_ms"]),
                    label_deg=float(row["label_deg"]),
                    window_ms=None if row["window_ms"] in ("", "None") else int(row["window_ms"]),
                )
            )

    return samples, events
