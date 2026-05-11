#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_DEF = ROOT_DIR / "pd" / "asic_report" / "pnr" / "user_top" / "results" / "user_top_postroute.def"
DEFAULT_OUTPUT_DIR = ROOT_DIR / "pd" / "asic_report" / "pnr" / "user_top" / "figures"
DEFAULT_OPENROAD = (
    Path.home()
    / "codex"
    / "third_party"
    / "OpenROAD-flow-scripts"
    / "tools"
    / "install"
    / "OpenROAD"
    / "bin"
    / "openroad"
)
DEFAULT_PLATFORM_ROOT = (
    Path.home() / "codex" / "third_party" / "OpenROAD-flow-scripts" / "flow" / "platforms" / "nangate45"
)
DEFAULT_SNAPSHOT_NAME = "user_top_postroute_layout.png"

FAKERAM_LEFS = [
    "fakeram45_1024x32.lef",
    "fakeram45_256x16.lef",
    "fakeram45_256x32.lef",
]
PLACEHOLDER_LEFS = [
    ROOT_DIR / "pd" / "asic_report" / "eval" / "user_top_eval" / "generated_macros" / "lef" / "placeholder_fifo_bram_256x72_dp.lef",
    ROOT_DIR / "pd" / "asic_report" / "eval" / "user_top_eval" / "generated_macros" / "lef" / "placeholder_gpu_shared_dmem_16384x64_dp.lef",
    ROOT_DIR / "pd" / "asic_report" / "eval" / "user_top_eval" / "generated_macros" / "lef" / "placeholder_mem_rf_64x64_1w2r.lef",
]
ORIENTATIONS_SWAP_WH = {"E", "W", "FE", "FW"}


@dataclass(frozen=True)
class PlacedComponent:
    name: str
    master: str
    x_dbu: int
    y_dbu: int
    orient: str


@dataclass(frozen=True)
class DefDesign:
    def_path: Path
    dbu_per_micron: int
    diearea_dbu: tuple[int, int, int, int]
    components: list[PlacedComponent]


def _fail(message: str) -> SystemExit:
    return SystemExit(message)


def _resolve_openroad_bin(explicit: str | None) -> Path | None:
    if explicit:
        path = Path(explicit).expanduser().resolve()
        return path if path.exists() else None
    if os.environ.get("OPENROAD_BIN"):
        path = Path(os.environ["OPENROAD_BIN"]).expanduser().resolve()
        if path.exists():
            return path
    resolved = shutil.which("openroad")
    if resolved:
        return Path(resolved).resolve()
    if DEFAULT_OPENROAD.exists():
        return DEFAULT_OPENROAD.resolve()
    return None


