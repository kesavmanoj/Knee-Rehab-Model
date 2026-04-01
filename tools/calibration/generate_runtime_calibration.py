from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path

from calibration_curve_fitter import polyfit, rmse


def find_latest_valid_session(base_dir: Path, prefix: str, sample_file_name: str, raw_adc_field: str) -> Path:
    matches = sorted(base_dir.glob(f"{prefix}_*"), reverse=True)
    if not matches:
        raise FileNotFoundError(f"No calibration session found for prefix '{prefix}' in {base_dir}")

    for session_dir in matches:
        sample_path = session_dir / sample_file_name
        if not sample_path.exists():
            continue
        try:
            load_grouped_mean_adc(sample_path, raw_adc_field)
            return session_dir
        except Exception:
            continue

    raise ValueError(f"No valid labeled calibration session found for prefix '{prefix}' in {base_dir}")


def load_grouped_mean_adc(samples_csv_path: Path, raw_adc_field: str) -> tuple[list[float], list[float]]:
    grouped_values: dict[float, list[float]] = defaultdict(list)
    with samples_csv_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            label_text = row["label_deg"].strip()
            if not label_text:
                continue
            grouped_values[float(label_text)].append(float(row[raw_adc_field]))

    if len(grouped_values) < 2:
        raise ValueError(f"Need at least two labeled groups in {samples_csv_path}")

    mean_adc_values: list[float] = []
    label_values: list[float] = []
    for label_deg in sorted(grouped_values):
        label_values.append(label_deg)
        mean_adc_values.append(sum(grouped_values[label_deg]) / len(grouped_values[label_deg]))
    return mean_adc_values, label_values


def format_cpp_array(values: list[float]) -> str:
    return ", ".join(f"{value:.12f}f" for value in values)


def write_generated_header(
    output_path: Path,
    pot_session_name: str,
    pot_coefficients: list[float],
    pot_rmse: float,
    flex_session_name: str,
    flex_quadratic_coefficients: list[float],
    flex_quadratic_rmse: float,
    flex_cubic_coefficients: list[float],
    flex_cubic_rmse: float,
    imu_session_name: str,
    imu_coefficients: list[float],
    imu_rmse: float,
):
    output_path.write_text(
        "\n".join(
            [
                "#pragma once",
                "",
                "namespace GeneratedCalibration {",
                "",
                f'static constexpr char kPotSourceSession[] = "{pot_session_name}";',
                f"static constexpr float kPotRawAdcSlope = {pot_coefficients[0]:.12f}f;",
                f"static constexpr float kPotRawAdcIntercept = {pot_coefficients[1]:.12f}f;",
                f"static constexpr float kPotFitRmseDeg = {pot_rmse:.12f}f;",
                "",
                f'static constexpr char kFlexSourceSession[] = "{flex_session_name}";',
                "static constexpr int kFlexSelectedPolynomialDegree = 2;",
                f"static constexpr float kFlexQuadraticCoefficients[3] = {{{format_cpp_array(flex_quadratic_coefficients)}}};",
                f"static constexpr float kFlexQuadraticRmseDeg = {flex_quadratic_rmse:.12f}f;",
                f"static constexpr float kFlexCubicCoefficients[4] = {{{format_cpp_array(flex_cubic_coefficients)}}};",
                f"static constexpr float kFlexCubicRmseDeg = {flex_cubic_rmse:.12f}f;",
                "",
                f'static constexpr char kImuSourceSession[] = "{imu_session_name}";',
                f"static constexpr float kImuRawAngleSlope = {imu_coefficients[0]:.12f}f;",
                f"static constexpr float kImuRawAngleIntercept = {imu_coefficients[1]:.12f}f;",
                f"static constexpr float kImuFitRmseDeg = {imu_rmse:.12f}f;",
                "",
                "}  // namespace GeneratedCalibration",
                "",
            ]
        ),
        encoding="utf-8",
    )


