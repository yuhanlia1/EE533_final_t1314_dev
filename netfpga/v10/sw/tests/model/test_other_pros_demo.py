from __future__ import annotations

import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_OTHER_PROS_SPEC = importlib.util.spec_from_file_location(
    "other_pros_demo_module",
    ROOT_DIR / "scripts" / "board" / "other_pros_demo.py",
)
other_pros_demo = importlib.util.module_from_spec(_OTHER_PROS_SPEC)
assert _OTHER_PROS_SPEC.loader is not None
_OTHER_PROS_SPEC.loader.exec_module(other_pros_demo)


class OtherProsDemoTests(unittest.TestCase):
    def test_build_throughput_summary_reads_existing_thresholds(self) -> None:
        summary = other_pros_demo._build_throughput_summary(
            ROOT_DIR / "bt" / "system_report" / "summary.json"
        )

        self.assertEqual(summary["max_zero_loss_pps"], 2000.0)
        self.assertEqual(summary["first_overload_pps"], 2400.0)
        self.assertTrue(summary["figure_validity"].endswith("rate_scan_energy_validity.png"))

    def test_parse_asic_power_report_extracts_total_components(self) -> None:
        parsed = other_pros_demo._parse_asic_power_report(
            ROOT_DIR / "pd" / "asic_report" / "pnr" / "user_top" / "reports" / "4_postroute_power.rpt"
        )

        self.assertAlmostEqual(parsed["total_power_w"], 2.03e-02, places=8)
        self.assertAlmostEqual(parsed["internal_power_w"], 1.20e-02, places=8)
        self.assertAlmostEqual(parsed["switching_power_w"], 1.94e-03, places=8)
        self.assertAlmostEqual(parsed["leakage_power_w"], 6.44e-03, places=8)

    def test_print_throughput_block_has_clean_sections(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            other_pros_demo._print_throughput_block(
                {
                    "max_zero_loss_pps": 2000.0,
                    "first_overload_pps": 2400.0,
                    "rate_scan_csv": "/tmp/round1_rate_scan.csv",
                    "max_zero_loss_payload_gbps": 0.000753656762736165,
                    "max_zero_loss_wire_gbps": 0.0014131064301303098,
                    "figure_validity": "/tmp/rate_scan_energy_validity.png",
                    "figure_payload_efficiency": "/tmp/rate_scan_payload_gbps_per_watt.png",
                    "display_statement": "Zero-loss operation remains stable through the measured safe region.",
                }
            )
        rendered = buffer.getvalue()
        self.assertIn("  Max Zero-Loss Rate : 2000.0 pps\n", rendered)
        self.assertIn("\n  Threshold Evidence:\n", rendered)
        self.assertIn("\n  Recommended Figure:\n", rendered)
        self.assertIn("\n  Statement  : Zero-loss operation remains stable", rendered)

    def test_main_power_command_prints_power_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            report_path = Path(tmpdir) / "power.rpt"
            report_path.write_text(
                "\n".join(
                    [
                        "Group                  Internal  Switching    Leakage      Total",
                        "Total                  1.20e-02   1.94e-03   6.44e-03   2.03e-02 100.0%",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            buffer = io.StringIO()
            with redirect_stdout(buffer):
                rc = other_pros_demo.main(["power", "--power-report", str(report_path)])

        self.assertEqual(rc, 0)
        self.assertIn("ASIC Post-route Total Power : 2.0300e-02 W", buffer.getvalue())


if __name__ == "__main__":
    unittest.main()