def _resolve_platform_root(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if not path.exists():
            raise _fail(f"ASIC platform root not found: {path}")
        return path
    if os.environ.get("ASIC_PLATFORM_ROOT"):
        path = Path(os.environ["ASIC_PLATFORM_ROOT"]).expanduser().resolve()
        if path.exists():
            return path
    if DEFAULT_PLATFORM_ROOT.exists():
        return DEFAULT_PLATFORM_ROOT.resolve()
    raise _fail(
        "Unable to resolve ASIC platform root. Set ASIC_PLATFORM_ROOT or use "
        "--platform-root."
    )


def _resolve_platform_inputs(platform_root: Path) -> dict[str, str]:
    tech_lef = Path(os.environ.get("ASIC_TECH_LEF", platform_root / "lef" / "NangateOpenCellLibrary.tech.lef"))
    stdcell_lef = Path(
        os.environ.get("ASIC_STD_CELL_LEF", platform_root / "lef" / "NangateOpenCellLibrary.macro.mod.lef")
    )
    liberty = Path(
        os.environ.get("ASIC_LIBERTY", platform_root / "lib" / "NangateOpenCellLibrary_typical.lib")
    )
    for path, label in (
        (tech_lef, "ASIC_TECH_LEF"),
        (stdcell_lef, "ASIC_STD_CELL_LEF"),
        (liberty, "ASIC_LIBERTY"),
    ):
        if not path.exists():
            raise _fail(f"{label} not found: {path}")
    return {
        "ASIC_PLATFORM_ROOT": str(platform_root),
        "ASIC_TECH_LEF": str(tech_lef.resolve()),
        "ASIC_STD_CELL_LEF": str(stdcell_lef.resolve()),
        "ASIC_LIBERTY": str(liberty.resolve()),
    }


def _collect_snapshot_lefs(platform_root: Path) -> list[Path]:
    lefs = []
    for name in FAKERAM_LEFS:
        path = (platform_root / "lef" / name).resolve()
        if not path.exists():
            raise _fail(f"Required fakeram LEF not found: {path}")
        lefs.append(path)
    for path in PLACEHOLDER_LEFS:
        resolved = path.resolve()
        if not resolved.exists():
            raise _fail(f"Required placeholder LEF not found: {resolved}")
        lefs.append(resolved)
    return lefs


def _parse_lef_sizes(lef_paths: list[Path]) -> dict[str, tuple[float, float]]:
    sizes: dict[str, tuple[float, float]] = {}
    macro_name: str | None = None
    size_pattern = re.compile(r"^\s*SIZE\s+([0-9.]+)\s+BY\s+([0-9.]+)\s*;", re.IGNORECASE)
    macro_pattern = re.compile(r"^\s*MACRO\s+(\S+)\s*$", re.IGNORECASE)
    end_pattern = re.compile(r"^\s*END\s+(\S+)\s*$", re.IGNORECASE)
    for lef_path in lef_paths:
        for line in lef_path.read_text(encoding="utf-8", errors="replace").splitlines():
            macro_match = macro_pattern.match(line)
            if macro_match:
                macro_name = macro_match.group(1)
                continue
            if macro_name is None:
                continue
            size_match = size_pattern.match(line)
            if size_match:
                sizes[macro_name] = (float(size_match.group(1)), float(size_match.group(2)))
                continue
            end_match = end_pattern.match(line)
            if end_match and end_match.group(1) == macro_name:
                macro_name = None
    if not sizes:
        raise _fail("No MACRO SIZE statements were parsed from the LEF inputs.")
    return sizes


def _parse_def_design(def_path: Path) -> DefDesign:
    dbu_per_micron: int | None = None
    diearea_dbu: tuple[int, int, int, int] | None = None
    components: list[PlacedComponent] = []
    in_components = False
    entry_lines: list[str] = []

    units_pattern = re.compile(r"^\s*UNITS\s+DISTANCE\s+MICRONS\s+(\d+)\s*;\s*$", re.IGNORECASE)
    diearea_pattern = re.compile(
        r"^\s*DIEAREA\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*;\s*$",
        re.IGNORECASE,
    )
    component_header = re.compile(r"^\s*COMPONENTS\s+\d+\s*;\s*$", re.IGNORECASE)
    end_components = re.compile(r"^\s*END\s+COMPONENTS\s*$", re.IGNORECASE)
    instance_pattern = re.compile(r"^-\s+(\S+)\s+(\S+)\b")
    placement_pattern = re.compile(
        r"\+\s+(?:PLACED|FIXED|COVER)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)",
        re.IGNORECASE,
    )

    for line in def_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if dbu_per_micron is None:
            match = units_pattern.match(line)
            if match:
                dbu_per_micron = int(match.group(1))
                continue
        if diearea_dbu is None:
            match = diearea_pattern.match(line)
            if match:
                diearea_dbu = tuple(int(match.group(index)) for index in range(1, 5))
                continue
        if component_header.match(line):
            in_components = True
            entry_lines.clear()
            continue
        if in_components and end_components.match(line):
            in_components = False
            entry_lines.clear()
            continue
        if not in_components:
            continue

        stripped = line.strip()
        if not stripped:
            continue
        entry_lines.append(stripped)
        if not stripped.endswith(";"):
            continue

        entry = " ".join(entry_lines)
        entry_lines.clear()
        instance_match = instance_pattern.match(entry)
        placement_match = placement_pattern.search(entry)
        if not instance_match or not placement_match:
            continue
        components.append(
            PlacedComponent(
                name=instance_match.group(1),
                master=instance_match.group(2),
                x_dbu=int(placement_match.group(1)),
                y_dbu=int(placement_match.group(2)),
                orient=placement_match.group(3),
            )
        )

    if dbu_per_micron is None:
        raise _fail(f"Failed to parse DEF units from {def_path}")
    if diearea_dbu is None:
        raise _fail(f"Failed to parse DIEAREA from {def_path}")
    if not components:
        raise _fail(f"Failed to parse placed components from {def_path}")
    return DefDesign(
        def_path=def_path.resolve(),
        dbu_per_micron=dbu_per_micron,
        diearea_dbu=diearea_dbu,
        components=components,
    )


def _swap_dimensions_if_needed(width_dbu: int, height_dbu: int, orient: str) -> tuple[int, int]:
    if orient.upper() in ORIENTATIONS_SWAP_WH:
        return height_dbu, width_dbu
    return width_dbu, height_dbu


def _is_macro(master: str, width_dbu: int, height_dbu: int, dbu_per_micron: int) -> bool:
    if master.startswith("placeholder_") or master.startswith("fakeram45_"):
        return True
    area_um2 = (width_dbu / dbu_per_micron) * (height_dbu / dbu_per_micron)
    return area_um2 >= 400.0


def _color_for_density(level: float) -> tuple[int, int, int]:
    level = max(0.0, min(1.0, level))
    base = (235, 241, 247)
    peak = (83, 125, 167)
    return tuple(int(base[index] + (peak[index] - base[index]) * level) for index in range(3))


def _render_preview(
    design: DefDesign,
    master_sizes_microns: dict[str, tuple[float, float]],
    out_path: Path,
    image_width_px: int,
) -> dict[str, object]:
    x0_dbu, y0_dbu, x1_dbu, y1_dbu = design.diearea_dbu
    die_width_dbu = max(1, x1_dbu - x0_dbu)
    die_height_dbu = max(1, y1_dbu - y0_dbu)
    image_height_px = max(480, round(image_width_px * die_height_dbu / die_width_dbu))
    margin_px = 32
    grid_width = max(240, min(900, image_width_px // 4))
    grid_height = max(180, round(grid_width * die_height_dbu / die_width_dbu))
    density = [0] * (grid_width * grid_height)
    macros: list[tuple[int, int, int, int, str]] = []

    dbu_per_micron = design.dbu_per_micron
    missing_masters = 0
    std_cells = 0

    def to_grid_x(value_dbu: int) -> int:
        ratio = (value_dbu - x0_dbu) / die_width_dbu
        return max(0, min(grid_width - 1, int(ratio * (grid_width - 1))))

    def to_grid_y(value_dbu: int) -> int:
        ratio = (value_dbu - y0_dbu) / die_height_dbu
        return max(0, min(grid_height - 1, int(ratio * (grid_height - 1))))

    for component in design.components:
        size = master_sizes_microns.get(component.master)
        if size is None:
            missing_masters += 1
            continue
        width_dbu = max(1, round(size[0] * dbu_per_micron))
        height_dbu = max(1, round(size[1] * dbu_per_micron))
        width_dbu, height_dbu = _swap_dimensions_if_needed(width_dbu, height_dbu, component.orient)
        if _is_macro(component.master, width_dbu, height_dbu, dbu_per_micron):
            macros.append(
                (
                    component.x_dbu,
                    component.y_dbu,
                    component.x_dbu + width_dbu,
                    component.y_dbu + height_dbu,
                    component.master,
                )
            )
            continue

        std_cells += 1
        gx0 = to_grid_x(component.x_dbu)
        gx1 = to_grid_x(component.x_dbu + width_dbu)
        gy0 = to_grid_y(component.y_dbu)
        gy1 = to_grid_y(component.y_dbu + height_dbu)
        for gy in range(min(gy0, gy1), max(gy0, gy1) + 1):
            row_offset = gy * grid_width
            for gx in range(min(gx0, gx1), max(gx0, gx1) + 1):
                density[row_offset + gx] += 1

    max_density = max(density) if density else 0

    image = Image.new("RGBA", (image_width_px + margin_px * 2, image_height_px + margin_px * 2 + 70), (250, 252, 255, 255))
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()
    die_box = (margin_px, margin_px, margin_px + image_width_px, margin_px + image_height_px)
    draw.rectangle(die_box, fill=(252, 253, 255, 255), outline=(38, 66, 102, 255), width=3)

    if max_density > 0:
        density_overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        density_draw = ImageDraw.Draw(density_overlay)
        bin_width = image_width_px / grid_width
        bin_height = image_height_px / grid_height
        for gy in range(grid_height):
            row_offset = gy * grid_width
            for gx in range(grid_width):
                value = density[row_offset + gx]
                if value <= 0:
                    continue
                level = math.sqrt(value / max_density)
                color = _color_for_density(level)
                left = margin_px + gx * bin_width
                right = margin_px + (gx + 1) * bin_width
                top = margin_px + image_height_px - (gy + 1) * bin_height
                bottom = margin_px + image_height_px - gy * bin_height
                density_draw.rectangle((left, top, right, bottom), fill=(*color, 150))
        image = Image.alpha_composite(image, density_overlay.filter(ImageFilter.BoxBlur(2.2)))
        draw = ImageDraw.Draw(image)

    def to_px_x(value_dbu: int) -> float:
        return margin_px + ((value_dbu - x0_dbu) / die_width_dbu) * image_width_px

    def to_px_y(value_dbu: int) -> float:
        return margin_px + image_height_px - ((value_dbu - y0_dbu) / die_height_dbu) * image_height_px

    for macro_x0, macro_y0, macro_x1, macro_y1, _master in macros:
        left = to_px_x(macro_x0)
        right = to_px_x(macro_x1)
        top = to_px_y(macro_y1)
        bottom = to_px_y(macro_y0)
        draw.rectangle((left, top, right, bottom), fill=(237, 156, 82, 255), outline=(148, 79, 20, 255), width=2)

    title = "user_top post-route DEF snapshot"
    subtitle = (
        f"std-cell density preview with macro overlay | placed components={len(design.components)} "
        f"| macros={len(macros)} | std-cells={std_cells}"
    )
    footer = f"source DEF: {design.def_path}"
    text_y = margin_px + image_height_px + 12
    draw.text((margin_px, text_y), title, fill=(17, 34, 68, 255), font=font)
    draw.text((margin_px, text_y + 18), subtitle, fill=(57, 74, 105, 255), font=font)
    draw.text((margin_px, text_y + 36), footer, fill=(90, 103, 127, 255), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(out_path)
    return {
        "status": "ok",
        "image_path": str(out_path.resolve()),
        "image_width_px": image.width,
        "image_height_px": image.height,
        "std_cell_count": std_cells,
        "macro_count": len(macros),
        "missing_master_count": missing_masters,
    }


def _write_openroad_tcl(
    tcl_path: Path,
    def_path: Path,
    out_png: Path,
    tech_lef: Path,
    stdcell_lef: Path,
    additional_lefs: list[Path],
    image_width_px: int,
) -> None:
    lines = [
        "# Auto-generated by scripts/asic/export_layout_snapshot.py",
        f"set def_file [file normalize {{{def_path}}}]",
        f"set out_png [file normalize {{{out_png}}}]",
        f"set tech_lef [file normalize {{{tech_lef}}}]",
        f"set stdcell_lef [file normalize {{{stdcell_lef}}}]",
        "read_lef $tech_lef",
        "read_lef $stdcell_lef",
    ]
    for lef_path in additional_lefs:
        lines.append(f"read_lef [file normalize {{{lef_path}}}]")
    lines.extend(
        [
            "read_def $def_file",
            "set block [[[ord::get_db] getChip] getBlock]",
            "set area [$block getDieArea]",
            "set xlo [$area xMin]",
            "set ylo [$area yMin]",
            "set xhi [$area xMax]",
            "set yhi [$area yMax]",
            "gui::fit",
            f"gui::save_image $out_png $xlo $ylo $xhi $yhi {image_width_px}",
            "puts \"snapshot_out=$out_png\"",
            "exit",
        ]
    )
    tcl_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _run_openroad_snapshot(
    openroad_bin: Path,
    tcl_path: Path,
    log_path: Path,
    platform_inputs: dict[str, str],
) -> dict[str, object]:
    env = os.environ.copy()
    env.update(platform_inputs)
    env["QT_QPA_PLATFORM"] = env.get("QT_QPA_PLATFORM", "offscreen")
    with tempfile.TemporaryDirectory(prefix="openroad_snapshot_runtime_") as runtime_dir:
        runtime_path = Path(runtime_dir)
        runtime_path.chmod(0o700)
        env["XDG_RUNTIME_DIR"] = str(runtime_path)
        process = subprocess.run(
            [str(openroad_bin), "-no_init", "-no_splash", "-gui", "-exit", str(tcl_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            cwd=str(ROOT_DIR),
        )
    log_path.write_text(process.stdout, encoding="utf-8")
    out_png = tcl_path.parent / "layout_snapshot_openroad.png"
    if process.returncode == 0 and out_png.exists() and out_png.stat().st_size > 0:
        return {
            "status": "ok",
            "log_path": str(log_path.resolve()),
            "image_path": str(out_png.resolve()),
            "openroad_bin": str(openroad_bin.resolve()),
            "returncode": process.returncode,
        }
    reason = "openroad_save_image_failed"
    if process.returncode != 0:
        reason = f"openroad_exit_{process.returncode}"
    return {
        "status": "warning",
        "reason": reason,
        "log_path": str(log_path.resolve()),
        "image_path": str(out_png.resolve()),
        "openroad_bin": str(openroad_bin.resolve()),
        "returncode": process.returncode,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Export a PPT-friendly layout snapshot from the final user_top DEF."
    )
    parser.add_argument(
        "--mode",
        choices=("auto", "openroad", "preview"),
        default="auto",
        help="auto tries OpenROAD first and falls back to a DEF preview; openroad requires a successful OpenROAD PNG; preview skips OpenROAD.",
    )
    parser.add_argument(
        "--def",
        dest="def_path",
        default=str(DEFAULT_DEF),
        help="Post-route DEF to visualize.",
    )
    parser.add_argument(
        "--out-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory for TCL/log/image outputs.",
    )
    parser.add_argument(
        "--openroad-bin",
        default=None,
        help="Optional OpenROAD binary override.",
    )
    parser.add_argument(
        "--platform-root",
        default=None,
        help="Optional Nangate45 platform root override.",
    )
    parser.add_argument(
        "--image-width-px",
        type=int,
        default=2200,
        help="Target width for the exported image.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    def_path = Path(args.def_path).expanduser().resolve()
    if not def_path.exists():
        raise _fail(f"DEF not found: {def_path}")
    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    platform_root = _resolve_platform_root(args.platform_root)
    platform_inputs = _resolve_platform_inputs(platform_root)
    additional_lefs = _collect_snapshot_lefs(platform_root)
    lef_sizes = _parse_lef_sizes(
        [Path(platform_inputs["ASIC_STD_CELL_LEF"]), *additional_lefs]
    )
    design = _parse_def_design(def_path)

    summary: dict[str, object] = {
        "mode": args.mode,
        "def_path": str(def_path),
        "out_dir": str(out_dir),
        "platform_root": str(platform_root),
        "openroad": None,
        "preview": None,
        "final_image": None,
    }

    openroad_png = out_dir / "layout_snapshot_openroad.png"
    preview_png = out_dir / "layout_snapshot_preview.png"
    final_png = out_dir / DEFAULT_SNAPSHOT_NAME

    if args.mode in {"auto", "openroad"}:
        openroad_bin = _resolve_openroad_bin(args.openroad_bin)
        if openroad_bin is None:
            if args.mode == "openroad":
                raise _fail("OpenROAD binary not found. Set OPENROAD_BIN or use --openroad-bin.")
            summary["openroad"] = {
                "status": "warning",
                "reason": "openroad_binary_not_found",
            }
        else:
            tcl_path = out_dir / "openroad_snapshot.tcl"
            log_path = out_dir / "openroad_snapshot.log"
            _write_openroad_tcl(
                tcl_path=tcl_path,
                def_path=def_path,
                out_png=openroad_png,
                tech_lef=Path(platform_inputs["ASIC_TECH_LEF"]),
                stdcell_lef=Path(platform_inputs["ASIC_STD_CELL_LEF"]),
                additional_lefs=additional_lefs,
                image_width_px=args.image_width_px,
            )
            summary["openroad"] = _run_openroad_snapshot(
                openroad_bin=openroad_bin,
                tcl_path=tcl_path,
                log_path=log_path,
                platform_inputs=platform_inputs,
            )
            if summary["openroad"]["status"] == "ok":
                shutil.copyfile(openroad_png, final_png)
                summary["final_image"] = str(final_png.resolve())

    if args.mode == "preview" or (args.mode == "auto" and summary["final_image"] is None):
        summary["preview"] = _render_preview(
            design=design,
            master_sizes_microns=lef_sizes,
            out_path=preview_png,
            image_width_px=args.image_width_px,
        )
        shutil.copyfile(preview_png, final_png)
        summary["final_image"] = str(final_png.resolve())

    summary_path = out_dir / "layout_snapshot_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    if summary["final_image"] is None:
        print(json.dumps(summary, indent=2))
        if args.mode == "openroad":
            return 2
        return 1

    print("=" * 100)
    print("Layout Snapshot Export")
    print("=" * 100)
    print(f"DEF         : {def_path}")
    print(f"Mode        : {args.mode}")
    print(f"Output Dir  : {out_dir}")
    print(f"Final Image : {summary['final_image']}")
    if summary["openroad"] is not None:
        print(f"OpenROAD    : {summary['openroad']['status']}")
        if summary["openroad"]["status"] != "ok":
            print(f"Reason      : {summary['openroad'].get('reason', 'n/a')}")
            log_path = summary["openroad"].get("log_path")
            if log_path:
                print(f"OpenROAD Log: {log_path}")
    if summary["preview"] is not None:
        print(f"Preview     : {summary['preview']['status']}")
        print(f"Preview PNG : {summary['preview']['image_path']}")
    print(f"Summary JSON: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
