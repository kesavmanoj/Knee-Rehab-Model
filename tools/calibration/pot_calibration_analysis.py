from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from calibration_log_parser import parse_csv_logs, parse_text_log
from serial_protocol import LabelEvent, PotSample


@dataclass
class FitMapping:
    slope: float
    intercept: float


@dataclass
class LabelSummaryRow:
    label_deg: float
    mean_adc: float
    mean_voltage: float
    sample_count: int


@dataclass
class AnalysisResult:
    adc_mapping: FitMapping
    voltage_mapping: FitMapping
    label_summary: list[LabelSummaryRow]
    time_plot_path: Path
    calibration_plot_path: Path
    summary_text_path: Path


def fit_linear_mapping(samples: list[PotSample]) -> tuple[FitMapping, FitMapping, list[PotSample]]:
    labeled_samples = [sample for sample in samples if sample.label_deg is not None]
    if len(labeled_samples) < 2:
        raise ValueError("Need at least two labeled samples to fit a linear mapping.")

    x_adc = np.array([sample.filtered_adc for sample in labeled_samples], dtype=float)
    x_voltage = np.array([sample.voltage for sample in labeled_samples], dtype=float)
    y_angle = np.array([sample.label_deg for sample in labeled_samples], dtype=float)

    adc_slope, adc_intercept = np.polyfit(x_adc, y_angle, 1)
    voltage_slope, voltage_intercept = np.polyfit(x_voltage, y_angle, 1)

    return (
        FitMapping(float(adc_slope), float(adc_intercept)),
        FitMapping(float(voltage_slope), float(voltage_intercept)),
        labeled_samples,
    )


def summarize_labels(samples: list[PotSample]) -> list[LabelSummaryRow]:
    grouped: dict[float, list[PotSample]] = defaultdict(list)
    for sample in samples:
        if sample.label_deg is not None:
            grouped[sample.label_deg].append(sample)

    summary: list[LabelSummaryRow] = []
    for label_deg in sorted(grouped):
        label_samples = grouped[label_deg]
        mean_adc = float(np.mean([sample.filtered_adc for sample in label_samples]))
        mean_voltage = float(np.mean([sample.voltage for sample in label_samples]))
        summary.append(LabelSummaryRow(label_deg, mean_adc, mean_voltage, len(label_samples)))
    return summary


def make_time_plot(samples: list[PotSample], events: list[LabelEvent], output_path: Path):
    if not samples:
        raise ValueError("No samples found in log.")

    t0_ms = samples[0].time_ms
    times_s = [(sample.time_ms - t0_ms) / 1000.0 for sample in samples]
    filtered_adc = [sample.filtered_adc for sample in samples]

    fig, ax = plt.subplots(figsize=(12, 6))
    ax.plot(times_s, filtered_adc, color="tab:blue", linewidth=1.8, label="Filtered POT ADC")
    ax.set_title("Potentiometer Output vs Time")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Filtered ADC")
    ax.grid(True, alpha=0.25)

    active_starts: dict[float, float] = {}
    for event in events:
        event_time_s = (event.time_ms - t0_ms) / 1000.0
        if event.kind == "start":
            active_starts[event.label_deg] = event_time_s
        elif event.kind == "end" and event.label_deg in active_starts:
            start_time_s = active_starts.pop(event.label_deg)
            ax.axvspan(start_time_s, event_time_s, color="tab:orange", alpha=0.15)
            mid_time_s = (start_time_s + event_time_s) / 2.0
            ax.text(
                mid_time_s,
                ax.get_ylim()[1],
                f"{event.label_deg:.0f} deg",
                ha="center",
                va="top",
                fontsize=9,
                bbox=dict(facecolor="white", edgecolor="none", alpha=0.6),
            )

    ax.legend(loc="upper right")
    fig.tight_layout()
    fig.savefig(output_path, dpi=180)
    plt.close(fig)


def make_calibration_plot(summary: list[LabelSummaryRow], mapping_adc: FitMapping, output_path: Path):
    labels = np.array([row.label_deg for row in summary], dtype=float)
    mean_adc = np.array([row.mean_adc for row in summary], dtype=float)

    fig, ax = plt.subplots(figsize=(8, 6))
    ax.scatter(mean_adc, labels, color="tab:red", label="Labeled windows")

    x_min = float(np.min(mean_adc))
    x_max = float(np.max(mean_adc))
    x_fit = np.linspace(x_min, x_max, 100)
    y_fit = (mapping_adc.slope * x_fit) + mapping_adc.intercept
    ax.plot(x_fit, y_fit, color="black", linewidth=1.5, label="Linear fit")

    ax.set_title("Potentiometer ADC to Knee Angle Mapping")
    ax.set_xlabel("Filtered ADC")
    ax.set_ylabel("Knee Angle (deg)")
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(output_path, dpi=180)
    plt.close(fig)


def write_summary_text(result: AnalysisResult):
    lines = [
        "Linear mapping using filtered ADC:",
        f"  knee_angle_deg = ({result.adc_mapping.slope:.8f} * filtered_adc) + ({result.adc_mapping.intercept:.8f})",
        "Linear mapping using voltage:",
        f"  knee_angle_deg = ({result.voltage_mapping.slope:.8f} * voltage) + ({result.voltage_mapping.intercept:.8f})",
        "",
        "Per-label summary:",
    ]
    for row in result.label_summary:
        lines.append(
            f"  {row.label_deg:6.1f} deg -> mean ADC {row.mean_adc:8.2f}, mean V {row.mean_voltage:6.4f}, samples {row.sample_count}"
        )
    result.summary_text_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def analyze_samples_and_events(samples: list[PotSample], events: list[LabelEvent], output_dir: str | Path) -> AnalysisResult:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    adc_mapping, voltage_mapping, labeled_samples = fit_linear_mapping(samples)
    label_summary = summarize_labels(labeled_samples)

    time_plot_path = output_dir / "pot_vs_time.png"
    calibration_plot_path = output_dir / "pot_adc_to_angle_fit.png"
    summary_text_path = output_dir / "fit_summary.txt"

    make_time_plot(samples, events, time_plot_path)
    make_calibration_plot(label_summary, adc_mapping, calibration_plot_path)

    result = AnalysisResult(
        adc_mapping=adc_mapping,
        voltage_mapping=voltage_mapping,
        label_summary=label_summary,
        time_plot_path=time_plot_path,
        calibration_plot_path=calibration_plot_path,
        summary_text_path=summary_text_path,
    )
    write_summary_text(result)
    return result


def analyze_text_log(log_path: str | Path, output_dir: str | Path) -> AnalysisResult:
    samples, events = parse_text_log(log_path)
    return analyze_samples_and_events(samples, events, output_dir)


def analyze_csv_logs(samples_csv_path: str | Path, events_csv_path: str | Path, output_dir: str | Path) -> AnalysisResult:
    samples, events = parse_csv_logs(samples_csv_path, events_csv_path)
    return analyze_samples_and_events(samples, events, output_dir)
