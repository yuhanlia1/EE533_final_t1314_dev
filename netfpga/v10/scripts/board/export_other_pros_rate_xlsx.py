#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, Sequence
import sys
from xml.sax.saxutils import escape
import zipfile


ROOT_DIR = Path(__file__).resolve().parents[2]
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import board_metrics


DEFAULT_BASELINE_CSV = ROOT_DIR / "bt" / "report" / "round1_rate_scan.csv"
DEFAULT_OUT_XLSX = ROOT_DIR / "bt" / "report" / "round1_rate_scan_extended.xlsx"
DEFAULT_BASELINE_MAX_PPS = 2000.0
RATE_SUMMARY_JSON = "other_pros_rate_summary.json"

RATE_SCAN_COLUMNS = [
    "run_name",
    "offered_rate_req_per_sec",
    "actual_send_rate_req_per_sec",
    "goodput_result_per_sec",
    "wire_goodput_gbps",
    "payload_goodput_gbps",
    "measurement_valid",
    "drop_count",
    "drop_ratio",
    "mismatch_count",
    "rate_error_ratio",
    "sender_capture_count",
    "receiver_capture_count",
    "engine_emit_count",
    "receiver_span_seconds",
    "send_span_seconds",
    "pipeline_verdict",
    "correctness_verdict",
    "data_source",
]

FLOAT_FIELDS = {
    "offered_rate_req_per_sec",
    "actual_send_rate_req_per_sec",
    "goodput_result_per_sec",
    "wire_goodput_gbps",
    "payload_goodput_gbps",
    "drop_ratio",
    "rate_error_ratio",
    "receiver_span_seconds",
    "send_span_seconds",
}

INT_FIELDS = {
    "drop_count",
    "mismatch_count",
    "sender_capture_count",
    "receiver_capture_count",
    "engine_emit_count",
}

BOOL_FIELDS = {"measurement_valid"}


@dataclass
class Sheet:
    name: str
    rows: list[list[object]]
    widths: Sequence[int]


def _load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _parse_scalar(field: str, raw_value: str):
    value = str(raw_value).strip()
    if value == "":
        return None
    if field in BOOL_FIELDS:
        return value.lower() == "true"
    if field in INT_FIELDS:
        return int(float(value))
    if field in FLOAT_FIELDS:
        return float(value)
    return value


def _normalize_rate_row(row: dict, data_source: str) -> dict:
    normalized = {}
    for field in RATE_SCAN_COLUMNS:
        if field == "data_source":
            normalized[field] = data_source
        else:
            normalized[field] = row.get(field)
    return normalized


def _load_baseline_rows(path: Path, max_baseline_pps: float) -> list[dict]:
    rows = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for raw_row in reader:
            parsed = {key: _parse_scalar(key, value) for key, value in raw_row.items()}
            offered = float(parsed.get("offered_rate_req_per_sec") or 0.0)
            if offered > float(max_baseline_pps):
                continue
            rows.append(_normalize_rate_row(parsed, "baseline_csv"))
    return sorted(rows, key=lambda item: float(item.get("offered_rate_req_per_sec") or 0.0))


def _load_live_rows(summary_path: Path) -> tuple[dict, list[dict]]:
    summary = _load_json(summary_path)
    rows = []
    for prior_row in summary.get("rate_results", []):
        recomputed = board_metrics.recompute_rate_scan_result_from_run_dir(
            prior_row["run_dir"],
            prior_result=prior_row,
        )
        rows.append(_normalize_rate_row(recomputed, "high_range_live_scan"))
    rows.sort(key=lambda item: float(item.get("offered_rate_req_per_sec") or 0.0))
    return summary, rows


def _merge_rate_rows(baseline_rows: list[dict], live_rows: list[dict]) -> list[dict]:
    merged = {}
    for row in baseline_rows:
        merged[float(row.get("offered_rate_req_per_sec") or 0.0)] = row
    for row in live_rows:
        merged[float(row.get("offered_rate_req_per_sec") or 0.0)] = row
    return [merged[key] for key in sorted(merged)]


def _is_zero_loss(row: dict) -> bool:
    return (
        bool(row.get("measurement_valid"))
        and int(row.get("drop_count", 0) or 0) == 0
        and int(row.get("mismatch_count", 0) or 0) == 0
    )


def _analyze_merged_rows(rows: list[dict]) -> dict:
    ordered = sorted(rows, key=lambda item: float(item.get("offered_rate_req_per_sec") or 0.0))
    passing = [item for item in ordered if _is_zero_loss(item)]
    max_zero_loss = passing[-1] if passing else None
    first_overload = None
    for item in ordered:
        if not _is_zero_loss(item):
            first_overload = item
            break
    return {
        "max_zero_loss_pps": max_zero_loss.get("offered_rate_req_per_sec") if max_zero_loss is not None else None,
        "first_overload_pps": (
            first_overload.get("offered_rate_req_per_sec") if first_overload is not None else None
        ),
        "threshold_complete": first_overload is not None,
    }


def _summary_rows(
    baseline_csv: Path,
    live_summary: Path,
    live_summary_data: dict,
    merged_rows: list[dict],
    baseline_rows: list[dict],
    live_rows: list[dict],
) -> list[list[object]]:
    analysis = _analyze_merged_rows(merged_rows)
    return [
        ["field", "value"],
        ["created_at", datetime.now().isoformat(timespec="seconds")],
        ["baseline_source_csv", str(baseline_csv.resolve())],
        ["live_scan_summary_json", str(live_summary.resolve())],
        [
            "high_range_rates",
            ",".join(str(int(rate)) for rate in live_summary_data.get("rate_points_req_per_sec", [])),
        ],
        ["baseline_row_count", len(baseline_rows)],
        ["live_row_count", len(live_rows)],
        ["merged_row_count", len(merged_rows)],
        ["max_zero_loss_pps", analysis["max_zero_loss_pps"]],
        ["first_overload_pps", analysis["first_overload_pps"]],
        ["threshold_complete", analysis["threshold_complete"]],
    ]


