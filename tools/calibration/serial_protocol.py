from __future__ import annotations

from dataclasses import dataclass


@dataclass
class PotSample:
    time_ms: int
    raw_adc: int
    filtered_adc: float
    voltage: float
    pot_angle_deg: float
    label_deg: float | None


@dataclass
class LabelEvent:
    kind: str
    time_ms: int
    label_deg: float
    window_ms: int | None = None


def parse_serial_line(line: str) -> PotSample | LabelEvent | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None

    parts = stripped.split(",")
    if parts[0] in ("SAMPLE", "POT_SAMPLE") and len(parts) == 7:
        return PotSample(
            time_ms=int(parts[1]),
            raw_adc=int(parts[2]),
            filtered_adc=float(parts[3]),
            voltage=float(parts[4]),
            pot_angle_deg=float(parts[5]),
            label_deg=None if parts[6].lower() == "nan" else float(parts[6]),
        )

    if parts[0] == "LABEL_START" and len(parts) == 4:
        return LabelEvent(
            kind="start",
            time_ms=int(parts[1]),
            label_deg=float(parts[2]),
            window_ms=int(parts[3]),
        )

    if parts[0] == "LABEL_END" and len(parts) == 3:
        return LabelEvent(
            kind="end",
            time_ms=int(parts[1]),
            label_deg=float(parts[2]),
            window_ms=None,
        )

    return None
