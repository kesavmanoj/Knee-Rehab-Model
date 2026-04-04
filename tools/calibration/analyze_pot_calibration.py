from __future__ import annotations

import argparse
from pathlib import Path

from pot_calibration_analysis import analyze_csv_logs, analyze_text_log


def main():
    parser = argparse.ArgumentParser(description="Analyze labeled potentiometer calibration logs.")
    parser.add_argument("log_path", nargs="?", help="Path to the raw serial log text file")
    parser.add_argument("--samples-csv", help="Path to samples CSV collected by the live logger")
    parser.add_argument("--events-csv", help="Path to label events CSV collected by the live logger")
    parser.add_argument("--output-dir", default="calibration_output", help="Directory for plots")
    args = parser.parse_args()

    if args.samples_csv or args.events_csv:
        if not args.samples_csv or not args.events_csv:
            raise ValueError("Provide both --samples-csv and --events-csv together.")
        result = analyze_csv_logs(args.samples_csv, args.events_csv, args.output_dir)
    else:
        if not args.log_path:
            raise ValueError("Provide either a raw log path or both CSV paths.")
        result = analyze_text_log(args.log_path, args.output_dir)

    print("Linear mapping using filtered ADC:")
    print(f"  knee_angle_deg = ({result.adc_mapping.slope:.8f} * filtered_adc) + ({result.adc_mapping.intercept:.8f})")
    print("Linear mapping using voltage:")
    print(f"  knee_angle_deg = ({result.voltage_mapping.slope:.8f} * voltage) + ({result.voltage_mapping.intercept:.8f})")
    print()
    print("Per-label summary:")
    for row in result.label_summary:
        print(
            f"  {row.label_deg:6.1f} deg -> mean ADC {row.mean_adc:8.2f}, mean V {row.mean_voltage:6.4f}, samples {row.sample_count}"
        )
    print()
    print(f"Saved: {Path(result.time_plot_path)}")
    print(f"Saved: {Path(result.calibration_plot_path)}")
    print(f"Saved: {Path(result.summary_text_path)}")


if __name__ == "__main__":
    main()
