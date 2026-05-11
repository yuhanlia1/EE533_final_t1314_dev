from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_EXPORT_SPEC = importlib.util.spec_from_file_location(
    "export_other_pros_rate_xlsx_module",
    ROOT_DIR / "scripts" / "board" / "export_other_pros_rate_xlsx.py",
)
export_other_pros_rate_xlsx = importlib.util.module_from_spec(_EXPORT_SPEC)
sys.modules[_EXPORT_SPEC.name] = export_other_pros_rate_xlsx
assert _EXPORT_SPEC.loader is not None
_EXPORT_SPEC.loader.exec_module(export_other_pros_rate_xlsx)


class ExportOtherProsRateXlsxTests(unittest.TestCase):
    def test_merge_rate_rows_prefers_live_duplicate_and_sorts(self) -> None:
        baseline_rows = [
            {"offered_rate_req_per_sec": 2000.0, "run_name": "baseline_2000", "data_source": "baseline_csv"},
            {"offered_rate_req_per_sec": 100.0, "run_name": "baseline_100", "data_source": "baseline_csv"},
        ]
        live_rows = [
            {"offered_rate_req_per_sec": 2400.0, "run_name": "live_2400", "data_source": "high_range_live_scan"},
            {"offered_rate_req_per_sec": 2000.0, "run_name": "live_2000", "data_source": "high_range_live_scan"},
        ]

        merged = export_other_pros_rate_xlsx._merge_rate_rows(baseline_rows, live_rows)

        self.assertEqual([row["offered_rate_req_per_sec"] for row in merged], [100.0, 2000.0, 2400.0])
        self.assertEqual(merged[1]["run_name"], "live_2000")
        self.assertEqual(merged[1]["data_source"], "high_range_live_scan")

    def test_analyze_merged_rows_reports_zero_loss_and_first_overload(self) -> None:
        analysis = export_other_pros_rate_xlsx._analyze_merged_rows(
            [
                {"offered_rate_req_per_sec": 2000.0, "measurement_valid": True, "drop_count": 0, "mismatch_count": 0},
                {"offered_rate_req_per_sec": 2400.0, "measurement_valid": False, "drop_count": 1, "mismatch_count": 1},
            ]
        )

        self.assertEqual(analysis["max_zero_loss_pps"], 2000.0)
        self.assertEqual(analysis["first_overload_pps"], 2400.0)
        self.assertTrue(analysis["threshold_complete"])

    def test_main_writes_merged_xlsx(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            baseline_csv = tmp_path / "round1_rate_scan.csv"
            baseline_csv.write_text(
                "\n".join(
                    [
                        ",".join(export_other_pros_rate_xlsx.RATE_SCAN_COLUMNS[:-1]),
                        "baseline_100,100.0,99.5,99.0,0.001,0.0005,true,0,0.0,0,0.005,100,100,100,1.0,1.0,healthy,healthy",
                        "baseline_2000,2000.0,1980.0,1970.0,0.002,0.001,true,0,0.0,0,0.01,4000,4000,4000,2.0,2.0,healthy,healthy",
                        "baseline_2400,2400.0,2300.0,2200.0,0.002,0.001,false,2,0.001,2,0.04,4800,4798,4800,2.0,2.0,overload_or_loss,mismatch",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            live_2400_dir = tmp_path / "live_2400"
            live_2800_dir = tmp_path / "live_2800"
            live_2400_dir.mkdir()
            live_2800_dir.mkdir()
            live_summary = tmp_path / export_other_pros_rate_xlsx.RATE_SUMMARY_JSON
            live_summary.write_text(
                json.dumps(
                    {
                        "rate_points_req_per_sec": [2400, 2800],
                        "rate_results": [
                            {"run_dir": str(live_2400_dir), "run_name": "live_2400"},
                            {"run_dir": str(live_2800_dir), "run_name": "live_2800"},
                        ],
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            original_recompute = export_other_pros_rate_xlsx.board_metrics.recompute_rate_scan_result_from_run_dir

            def fake_recompute(run_dir, prior_result=None):
                run_dir = Path(run_dir)
                if run_dir == live_2400_dir:
                    return {
                        "run_name": "live_2400",
                        "offered_rate_req_per_sec": 2400.0,
                        "actual_send_rate_req_per_sec": 2390.0,
                        "goodput_result_per_sec": 2385.0,
                        "wire_goodput_gbps": 0.003,
                        "payload_goodput_gbps": 0.0015,
                        "measurement_valid": True,
                        "drop_count": 0,
                        "drop_ratio": 0.0,
                        "mismatch_count": 0,
                        "rate_error_ratio": 0.004,
                        "sender_capture_count": 4800,
                        "receiver_capture_count": 4800,
                        "engine_emit_count": 4800,
                        "receiver_span_seconds": 2.0,
                        "send_span_seconds": 2.0,
                        "pipeline_verdict": "healthy",
                        "correctness_verdict": "healthy",
                    }
                return {
                    "run_name": "live_2800",
                    "offered_rate_req_per_sec": 2800.0,
                    "actual_send_rate_req_per_sec": 2790.0,
                    "goodput_result_per_sec": 1200.0,
                    "wire_goodput_gbps": 0.0016,
                    "payload_goodput_gbps": 0.0008,
                    "measurement_valid": False,
                    "drop_count": 12,
                    "drop_ratio": 12.0 / 5600.0,
                    "mismatch_count": 12,
                    "rate_error_ratio": 0.0036,
                    "sender_capture_count": 5600,
                    "receiver_capture_count": 5588,
                    "engine_emit_count": 5600,
                    "receiver_span_seconds": 4.5,
                    "send_span_seconds": 2.0,
                    "pipeline_verdict": "overload_or_loss",
                    "correctness_verdict": "mismatch",
                }

            export_other_pros_rate_xlsx.board_metrics.recompute_rate_scan_result_from_run_dir = fake_recompute
            try:
                out_xlsx = tmp_path / "merged.xlsx"
                exit_code = export_other_pros_rate_xlsx.main(
                    [
                        "--live-summary",
                        str(live_summary),
                        "--baseline-csv",
                        str(baseline_csv),
                        "--out-xlsx",
                        str(out_xlsx),
                    ]
                )
            finally:
                export_other_pros_rate_xlsx.board_metrics.recompute_rate_scan_result_from_run_dir = original_recompute

            self.assertEqual(exit_code, 0)
            self.assertTrue(out_xlsx.exists())
            with zipfile.ZipFile(out_xlsx) as zf:
                workbook_xml = zf.read("xl/workbook.xml").decode("utf-8")
                sheet1_xml = zf.read("xl/worksheets/sheet1.xml").decode("utf-8")
                sheet2_xml = zf.read("xl/worksheets/sheet2.xml").decode("utf-8")

            self.assertIn('sheet name="rate_scan"', workbook_xml)
            self.assertIn('sheet name="summary"', workbook_xml)
            self.assertIn("data_source", sheet1_xml)
            self.assertIn("baseline_csv", sheet1_xml)
            self.assertIn("high_range_live_scan", sheet1_xml)
            self.assertIn("2400.0", sheet1_xml)
            self.assertNotIn("baseline_2400", sheet1_xml)
            self.assertIn("first_overload_pps", sheet2_xml)
            self.assertIn("2800.0", sheet2_xml)


if __name__ == "__main__":
    unittest.main()
