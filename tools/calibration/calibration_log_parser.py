from __future__ import annotations

import csv
from pathlib import Path
from typing import List

from serial_protocol import LabelEvent, PotSample, parse_serial_line


def parse_text_log(log_path: str | Path) -> tuple[List[PotSample], List[LabelEvent]]:
    samples: List[PotSample] = []
    events: List[LabelEvent] = []

    with Path(log_path).open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            parsed = parse_serial_line(raw_line)
            if parsed is None:
                continue
            if isinstance(parsed, PotSample):
                samples.append(parsed)
            elif isinstance(parsed, LabelEvent):
                events.append(parsed)

    return samples, events


def parse_csv_logs(samples_csv_path: str | Path, events_csv_path: str | Path) -> tuple[List[PotSample], List[LabelEvent]]:
    samples: List[PotSample] = []
    events: List[LabelEvent] = []

    with Path(samples_csv_path).open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            samples.append(
                PotSample(
                    time_ms=int(row["board_time_ms"]),
                    raw_adc=int(row["pot_raw_adc"]),
                    filtered_adc=float(row["pot_filtered_adc"]),
                    voltage=float(row["pot_voltage"]),
                    pot_angle_deg=float(row["pot_angle_deg"]),
                    label_deg=None if row["label_deg"] in ("", "nan", "None") else float(row["label_deg"]),
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
