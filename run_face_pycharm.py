# -*- coding: utf-8 -*-
"""
PyCharm launcher for the face-recognition side.

Keep this file in an ASCII-only path. PyCharm sometimes crashes native OpenCV/
Conda DLL loading before the target script starts when the script path contains
Chinese characters or when the base Conda PATH leaks into the run environment.
"""

import os
import runpy
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent
FACE_DIR = ROOT_DIR / "深度学习端代码"
FACE_SCRIPT = FACE_DIR / "face.py"
LOG_PATH = FACE_DIR / "face_startup.log"


def launcher_log(message: str) -> None:
    try:
        with LOG_PATH.open("a", encoding="utf-8") as log_file:
            log_file.write(f"launcher {message}\n")
    except Exception:
        pass


def configure_environment() -> None:
    conda_prefix = Path(sys.executable).resolve().parent
    os.environ["PYTHONUTF8"] = "1"
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CONDA_PREFIX"] = str(conda_prefix)
    os.environ["CONDA_DEFAULT_ENV"] = conda_prefix.name

    preferred_paths = [
        conda_prefix,
        conda_prefix / "Scripts",
        conda_prefix / "Library" / "bin",
        conda_prefix / "Library" / "mingw-w64" / "bin",
        conda_prefix / "Library" / "usr" / "bin",
    ]

    cleaned_paths = []
    for part in os.environ.get("PATH", "").split(os.pathsep):
        normalized = part.rstrip("\\/").lower()
        if normalized.startswith(r"e:\anaconda3".lower()):
            continue
        cleaned_paths.append(part)

    os.environ["PATH"] = os.pathsep.join(
        [str(path) for path in preferred_paths if path.exists()] + cleaned_paths
    )

    qt_plugin_dir = conda_prefix / "Library" / "plugins"
    qt_platform_dir = qt_plugin_dir / "platforms"
    if qt_plugin_dir.exists():
        os.environ["QT_PLUGIN_PATH"] = str(qt_plugin_dir)
    if qt_platform_dir.exists():
        os.environ["QT_QPA_PLATFORM_PLUGIN_PATH"] = str(qt_platform_dir)

    launcher_log(f"python={sys.executable}")
    launcher_log(f"cwd={FACE_DIR}")
    launcher_log(f"script={FACE_SCRIPT}")
    launcher_log(f"CONDA_PREFIX={os.environ.get('CONDA_PREFIX', '')}")


def main() -> None:
    configure_environment()
    os.chdir(FACE_DIR)
    sys.path.insert(0, str(FACE_DIR))
    runpy.run_path(str(FACE_SCRIPT), run_name="__main__")


if __name__ == "__main__":
    main()
