from __future__ import annotations

from pathlib import Path

try:
    from torch import nn
except ModuleNotFoundError:  # pragma: no cover - environment dependent
    nn = None


DATASET_DIR = Path(__file__).resolve().parents[1]
RAW_DIR = DATASET_DIR / "raw"
INTERMEDIATE_DIR = DATASET_DIR / "intermediate"
MODELS_DIR = DATASET_DIR / "models"
EXPORT_DIR = DATASET_DIR / "export"

DEFAULT_INPUT_XLSX = INTERMEDIATE_DIR / "labeled_5s.xlsx"
DEFAULT_INPUT_SHEET = "labeled_5s_samples"
DEFAULT_LABEL_COL = "road_state_label"
DEFAULT_MODEL_DIR = MODELS_DIR / "mlp_5s_output"
DEFAULT_MANIFEST_PATH = EXPORT_DIR / "rsu_ann_model_int16.json"
DEFAULT_MANIFEST_REPORT_PATH = EXPORT_DIR / "rsu_ann_model_int16.report.json"

FEATURE_COLS = [
    "win_vehicle_count",
    "win_speed_mean",
    "win_speed_std",
    "win_speed_p10",
    "win_speed_p50",
    "win_speed_p90",
    "win_speed_min",
    "win_low_speed_ratio",
    "win_near_stop_ratio",
    "win_stop_vehicle_count",
    "win_acc_mean",
    "win_acc_std",
    "win_acc_min",
    "win_hard_brake_ratio",
    "win_speed_drop_ratio",
    "win_time_headway_mean",
    "win_time_headway_p10",
    "win_short_headway_ratio",
    "win_space_headway_mean",
    "win_space_headway_p10",
]

LABEL_ORDER = ["Free-flow", "Slow", "Congested", "Incident-risk"]

HIDDEN_DIM_1 = 32
HIDDEN_DIM_2 = 16


if nn is None:  # pragma: no cover - environment dependent
    class SmallMLP:  # type: ignore[no-redef]
        def __init__(self, *args, **kwargs):
            raise RuntimeError("torch is required to construct SmallMLP")
else:
    class SmallMLP(nn.Module):  # type: ignore[no-redef]
        def __init__(self, in_dim: int, num_classes: int, dropout: float = 0.2):
            super().__init__()
            self.net = nn.Sequential(
                nn.Linear(in_dim, HIDDEN_DIM_1),
                nn.ReLU(),
                nn.Dropout(dropout),
                nn.Linear(HIDDEN_DIM_1, HIDDEN_DIM_2),
                nn.ReLU(),
                nn.Dropout(dropout),
                nn.Linear(HIDDEN_DIM_2, num_classes),
            )

        def forward(self, x):
            return self.net(x)


def labels_from_mapping(label_to_id: dict[str, int]) -> list[str]:
    return [label for label, _ in sorted(label_to_id.items(), key=lambda item: int(item[1]))]


def ensure_parent_dir(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    return path