def write_summary_text(
    output_path: Path,
    pot_session_name: str,
    pot_coefficients: list[float],
    pot_rmse: float,
    flex_session_name: str,
    flex_quadratic_coefficients: list[float],
    flex_quadratic_rmse: float,
    flex_cubic_coefficients: list[float],
    flex_cubic_rmse: float,
    imu_session_name: str,
    imu_coefficients: list[float],
    imu_rmse: float,
):
    output_path.write_text(
        "\n".join(
            [
                f"Pot session: {pot_session_name}",
                f"  linear angle(adc) = ({pot_coefficients[0]:.12f} * adc) + ({pot_coefficients[1]:.12f})",
                f"  rmse = {pot_rmse:.6f} deg",
                "",
                f"Flex session: {flex_session_name}",
                f"  quadratic angle(adc) = ({flex_quadratic_coefficients[0]:.12e} * adc^2) + ({flex_quadratic_coefficients[1]:.12f} * adc) + ({flex_quadratic_coefficients[2]:.12f})",
                f"  quadratic rmse = {flex_quadratic_rmse:.6f} deg",
                f"  cubic angle(adc) = ({flex_cubic_coefficients[0]:.12e} * adc^3) + ({flex_cubic_coefficients[1]:.12e} * adc^2) + ({flex_cubic_coefficients[2]:.12f} * adc) + ({flex_cubic_coefficients[3]:.12f})",
                f"  cubic rmse = {flex_cubic_rmse:.6f} deg",
                "",
                f"IMU session: {imu_session_name}",
                "  runtime uses the direct measured dual-IMU knee angle",
                "",
                "Selected runtime model:",
                "  POT -> linear on raw ADC",
                "  FLEX -> quadratic on raw ADC",
                "  IMU -> direct measured angle (no runtime calibration)",
                "",
                "If you recalibrate POT or FLEX, rerun this generator to refresh the firmware coefficients.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def main():
    parser = argparse.ArgumentParser(description="Generate runtime calibration coefficients from latest labeled POT and flex sessions.")
    parser.add_argument("--sessions-dir", default="calibration_sessions")
    parser.add_argument("--pot-session", help="Optional explicit pot session directory")
    parser.add_argument("--flex-session", help="Optional explicit flex session directory")
    parser.add_argument("--output-header", default="firmware/master_node/GeneratedCalibration.h")
    parser.add_argument("--output-summary", default="calibration_sessions/generated_runtime_calibration_summary.txt")
    args = parser.parse_args()

    sessions_dir = Path(args.sessions_dir)
    pot_session_dir = Path(args.pot_session) if args.pot_session else find_latest_valid_session(sessions_dir, "pot_session", "pot_samples.csv", "pot_raw_adc")
    flex_session_dir = Path(args.flex_session) if args.flex_session else find_latest_valid_session(sessions_dir, "flex_session", "flex_samples.csv", "flex_raw_adc")

    pot_xs, pot_ys = load_grouped_mean_adc(pot_session_dir / "pot_samples.csv", "pot_raw_adc")
    flex_xs, flex_ys = load_grouped_mean_adc(flex_session_dir / "flex_samples.csv", "flex_raw_adc")
    imu_coefficients = [1.0, 0.0]
    imu_rmse = 0.0
    imu_session_name = "direct_measurement"

    pot_coefficients = polyfit(pot_xs, pot_ys, 1)
    flex_quadratic_coefficients = polyfit(flex_xs, flex_ys, 2)
    flex_cubic_coefficients = polyfit(flex_xs, flex_ys, 3)

    pot_rmse = rmse(pot_coefficients, pot_xs, pot_ys)
    flex_quadratic_rmse = rmse(flex_quadratic_coefficients, flex_xs, flex_ys)
    flex_cubic_rmse = rmse(flex_cubic_coefficients, flex_xs, flex_ys)

    output_header = Path(args.output_header)
    output_header.parent.mkdir(parents=True, exist_ok=True)
    write_generated_header(
        output_header,
        pot_session_dir.name,
        pot_coefficients,
        pot_rmse,
        flex_session_dir.name,
        flex_quadratic_coefficients,
        flex_quadratic_rmse,
        flex_cubic_coefficients,
        flex_cubic_rmse,
        imu_session_name,
        imu_coefficients,
        imu_rmse,
    )

    output_summary = Path(args.output_summary)
    output_summary.parent.mkdir(parents=True, exist_ok=True)
    write_summary_text(
        output_summary,
        pot_session_dir.name,
        pot_coefficients,
        pot_rmse,
        flex_session_dir.name,
        flex_quadratic_coefficients,
        flex_quadratic_rmse,
        flex_cubic_coefficients,
        flex_cubic_rmse,
        imu_session_name,
        imu_coefficients,
        imu_rmse,
    )

    print(f"Generated header: {output_header}")
    print(f"Generated summary: {output_summary}")


if __name__ == "__main__":
    main()
