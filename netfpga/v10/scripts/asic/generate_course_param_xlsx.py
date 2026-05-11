#!/usr/bin/env python3
"""Generate a simple FPGA/ASIC course-parameter Excel workbook under pd/."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence
from xml.sax.saxutils import escape
import zipfile


REPO_ROOT = Path(__file__).resolve().parents[2]
PD_ROOT = REPO_ROOT / "pd"
FPGA_SRP = PD_ROOT / "fpga_report" / "nf2_top.srp"
FPGA_TWR = PD_ROOT / "fpga_report" / "nf2_top_par.twr"
ASIC_JSON = PD_ROOT / "asic_report" / "eval" / "user_top_eval" / "user_top_eval.json"
OUTPUT_XLSX = PD_ROOT / "fpga_asic_course_params.xlsx"


@dataclass
class Sheet:
    name: str
    rows: List[List[object]]
    widths: Sequence[int]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def extract_one(pattern: str, text: str, cast=str):
    match = re.search(pattern, text, flags=re.S)
    if not match:
        return None
    return cast(match.group(1))


def extract_two(pattern: str, text: str, cast=str):
    match = re.search(pattern, text, flags=re.S)
    if not match:
        return None, None
    return cast(match.group(1)), cast(match.group(2))


def load_fpga_data() -> dict:
    srp = read_text(FPGA_SRP) if FPGA_SRP.exists() else ""
    twr = read_text(FPGA_TWR) if FPGA_TWR.exists() else ""

    slices_used, slices_total = extract_two(r"Number of Slices:\s+(\d+)\s+out of\s+(\d+)", srp, int)
    ffs_used, ffs_total = extract_two(r"Number of Slice Flip Flops:\s+(\d+)\s+out of\s+(\d+)", srp, int)
    luts_used, luts_total = extract_two(r"Number of 4 input LUTs:\s+(\d+)\s+out of\s+(\d+)", srp, int)
    brams_used, brams_total = extract_two(r"Number of BRAMs:\s+(\d+)\s+out of\s+(\d+)", srp, int)
    mults_used, mults_total = extract_two(r"Number of MULT18X18s:\s+(\d+)\s+out of\s+(\d+)", srp, int)
    synth_period, synth_fmax = extract_two(r"Minimum period:\s*([0-9.]+)ns \(Maximum Frequency:\s*([0-9.]+)MHz\)", srp, float)
    impl_period, impl_fmax = extract_two(r"Minimum period:\s*([0-9.]+)ns\s+\(Maximum frequency:\s*([0-9.]+)MHz\)", twr, float)

    return {
        "device": extract_one(r"Selected Device\s*:\s*(\S+)", srp),
        "slices_used": slices_used,
        "slices_total": slices_total,
        "ffs_used": ffs_used,
        "ffs_total": ffs_total,
        "luts_used": luts_used,
        "luts_total": luts_total,
        "brams_used": brams_used,
        "brams_total": brams_total,
        "mults_used": mults_used,
        "mults_total": mults_total,
        "synth_period_ns": synth_period,
        "synth_fmax_mhz": synth_fmax,
        "impl_period_ns": impl_period,
        "impl_fmax_mhz": impl_fmax,
        "power_w": None,
    }


def load_asic_data() -> dict:
    if not ASIC_JSON.exists():
        return {}
    data = json.loads(ASIC_JSON.read_text(encoding="utf-8"))
    return {
        "design_name": data.get("design_name"),
        "top_module": data.get("top_module"),
        "evaluation_scope": data.get("evaluation_scope"),
        "artifact_root": data.get("artifact_root"),
        "target_ns": data.get("clock_constraints", [{}])[0].get("target_ns"),
        "memory_bits_total": data.get("memory_bits_total"),
        "included_module_count": len(data.get("included_modules", [])),
        "area_status": data.get("area_summary", {}).get("status"),
        "timing_status": data.get("timing_summary", {}).get("status"),
        "logic_area_est": data.get("area_summary", {}).get("logic_area_est"),
        "seq_area_est": data.get("area_summary", {}).get("seq_area_est"),
        "total_area_est": data.get("area_summary", {}).get("total_area_est"),
        "power_mw": None,
    }


def as_text(value: object) -> str:
    if value is None:
        return ""
    return str(value)


def build_summary_sheet(fpga: dict, asic: dict) -> Sheet:
    rows = [
        ["Category", "Parameter", "FPGA", "ASIC", "Unit", "Notes"],
        ["Project", "Design boundary", "nf2_top whole board design", as_text(asic.get("top_module")), "-", "FPGA is full board; ASIC currently evaluates user_top only"],
        ["Project", "Current status", "Implemented on NetFPGA", "Static evaluation only", "-", "ASIC netlist/area/power not generated yet"],
        ["Clock", "Target / measured frequency", as_text(fpga.get("impl_fmax_mhz")), "", "MHz", "FPGA uses implemented timing result"],
        ["Clock", "Minimum period", as_text(fpga.get("impl_period_ns")), as_text(asic.get("target_ns")), "ns", "ASIC column is current target constraint"],
        ["Area", "Primary area metric", as_text(fpga.get("slices_used")), as_text(asic.get("total_area_est")) or "TBD", "slices / um^2", "ASIC area needs Yosys + liberty"],
        ["Area", "Logic area detail", as_text(fpga.get("luts_used")), as_text(asic.get("logic_area_est")) or "TBD", "LUTs / um^2", "Course-level coarse comparison"],
        ["Area", "Sequential area detail", as_text(fpga.get("ffs_used")), as_text(asic.get("seq_area_est")) or "TBD", "FFs / um^2", "ASIC sequential area not available yet"],
        ["Area", "Memory resource", as_text(fpga.get("brams_used")), as_text(asic.get("memory_bits_total")), "BRAMs / bits", "ASIC side uses total memory bits"],
        ["Area", "Multiplier / DSP resource", as_text(fpga.get("mults_used")), "N/A", "count", "ASIC side will map into standard cells/macros"],
        ["Power", "Estimated total power", as_text(fpga.get("power_w")) or "TBD", as_text(asic.get("power_mw")) or "TBD", "W / mW", "No trustworthy power report exists yet"],
    ]
    return Sheet("Summary", rows, [14, 26, 24, 24, 14, 48])


def build_fpga_sheet(fpga: dict) -> Sheet:
    rows = [
        ["Parameter", "Value", "Unit", "Source / Notes"],
        ["Device", as_text(fpga.get("device")), "-", repo_rel(FPGA_SRP)],
        ["Slices used", as_text(fpga.get("slices_used")), "count", "Area proxy used in course table"],
        ["Slices total", as_text(fpga.get("slices_total")), "count", ""],
        ["Slice FFs used", as_text(fpga.get("ffs_used")), "count", ""],
        ["Slice FFs total", as_text(fpga.get("ffs_total")), "count", ""],
        ["LUTs used", as_text(fpga.get("luts_used")), "count", ""],
        ["LUTs total", as_text(fpga.get("luts_total")), "count", ""],
        ["BRAMs used", as_text(fpga.get("brams_used")), "count", ""],
        ["BRAMs total", as_text(fpga.get("brams_total")), "count", ""],
        ["MULT18X18 used", as_text(fpga.get("mults_used")), "count", ""],
        ["MULT18X18 total", as_text(fpga.get("mults_total")), "count", ""],
        ["Synthesis min period", as_text(fpga.get("synth_period_ns")), "ns", repo_rel(FPGA_SRP)],
        ["Synthesis Fmax", as_text(fpga.get("synth_fmax_mhz")), "MHz", repo_rel(FPGA_SRP)],
        ["Implemented min period", as_text(fpga.get("impl_period_ns")), "ns", repo_rel(FPGA_TWR)],
        ["Implemented Fmax", as_text(fpga.get("impl_fmax_mhz")), "MHz", repo_rel(FPGA_TWR)],
        ["Total power", as_text(fpga.get("power_w")) or "TBD", "W", "No FPGA power report found under pd/fpga_report"],
    ]
    return Sheet("FPGA", rows, [24, 18, 12, 44])


def build_asic_sheet(asic: dict) -> Sheet:
    rows = [
        ["Parameter", "Value", "Unit", "Source / Notes"],
        ["Design name", as_text(asic.get("design_name")), "-", repo_rel(ASIC_JSON)],
        ["Top module", as_text(asic.get("top_module")), "-", ""],
        ["Evaluation scope", as_text(asic.get("evaluation_scope")), "-", ""],
        ["Artifact root", as_text(asic.get("artifact_root")), "-", ""],
        ["Included module count", as_text(asic.get("included_module_count")), "count", ""],
        ["Target clock period", as_text(asic.get("target_ns")), "ns", "Current constraint target only"],
        ["Total memory bits", as_text(asic.get("memory_bits_total")), "bits", "Available now from static hierarchy scan"],
        ["Total area", as_text(asic.get("total_area_est")) or "TBD", "um^2", as_text(asic.get("area_status"))],
        ["Logic area", as_text(asic.get("logic_area_est")) or "TBD", "um^2", as_text(asic.get("area_status"))],
        ["Sequential area", as_text(asic.get("seq_area_est")) or "TBD", "um^2", as_text(asic.get("area_status"))],
        ["Total power", as_text(asic.get("power_mw")) or "TBD", "mW", "Need synthesis / activity / PNR flow"],
        ["Timing status", as_text(asic.get("timing_status")), "-", "No STA result yet"],
    ]
    return Sheet("ASIC", rows, [24, 20, 12, 44])


def build_notes_sheet() -> Sheet:
    rows = [
        ["Note", "Detail"],
        ["Course scope", "Keep only easy-to-obtain metrics: area proxy, timing proxy, and power placeholders."],
        ["FPGA area", "Use slices/LUTs/FFs/BRAMs/MULT18X18 directly from pd/fpga_report."],
        ["ASIC area", "Only fill true um^2 area after Yosys synthesis with a valid liberty."],
        ["Power", "Both FPGA and ASIC power are marked TBD because no trustworthy power reports exist yet."],
        ["Boundary mismatch", "FPGA numbers come from full nf2_top board design, while ASIC currently targets user_top."],
        ["Current ASIC state", "Static evaluation package exists, but no Yosys netlist / no OpenROAD results yet."],
    ]
    return Sheet("Notes", rows, [20, 96])


def repo_rel(path: Path) -> str:
    return str(path.relative_to(REPO_ROOT))


def excel_column_name(index: int) -> str:
    result = []
    while index > 0:
        index, rem = divmod(index - 1, 26)
        result.append(chr(65 + rem))
    return "".join(reversed(result))


def sheet_xml(sheet: Sheet) -> str:
    rows_xml = []
    for row_idx, row in enumerate(sheet.rows, start=1):
        cells = []
        for col_idx, value in enumerate(row, start=1):
            ref = f"{excel_column_name(col_idx)}{row_idx}"
            text = escape(as_text(value))
            style = ' s="1"' if row_idx == 1 else ""
            cells.append(f'<c r="{ref}" t="inlineStr"{style}><is><t>{text}</t></is></c>')
        rows_xml.append(f'<row r="{row_idx}">{"".join(cells)}</row>')
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
        f'{cols_xml(sheet.widths)}'
        '<sheetData>'
        f'{"".join(rows_xml)}'
        '</sheetData>'
        '</worksheet>'
    )


def cols_xml(widths: Sequence[int]) -> str:
    col_entries = []
    for idx, width in enumerate(widths, start=1):
        col_entries.append(
            f'<col min="{idx}" max="{idx}" width="{width}" customWidth="1"/>'
        )
    return f'<cols>{"".join(col_entries)}</cols>'


def workbook_xml(sheets: Iterable[Sheet]) -> str:
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


def workbook_rels_xml(sheet_count: int) -> str:
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


def root_rels_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/>'
        '</Relationships>'
    )


def content_types_xml(sheet_count: int) -> str:
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


def styles_xml() -> str:
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


def write_xlsx(sheets: List[Sheet], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", content_types_xml(len(sheets)))
        zf.writestr("_rels/.rels", root_rels_xml())
        zf.writestr("xl/workbook.xml", workbook_xml(sheets))
        zf.writestr("xl/_rels/workbook.xml.rels", workbook_rels_xml(len(sheets)))
        zf.writestr("xl/styles.xml", styles_xml())
        for idx, sheet in enumerate(sheets, start=1):
            zf.writestr(f"xl/worksheets/sheet{idx}.xml", sheet_xml(sheet))


def main() -> int:
    fpga = load_fpga_data()
    asic = load_asic_data()
    sheets = [
        build_summary_sheet(fpga, asic),
        build_fpga_sheet(fpga),
        build_asic_sheet(asic),
        build_notes_sheet(),
    ]
    write_xlsx(sheets, OUTPUT_XLSX)
    print(f"wrote {OUTPUT_XLSX}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