def _rate_scan_sheet_rows(merged_rows: list[dict]) -> list[list[object]]:
    rows = [list(RATE_SCAN_COLUMNS)]
    for row in merged_rows:
        rows.append([row.get(field) for field in RATE_SCAN_COLUMNS])
    return rows


def _as_cell_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _excel_column_name(index: int) -> str:
    result = []
    while index > 0:
        index, rem = divmod(index - 1, 26)
        result.append(chr(65 + rem))
    return "".join(reversed(result))


def _cols_xml(widths: Sequence[int]) -> str:
    entries = []
    for idx, width in enumerate(widths, start=1):
        entries.append(f'<col min="{idx}" max="{idx}" width="{width}" customWidth="1"/>')
    return f'<cols>{"".join(entries)}</cols>'


def _sheet_xml(sheet: Sheet) -> str:
    row_xml = []
    for row_idx, row in enumerate(sheet.rows, start=1):
        cells = []
        for col_idx, value in enumerate(row, start=1):
            ref = f"{_excel_column_name(col_idx)}{row_idx}"
            text = escape(_as_cell_text(value))
            style = ' s="1"' if row_idx == 1 else ""
            cells.append(f'<c r="{ref}" t="inlineStr"{style}><is><t>{text}</t></is></c>')
        row_xml.append(f'<row r="{row_idx}">{"".join(cells)}</row>')
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
        f'{_cols_xml(sheet.widths)}'
        '<sheetData>'
        f'{"".join(row_xml)}'
        '</sheetData>'
        '</worksheet>'
    )


def _workbook_xml(sheets: Iterable[Sheet]) -> str:
    entries = []
    for idx, sheet in enumerate(sheets, start=1):
        entries.append(f'<sheet name="{escape(sheet.name)}" sheetId="{idx}" r:id="rId{idx}"/>')
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>'
        f'{"".join(entries)}'
        '</sheets>'
        '</workbook>'
    )


def _workbook_rels_xml(sheet_count: int) -> str:
    rels = []
    for idx in range(1, sheet_count + 1):
        rels.append(
            f'<Relationship Id="rId{idx}" '
            f'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            f'Target="worksheets/sheet{idx}.xml"/>'
        )
    rels.append(
        f'<Relationship Id="rId{sheet_count + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/>'
    )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        f'{"".join(rels)}'
        '</Relationships>'
    )


def _root_rels_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/>'
        '</Relationships>'
    )


def _content_types_xml(sheet_count: int) -> str:
    overrides = [
        '<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
        '<Override PartName="/xl/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    ]
    for idx in range(1, sheet_count + 1):
        overrides.append(
            f'<Override PartName="/xl/worksheets/sheet{idx}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        f'{"".join(overrides)}'
        '</Types>'
    )


def _styles_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2">'
        '<font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font>'
        '</fonts>'
        '<fills count="2">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '</fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
        '</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>'
    )


def _write_xlsx(sheets: list[Sheet], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", _content_types_xml(len(sheets)))
        zf.writestr("_rels/.rels", _root_rels_xml())
        zf.writestr("xl/workbook.xml", _workbook_xml(sheets))
        zf.writestr("xl/_rels/workbook.xml.rels", _workbook_rels_xml(len(sheets)))
        zf.writestr("xl/styles.xml", _styles_xml())
        for idx, sheet in enumerate(sheets, start=1):
            zf.writestr(f"xl/worksheets/sheet{idx}.xml", _sheet_xml(sheet))


def _resolve_live_summary_path(args: argparse.Namespace) -> Path:
    if args.live_summary:
        return Path(args.live_summary).resolve()
    return (Path(args.run_dir).resolve() / RATE_SUMMARY_JSON).resolve()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Merge baseline + live high-range rate-scan data into Excel.")
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--run-dir", help="Live rate-scan run_dir containing other_pros_rate_summary.json")
    source_group.add_argument("--live-summary", help="Path to other_pros_rate_summary.json")
    parser.add_argument("--baseline-csv", default=str(DEFAULT_BASELINE_CSV))
    parser.add_argument("--baseline-max-pps", type=float, default=DEFAULT_BASELINE_MAX_PPS)
    parser.add_argument("--out-xlsx", default=str(DEFAULT_OUT_XLSX))
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    baseline_csv = Path(args.baseline_csv).resolve()
    live_summary_path = _resolve_live_summary_path(args)
    out_xlsx = Path(args.out_xlsx).resolve()

    baseline_rows = _load_baseline_rows(baseline_csv, args.baseline_max_pps)
    live_summary, live_rows = _load_live_rows(live_summary_path)
    merged_rows = _merge_rate_rows(baseline_rows, live_rows)
    analysis = _analyze_merged_rows(merged_rows)

    sheets = [
        Sheet(
            "rate_scan",
            _rate_scan_sheet_rows(merged_rows),
            [28, 18, 22, 22, 18, 18, 16, 12, 12, 14, 16, 18, 18, 18, 18, 18, 20, 20, 18],
        ),
        Sheet(
            "summary",
            _summary_rows(baseline_csv, live_summary_path, live_summary, merged_rows, baseline_rows, live_rows),
            [28, 96],
        ),
    ]
    _write_xlsx(sheets, out_xlsx)

    print("rate_scan_xlsx=%s" % out_xlsx)
    print("max_zero_loss_pps=%s" % analysis["max_zero_loss_pps"])
    print("first_overload_pps=%s" % analysis["first_overload_pps"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
