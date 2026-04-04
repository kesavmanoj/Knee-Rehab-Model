from __future__ import annotations

import re
from dataclasses import dataclass


RUNTIME_CSV_PREFIX = "RUNTIME_SAMPLE"
SIMPLE_PREFIX = "SIMPLE"
RUNTIME_LINE_PATTERN = re.compile(
    r"FLEX_RAW:\[(?P<flex_raw>\d+)\]\s+\|\s+FLEX_ANGLE:\[\s*(?P<flex_angle>-?\d+(?:\.\d+)?)\]\s+deg\s+\|\s+"
    r"POT_RAW:\[(?P<pot_raw>\d+)\]\s+\|\s+POT_ANGLE:\[\s*(?P<pot_angle>-?\d+(?:\.\d+)?)\]\s+deg"
)


@dataclass
class RuntimeSensorSample:
    time_ms: int | None
    flex_raw_adc: int
    flex_angle_deg: float
    pot_raw_adc: int
    pot_angle_deg: float
    master_imu_deg: float | None
    slave_imu_deg: float | None
    imu_angle_deg: float | None
    fused_angle_deg: float | None


def parse_runtime_line(line: str) -> RuntimeSensorSample | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None

    parts = stripped.split(",")
    if parts[0] == RUNTIME_CSV_PREFIX and len(parts) == 6:
        return RuntimeSensorSample(
            time_ms=int(parts[1]),
            flex_raw_adc=int(parts[2]),
            flex_angle_deg=float(parts[3]),
            pot_raw_adc=int(parts[4]),
            pot_angle_deg=float(parts[5]),
            master_imu_deg=None,
            slave_imu_deg=None,
            imu_angle_deg=None,
            fused_angle_deg=None,
        )

    if parts[0] == RUNTIME_CSV_PREFIX and len(parts) == 9:
        return RuntimeSensorSample(
            time_ms=int(parts[1]),
            flex_raw_adc=int(parts[2]),
            flex_angle_deg=float(parts[3]),
            pot_raw_adc=int(parts[4]),
            pot_angle_deg=float(parts[5]),
            master_imu_deg=float(parts[6]),
            slave_imu_deg=float(parts[7]),
            imu_angle_deg=float(parts[8]),
            fused_angle_deg=None,
        )

    if parts[0] == SIMPLE_PREFIX and len(parts) == 11:
        return RuntimeSensorSample(
            time_ms=int(parts[1]),
            flex_raw_adc=int(parts[6]),
            flex_angle_deg=float(parts[7]),
            pot_raw_adc=int(parts[8]),
            pot_angle_deg=float(parts[9]),
            master_imu_deg=float(parts[2]),
            slave_imu_deg=float(parts[3]),
            imu_angle_deg=float(parts[4]),
            fused_angle_deg=float(parts[5]),
        )

    match = RUNTIME_LINE_PATTERN.fullmatch(stripped)
    if not match:
        return None

    return RuntimeSensorSample(
        time_ms=None,
        flex_raw_adc=int(match.group("flex_raw")),
        flex_angle_deg=float(match.group("flex_angle")),
        pot_raw_adc=int(match.group("pot_raw")),
        pot_angle_deg=float(match.group("pot_angle")),
        master_imu_deg=None,
        slave_imu_deg=None,
        imu_angle_deg=None,
        fused_angle_deg=None,
    )
