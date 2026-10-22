"""
DAB TX GUI - entry point (run on Windows).

PySide6 GUI for the DAB transmit chain running in WSL:

    audio -> ODR-AudioEnc -> ODR-DabMux (ETI) -> ODR-DabMod -> ADALM-PLUTO
                                                     |
                                                     +-> IQ file (.cf32)

The GUI only starts the scripts in wsl/dab_tools/scripts/ (tx_manager.py);
all signal processing is done by the ODR tools.

Usage:
    python main.py            (or run_gui.bat / run_gui.ps1)

Set DAB_WSL_DIR to override the WSL path of wsl/dab_tools.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

from PySide6.QtWidgets import QApplication

from tx_manager import TxManager, _win_to_wsl
from ui_main import MainWindow, UiSignals

# WSL path of the folder that contains make_eti.sh, run_dabmod_tx.sh,
# configs/ and scripts/.
WSL_PROJECT_DIR = os.environ.get(
    "DAB_WSL_DIR",
    _win_to_wsl(str(Path(__file__).resolve().parent / "wsl" / "dab_tools")),
)


def scan_plutos_by_ip_sweep():
    """Ping 192.168.0.1 ... 192.168.20.1 and list the addresses that answer.

    A PlutoSDR connected over USB appears as a network device, by default
    at 192.168.2.1. The result is informational: the Pluto URI can always
    be typed in the GUI (default ip:192.168.2.1).
    """
    found = []
    for x in range(0, 21):
        ip = f"192.168.{x}.1"
        try:
            out = subprocess.check_output(
                ["ping", "-n", "1", "-w", "150", ip],   # Windows ping syntax
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="ignore",
            )
            if re.search(r"TTL=\d+", out, re.IGNORECASE):
                found.append({"serial": "UNKNOWN", "uri": f"ip:{ip}"})
        except Exception:
            pass
    return found


def _apply_theme(app):
    """Load the dark Qt style sheet (ui_style.qss) if it exists."""
    try:
        qss_path = Path(__file__).with_name("ui_style.qss")
        if qss_path.exists():
            app.setStyleSheet(qss_path.read_text(encoding="utf-8"))
    except Exception:
        pass


def main():
    app = QApplication(sys.argv)
    _apply_theme(app)

    signals = UiSignals()
    plutos_found = scan_plutos_by_ip_sweep()

    tx_manager = TxManager(signals, WSL_PROJECT_DIR)
    win = MainWindow(tx_manager, signals, plutos_found)

    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
