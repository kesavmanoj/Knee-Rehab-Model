from __future__ import annotations

from dataclasses import dataclass


@dataclass
class ImuSample:
    time_ms: int
    master_imu_deg: float
    slave_imu_deg: float
    imu_raw_knee_angle_deg: float
    imu_angle_deg: float
    label_deg: float | None


@dataclass
class LabelEvent:
    kind: str
    time_ms: int
    label_deg: float
    window_ms: int | None = None


def parse_serial_line(line: str) -> ImuSample | LabelEvent | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None

    parts = stripped.split(",")
    if parts[0] == "IMU_SAMPLE" and len(parts) == 7:
        label_text = parts[6].strip().lower()
        return ImuSample(
            time_ms=int(parts[1]),
            master_imu_deg=float(parts[2]),
            slave_imu_deg=float(parts[3]),
            imu_raw_knee_angle_deg=float(parts[4]),
            imu_angle_deg=float(parts[5]),
            label_deg=None if label_text == "nan" else float(parts[6]),
        )

    if parts[0] == "LABEL_START" and len(parts) == 4:
        return LabelEvent(kind="start", time_ms=int(parts[1]), label_deg=float(parts[2]), window_ms=int(parts[3]))

    if parts[0] == "LABEL_END" and len(parts) == 3:
        return LabelEvent(kind="end", time_ms=int(parts[1]), label_deg=float(parts[2]), window_ms=None)

    return None
