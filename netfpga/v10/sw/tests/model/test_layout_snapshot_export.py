from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


SW_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = SW_DIR.parent

_EXPORT_SPEC = importlib.util.spec_from_file_location(
    "layout_snapshot_export_module",
    ROOT_DIR / "scripts" / "asic" / "export_layout_snapshot.py",
)
layout_snapshot_export = importlib.util.module_from_spec(_EXPORT_SPEC)
sys.modules[_EXPORT_SPEC.name] = layout_snapshot_export
assert _EXPORT_SPEC.loader is not None
_EXPORT_SPEC.loader.exec_module(layout_snapshot_export)


class LayoutSnapshotExportTests(unittest.TestCase):
    def test_parse_lef_sizes_extracts_macro_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            lef_path = Path(tmpdir) / "sample.lef"
            lef_path.write_text(
                "\n".join(
                    [
                        "VERSION 5.8 ;",
                        "MACRO DEMO_MACRO",
                        "  CLASS BLOCK ;",
                        "  SIZE 12.5 BY 7.0 ;",
                        "END DEMO_MACRO",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            sizes = layout_snapshot_export._parse_lef_sizes([lef_path])

        self.assertEqual(sizes["DEMO_MACRO"], (12.5, 7.0))

    def test_parse_def_design_extracts_units_diearea_and_component(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            def_path = Path(tmpdir) / "sample.def"
            def_path.write_text(
                "\n".join(
                    [
                        "VERSION 5.8 ;",
                        "DIVIDERCHAR \"/\" ;",
                        "BUSBITCHARS \"[]\" ;",
                        "DESIGN demo ;",
                        "UNITS DISTANCE MICRONS 2000 ;",
                        "DIEAREA ( 0 0 ) ( 1000 800 ) ;",
                        "COMPONENTS 1 ;",
                        "- U0 DEMO_MACRO + PLACED ( 100 120 ) N ;",
                        "END COMPONENTS",
                        "END DESIGN",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            design = layout_snapshot_export._parse_def_design(def_path)

        self.assertEqual(design.dbu_per_micron, 2000)
        self.assertEqual(design.diearea_dbu, (0, 0, 1000, 800))
        self.assertEqual(len(design.components), 1)
        self.assertEqual(design.components[0].master, "DEMO_MACRO")
        self.assertEqual(design.components[0].x_dbu, 100)

    def test_render_preview_writes_png(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            design = layout_snapshot_export.DefDesign(
                def_path=Path(tmpdir) / "sample.def",
                dbu_per_micron=1000,
                diearea_dbu=(0, 0, 10000, 8000),
                components=[
                    layout_snapshot_export.PlacedComponent("MAC0", "BIG_MACRO", 1000, 1000, "N"),
                    layout_snapshot_export.PlacedComponent("U0", "STD_CELL", 500, 500, "N"),
                    layout_snapshot_export.PlacedComponent("U1", "STD_CELL", 520, 500, "N"),
                ],
            )
            sizes = {
                "BIG_MACRO": (4.0, 3.0),
                "STD_CELL": (0.5, 1.0),
            }
            out_path = Path(tmpdir) / "preview.png"

            summary = layout_snapshot_export._render_preview(design, sizes, out_path, image_width_px=800)

            self.assertEqual(summary["status"], "ok")
            self.assertTrue(out_path.exists())
            with Image.open(out_path) as image:
                self.assertGreater(image.size[0], 100)
                self.assertGreater(image.size[1], 100)


if __name__ == "__main__":
    unittest.main()
