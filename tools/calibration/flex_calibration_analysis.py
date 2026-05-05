from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

try:
    from .calibration_curve_fitter import polyfit, polyval, rmse
    from .flex_calibration_log_parser import parse_csv_logs, parse_text_log
    from .flex_serial_protocol import FlexSample, LabelEvent
except ImportError:
    from calibration_curve_fitter import polyfit, polyval, rmse
    from flex_calibration_log_parser import parse_csv_logs, parse_text_log
    from flex_serial_protocol import FlexSample, LabelEvent


@dataclass
class FitMapping:
    slope: float
    intercept: float


@dataclass
class PolynomialFit:
    degree: int
    coefficients: list[float]
    rmse_deg: float


@dataclass
class LabelSummaryRow:
    label_deg: float
    mean_adc: float
    mean_voltage: float
    mean_resistance_ohms: float | None
    sample_count: int


@dataclass
class AnalysisResult:
    adc_mapping: FitMapping
    resistance_mapping: FitMapping
    adc_polynomial_fits: list[PolynomialFit]
    label_summary: list[LabelSummaryRow]
    time_plot_path: Path
    calibration_plot_path: Path
    summary_text_path: Path


def fit_linear_mapping(samples: list[FlexSample]) -> tuple[FitMapping, FitMapping, list[FlexSample]]:
    labeled_samples = [sample for sample in samples if sample.label_deg is not None and sample.resistance_ohms is not None]
    if len(labeled_samples) < 2:
        raise ValueError("Need at least two labeled samples with valid resistance to fit a linear mapping.")

    x_adc = np.array([sample.filtered_adc for sample in labeled_samples], dtype=float)
    x_resistance = np.array([sample.resistance_ohms for sample in labeled_samples], dtype=float)
    y_angle = np.array([sample.label_deg for sample in labeled_samples], dtype=float)

    adc_slope, adc_intercept = np.polyfit(x_adc, y_angle, 1)
    resistance_slope, resistance_intercept = np.polyfit(x_resistance, y_angle, 1)

    return (
        FitMapping(float(adc_slope), float(adc_intercept)),
        FitMapping(float(resistance_slope), float(resistance_intercept)),
        labeled_samples,
    )


def fit_adc_polynomials(samples: list[FlexSample]) -> list[PolynomialFit]:
    labeled_samples = [sample for sample in samples if sample.label_deg is not None]
    if len(labeled_samples) < 4:
        raise ValueError("Need at least four labeled samples to fit 1st, 2nd, and 3rd degree polynomials.")

    x_adc = [float(sample.filtered_adc) for sample in labeled_samples]
    y_angle = [float(sample.label_deg) for sample in labeled_samples]

    fits: list[PolynomialFit] = []
    for degree in (1, 2, 3):
        coefficients = polyfit(x_adc, y_angle, degree)
        fits.append(
            PolynomialFit(
                degree=degree,
                coefficients=coefficients,
                rmse_deg=rmse(coefficients, x_adc, y_angle),
            )
        )
    return fits


def summarize_labels(samples: list[FlexSample]) -> list[LabelSummaryRow]:
    grouped: dict[float, list[FlexSample]] = defaultdict(list)
    for sample in samples:
        if sample.label_deg is not None:
            grouped[sample.label_deg].append(sample)

    summary: list[LabelSummaryRow] = []
    for label_deg in sorted(grouped):
        label_samples = grouped[label_deg]
        resistance_values = [sample.resistance_ohms for sample in label_samples if sample.resistance_ohms is not None]
        mean_resistance = float(np.mean(resistance_values)) if resistance_values else None
        summary.append(
            LabelSummaryRow(
                label_deg=label_deg,
                mean_adc=float(np.mean([sample.filtered_adc for sample in label_samples])),
                mean_voltage=float(np.mean([sample.voltage for sample in label_samples])),
                mean_resistance_ohms=mean_resistance,
                sample_count=len(label_samples),
            )
        )
    return summary


def make_time_plot(samples: list[FlexSample], events: list[LabelEvent], output_path: Path):
    if not samples:
        raise ValueError("No samples found in log.")

    t0_ms = samples[0].time_ms
    times_s = [(sample.time_ms - t0_ms) / 1000.0 for sample in samples]
    filtered_adc = [sample.filtered_adc for sample in samples]

    fig, ax = plt.subplots(figsize=(12, 6))
    ax.plot(times_s, filtered_adc, color="tab:green", linewidth=1.8, label="Filtered Flex ADC")
    ax.set_title("Flex Sensor Output vs Time")
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


def make_calibration_plot(summary: list[LabelSummaryRow], polynomial_fits: list[PolynomialFit], output_path: Path):
    labels = np.array([row.label_deg for row in summary], dtype=float)
    mean_adc = np.array([row.mean_adc for row in summary], dtype=float)

    fig, ax = plt.subplots(figsize=(8, 6))
    ax.scatter(mean_adc, labels, color="tab:red", label="Labeled windows")

    x_min = float(np.min(mean_adc))
    x_max = float(np.max(mean_adc))
    x_fit = np.linspace(x_min, x_max, 200)

    fit_colours = {
        1: "black",
        2: "tab:blue",
        3: "tab:green",
    }

    for fit in polynomial_fits:
        y_fit = np.array([polyval(fit.coefficients, x_value) for x_value in x_fit], dtype=float)
        ax.plot(
            x_fit,
            y_fit,
            color=fit_colours.get(fit.degree, "tab:gray"),
            linewidth=1.8,
            label=f"{fit.degree} degree fit (RMSE {fit.rmse_deg:.2f})",
        )

    ax.set_title("Flex Sensor ADC to Knee Angle Mapping")
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
        "Linear mapping using resistance:",
        f"  knee_angle_deg = ({result.resistance_mapping.slope:.8f} * resistance_ohms) + ({result.resistance_mapping.intercept:.8f})",
        "",
        "ADC polynomial fits:",
    ]
    for fit in result.adc_polynomial_fits:
        coefficients_text = ", ".join(f"{coefficient:.12f}" for coefficient in fit.coefficients)
        lines.append(f"  degree {fit.degree}: coeffs [{coefficients_text}] | rmse = {fit.rmse_deg:.6f} deg")
    lines.extend([
        "",
        "Per-label summary:",
    ])
    for row in result.label_summary:
        resistance_text = "nan" if row.mean_resistance_ohms is None else f"{row.mean_resistance_ohms:9.2f}"
        lines.append(
            f"  {row.label_deg:6.1f} deg -> mean ADC {row.mean_adc:8.2f}, mean V {row.mean_voltage:6.4f}, mean R {resistance_text}, samples {row.sample_count}"
        )
    result.summary_text_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def analyze_samples_and_events(samples: list[FlexSample], events: list[LabelEvent], output_dir: str | Path) -> AnalysisResult:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    adc_mapping, resistance_mapping, labeled_samples = fit_linear_mapping(samples)
    adc_polynomial_fits = fit_adc_polynomials(samples)
    label_summary = summarize_labels(labeled_samples)

    time_plot_path = output_dir / "flex_vs_time.png"
    calibration_plot_path = output_dir / "flex_adc_to_angle_fit.png"
    summary_text_path = output_dir / "fit_summary.txt"

    make_time_plot(samples, events, time_plot_path)
    make_calibration_plot(label_summary, adc_polynomial_fits, calibration_plot_path)

    result = AnalysisResult(
        adc_mapping=adc_mapping,
        resistance_mapping=resistance_mapping,
        adc_polynomial_fits=adc_polynomial_fits,
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
