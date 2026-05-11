from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_EXPORT_SPEC = importlib.util.spec_from_file_location(
    "system_metrics_export_module",
    ROOT_DIR / "scripts" / "board" / "nic_round2" / "export_system_metrics.py",
)
system_export = importlib.util.module_from_spec(_EXPORT_SPEC)
assert _EXPORT_SPEC.loader is not None
_EXPORT_SPEC.loader.exec_module(system_export)


class SystemMetricsExportTests(unittest.TestCase):
    def test_parse_fpga_utilization_srp_reads_expected_counts(self) -> None:
        result = system_export.parse_fpga_utilization_srp(ROOT_DIR / "pd" / "fpga_report" / "nf2_top.srp")

        self.assertEqual(result["device"], "2vp50ff1152-7")
        self.assertEqual(result["lut4"], 30669)
        self.assertEqual(result["brams"], 108)
        self.assertEqual(result["mult18x18"], 11)
        self.assertEqual(result["bonded_iobs"], 360)

    def test_parse_asic_power_report_reads_total_power(self) -> None:
        result = system_export.parse_asic_power_report(
            ROOT_DIR / "pd" / "asic_report" / "pnr" / "user_top" / "reports" / "4_postroute_power.rpt"
        )

        self.assertAlmostEqual(result["total_power_w"], 2.03e-02, places=8)
        self.assertAlmostEqual(result["internal_power_w"], 1.20e-02, places=8)
        self.assertIn("Macro", result["groups"])

    def test_build_fpga_theoretical_power_sums_components(self) -> None:
        model = json.loads((ROOT_DIR / "bt" / "power_models" / "fpga_resource_model.json").read_text(encoding="utf-8"))
        utilization = system_export.parse_fpga_utilization_srp(ROOT_DIR / "pd" / "fpga_report" / "nf2_top.srp")

        result = system_export.build_fpga_theoretical_power(utilization, model)

        component_sum = sum(item["power_w"] for item in result["components"].values())
        self.assertAlmostEqual(result["total_power_w"], component_sum, places=12)
        self.assertGreater(result["total_power_w"], 0.0)

    def test_rate_scan_rows_compute_energy_only_for_valid_points(self) -> None:
        summary = json.loads((ROOT_DIR / "bt" / "round1_final" / "summary.json").read_text(encoding="utf-8"))
        rows = system_export._rate_scan_rows(summary, 1.0, 2.0)
        valid_2000 = next(row for row in rows if float(row["offered_rate_req_per_sec"]) == 2000.0)
        invalid_2400 = next(row for row in rows if float(row["offered_rate_req_per_sec"]) == 2400.0)

        self.assertTrue(valid_2000["measurement_valid"])
        self.assertGreater(valid_2000["fpga_energy_per_inference_j"], 0.0)
        self.assertFalse(invalid_2400["measurement_valid"])
        self.assertIsNone(invalid_2400["fpga_energy_per_inference_j"])

    def test_main_exports_expected_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "system_report"
            parser = system_export.build_parser()
            args = parser.parse_args(
                [
                    "--out-dir",
                    str(out_dir),
                ]
            )
            source_summary_path = Path(args.source_summary).resolve()
            fpga_srp_path = Path(args.fpga_srp).resolve()
            fpga_model_path = Path(args.fpga_model).resolve()
            asic_power_path = Path(args.asic_power_report).resolve()

            summary = system_export._load_json(source_summary_path)
            fpga_model = system_export._load_json(fpga_model_path)
            fpga_utilization = system_export.parse_fpga_utilization_srp(fpga_srp_path)
            asic_power = system_export.parse_asic_power_report(asic_power_path)
            fpga_power = system_export.build_fpga_theoretical_power(fpga_utilization, fpga_model)
            single_rows = system_export._single_packet_rows(summary, fpga_power["total_power_w"], asic_power["total_power_w"])
            rate_rows = system_export._rate_scan_rows(summary, fpga_power["total_power_w"], asic_power["total_power_w"])
            burst_rows = system_export._burst_rows(summary, fpga_power["total_power_w"], asic_power["total_power_w"])
            overview_rows = system_export._overview_rows(
                summary,
                source_summary_path,
                fpga_model_path,
                asic_power_path,
                fpga_power,
                asic_power,
                rate_rows,
            )

            system_export._write_csv(out_dir / "system_metrics_overview.csv", ["dataset_version"], overview_rows)
            system_export._write_csv(out_dir / "system_single_packet.csv", ["run_name"], single_rows)
            system_export._write_csv(out_dir / "system_fpga_energy.csv", ["run_name"], rate_rows)
            system_export._write_csv(out_dir / "system_asic_energy.csv", ["run_name"], rate_rows)
            system_export._write_csv(out_dir / "system_burst_energy.csv", ["run_name"], burst_rows)
            system_export._write_json(out_dir / "summary.json", {"overview": overview_rows[0]})
            system_export._write_text(out_dir / "summary.md", "# demo\n")
            system_export._write_readme(out_dir, source_summary_path, fpga_model_path, asic_power_path)

            self.assertTrue((out_dir / "system_metrics_overview.csv").exists())
            self.assertTrue((out_dir / "system_single_packet.csv").exists())
            self.assertTrue((out_dir / "system_fpga_energy.csv").exists())
            self.assertTrue((out_dir / "system_asic_energy.csv").exists())
            self.assertTrue((out_dir / "system_burst_energy.csv").exists())
            self.assertTrue((out_dir / "summary.json").exists())
            self.assertTrue((out_dir / "summary.md").exists())
            self.assertTrue((out_dir / "README.md").exists())
