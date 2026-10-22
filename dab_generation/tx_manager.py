"""
TX manager: starts and stops the DAB transmit scripts in WSL.

Each GUI slot (currently TX-1) runs one script from wsl/dab_tools/scripts/
via "wsl bash -lc ..." and forwards its output to the GUI log.

random : transmit the active ETI file (tx_random.sh)
file   : build an ETI from an audio file and transmit it (tx_file.sh)
record : offline generation of a baseband IQ file, no SDR (tx_record.sh)
"""

import subprocess
import threading
from dataclasses import dataclass

# -------------------------
# Frequency presets (GUI): DAB Band III channels 5A-13F
# -------------------------
PRESETS_HZ = {
    # Test frequency outside Band III (not a DAB channel)
    "TEST (860.000 MHz)": 860_000_000,

    "5A (174.928 MHz)": 174_928_000,
    "5B (176.640 MHz)": 176_640_000,
    "5C (178.352 MHz)": 178_352_000,
    "5D (180.064 MHz)": 180_064_000,

    "6A (181.936 MHz)": 181_936_000,
    "6B (183.648 MHz)": 183_648_000,
    "6C (185.360 MHz)": 185_360_000,
    "6D (187.072 MHz)": 187_072_000,

    "7A (188.928 MHz)": 188_928_000,
    "7B (190.640 MHz)": 190_640_000,
    "7C (192.352 MHz)": 192_352_000,
    "7D (194.064 MHz)": 194_064_000,

    "8A (195.936 MHz)": 195_936_000,
    "8B (197.648 MHz)": 197_648_000,
    "8C (199.360 MHz)": 199_360_000,
    "8D (201.072 MHz)": 201_072_000,

    "9A (202.928 MHz)": 202_928_000,
    "9B (204.640 MHz)": 204_640_000,
    "9C (206.352 MHz)": 206_352_000,
    "9D (208.064 MHz)": 208_064_000,

    "10A (209.936 MHz)": 209_936_000,
    "10B (211.648 MHz)": 211_648_000,
    "10C (213.360 MHz)": 213_360_000,
    "10D (215.072 MHz)": 215_072_000,

    "11A (216.928 MHz)": 216_928_000,
    "11B (218.640 MHz)": 218_640_000,
    "11C (220.352 MHz)": 220_352_000,
    "11D (222.064 MHz)": 222_064_000,

    "12A (223.936 MHz)": 223_936_000,
    "12B (225.648 MHz)": 225_648_000,
    "12C (227.360 MHz)": 227_360_000,
    "12D (229.072 MHz)": 229_072_000,

    "13A (230.784 MHz)": 230_784_000,
    "13B (232.496 MHz)": 232_496_000,
    "13C (234.208 MHz)": 234_208_000,
    "13D (235.776 MHz)": 235_776_000,
    "13E (237.488 MHz)": 237_488_000,
    "13F (239.200 MHz)": 239_200_000,
}

# -------------------------
# Config object from UI
# -------------------------
@dataclass
class TxSlotConfig:
    """Settings of one transmit slot, collected from the GUI."""
    uri: str
    freq_hz: int
    gain_db: float
    mode: str              # "random" | "file" | "record"
    audio_path: str = ""
    iq_output_path: str = ""
    label: str = "MediComm-DAB"
    bitrate: int = 120
    sr: int = 48000
    ch: int = 2
    loop: int = 0
    duration_s: int = 0    # 0 = unlimited, -1 = track duration / full file (record)


def _bash_quote(value: str) -> str:
    """Quote a string for safe use inside a bash command line."""
    value = value or ""
    return "'" + value.replace("'", "'\"'\"'") + "'"


def _win_to_wsl(path: str) -> str:
    """Convert a Windows path (C:\\... or C:/...) to its WSL path (/mnt/c/...)."""
    if not path:
        return path

    p = path.replace("\\", "/")

    if len(p) >= 3 and p[1] == ":" and p[2] == "/":
        drive = p[0].lower()
        rest = p[3:]
        return f"/mnt/{drive}/{rest}"

    return p


# -------------------------
# TX Manager
# -------------------------
class TxManager:
    """Runs one WSL transmit process per slot and streams its output to the GUI."""

    def __init__(self, signals, wsl_project_dir):
        self.signals = signals
        self.wsl_dir = wsl_project_dir
        self.procs = {}  # slot -> subprocess

    def is_running(self, slot):
        p = self.procs.get(slot)
        return p is not None and p.poll() is None

    def stop(self, slot):
        p = self.procs.get(slot)
        if p and p.poll() is None:
            p.terminate()
            self.signals.log_line.emit(slot, "Stopped.")
        self.procs.pop(slot, None)

    def restart(self, slot, cfg):
        self.stop(slot)
        self.start(slot, cfg)

    def start(self, slot, cfg: TxSlotConfig):
        """Validate the settings, build the WSL command and start it."""
        is_record = (cfg.mode == "record")
        is_file = (cfg.mode == "file")
        is_random = (cfg.mode == "random")

        if not is_record and not cfg.uri:
            self.signals.log_line.emit(slot, "ERROR: Pluto URI is empty.")
            return

        if (is_file or is_record) and not cfg.audio_path:
            self.signals.log_line.emit(slot, "ERROR: Audio file is not selected.")
            return

        if is_record and (not cfg.iq_output_path or cfg.iq_output_path.strip() == "(none)"):
            self.signals.log_line.emit(slot, "ERROR: IQ output path is not selected.")
            return

        # Paths selected in the Windows GUI are converted to WSL paths
        audio_wsl = _win_to_wsl(cfg.audio_path)
        iq_wsl = _win_to_wsl(cfg.iq_output_path)

        if is_random:
            cmd = (
                f"cd {_bash_quote(self.wsl_dir)} && "
                f"./scripts/tx_random.sh "
                f"{_bash_quote(cfg.uri)} "
                f"{cfg.freq_hz} "
                f"{cfg.gain_db} "
                f"{cfg.loop} "
                f"{cfg.duration_s}"
            )

        elif is_file:
            cmd = (
                f"cd {_bash_quote(self.wsl_dir)} && "
                f"./scripts/tx_file.sh "
                f"{_bash_quote(audio_wsl)} "
                f"{_bash_quote(cfg.label)} "
                f"{cfg.bitrate} "
                f"{cfg.sr} "
                f"{cfg.ch} "
                f"{_bash_quote(cfg.uri)} "
                f"{cfg.freq_hz} "
                f"{cfg.gain_db} "
                f"{cfg.loop} "
                f"{cfg.duration_s}"
            )

        elif is_record:
            cmd = (
                f"cd {_bash_quote(self.wsl_dir)} && "
                f"bash ./scripts/tx_record.sh "
                f"{_bash_quote(audio_wsl)} "
                f"{_bash_quote(cfg.label)} "
                f"{cfg.bitrate} "
                f"{cfg.sr} "
                f"{cfg.ch} "
                f"{cfg.freq_hz} "
                f"{_bash_quote(iq_wsl)}"
            )

        else:
            self.signals.log_line.emit(slot, f"ERROR: Unsupported mode: {cfg.mode}")
            return

        full_cmd = ["wsl", "bash", "-lc", cmd]
        self.signals.log_line.emit(slot, f"$ {cmd}")

        proc = subprocess.Popen(
            full_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )
        self.procs[slot] = proc

        # Forward the script output to the GUI log (background thread)
        def reader():
            for line in proc.stdout:
                line = line.rstrip()
                if line:
                    self.signals.log_line.emit(slot, line)
            self.signals.log_line.emit(slot, "Terminated.")

        threading.Thread(target=reader, daemon=True).start()
