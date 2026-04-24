from __future__ import annotations

from pathlib import Path


SW_DIR = Path(__file__).resolve().parents[1]
ROOT_DIR = SW_DIR.parent


def write_fake_annctl(path: Path, env_var: str = "ANNCTL_LOG") -> None:
    path.write_text(
        "\n".join(
            [
                "#!/usr/bin/perl",
                "use strict;",
                "use warnings;",
                f"my $log_path = $ENV{{'{env_var}'}} or die 'missing {env_var}';",
                "open my $fh, '>>', $log_path or die $!;",
                "print {$fh} join(' ', @ARGV), \"\\n\";",
                "close $fh or die $!;",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

