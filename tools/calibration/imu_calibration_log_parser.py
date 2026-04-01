from __future__ import annotations

import csv
from pathlib import Path

from imu_serial_protocol import ImuSample, LabelEvent, parse_serial_line


def parse_text_log(log_path: str | Path) -> tuple[list[ImuSample], list[LabelEvent]]:
    samples: list[ImuSample] = []
    events: list[LabelEvent] = []

    with Path(log_path).open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            parsed = parse_serial_line(raw_line)
            if parsed is None:
                continue
            if isinstance(parsed, ImuSample):
                samples.append(parsed)
            elif isinstance(parsed, LabelEvent):
                events.append(parsed)

    return samples, events


def parse_csv_logs(samples_csv_path: str | Path, events_csv_path: str | Path) -> tuple[list[ImuSample], list[LabelEvent]]:
    samples: list[ImuSample] = []
    events: list[LabelEvent] = []

    with Path(samples_csv_path).open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            label_text = row["label_deg"].strip().lower()
            samples.append(
                ImuSample(
                    time_ms=int(row["board_time_ms"]),
                    master_imu_deg=float(row["master_imu_deg"]),
                    slave_imu_deg=float(row["slave_imu_deg"]),
                    imu_raw_knee_angle_deg=float(row["imu_raw_knee_angle_deg"]),
                    imu_angle_deg=float(row["imu_angle_deg"]),
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
