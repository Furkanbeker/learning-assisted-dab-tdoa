#!/usr/bin/env bash
# =============================================================================
# tx_file.sh  ("File" mode of the GUI)
#
# Builds an ETI file from an audio file (make_eti.sh), selects it as the
# active ETI (eti/myfirst.eti) and transmits it with the PlutoSDR
# (run_dabmod_tx.sh).
#
# Usage:
#   ./tx_file.sh AUDIO [LABEL] [BITRATE] [SR] [CH] URI FREQ_HZ GAIN_DB [LOOP] [DURATION_S]
#
#   DURATION_S = -1 uses the track duration (ffprobe). LOOP and DURATION_S
#   are passed to run_dabmod_tx.sh, which ignores them.
# =============================================================================
set -euo pipefail

AUDIO="${1:?audio}"
LABEL="${2:-MediComm-DAB}"
BITRATE="${3:-120}"
SR="${4:-48000}"
CH="${5:-2}"
URI="${6:?uri}"
FREQ="${7:?freq_hz}"
GAIN="${8:?gain_db}"
LOOP="${9:-0}"
DUR="${10:-0}"      # -1 = track duration

# Windows path -> WSL path
if [[ "$AUDIO" =~ ^[A-Za-z]:\\ ]]; then
  AUDIO="$(wslpath -u "$AUDIO")"
elif [[ "$AUDIO" =~ ^[A-Za-z]:/ ]]; then
  AUDIO_WIN="${AUDIO/\//\\}"
  AUDIO_WIN="${AUDIO_WIN//\//\\}"
  AUDIO="$(wslpath -u "$AUDIO_WIN")"
fi

# Work in the dab_tools folder (parent of scripts/)
cd "$(dirname "$0")/.."

# DUR = -1: use the track duration
if [[ "$DUR" == "-1" ]]; then
  command -v ffprobe >/dev/null || { echo "[ERROR] ffprobe missing"; exit 1; }
  DUR=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$AUDIO")
  DUR=${DUR%.*}   # integer seconds
  echo "[INFO] Track duration detected: ${DUR}s" >&2
fi

OUT="eti/render_$(date +%Y%m%d_%H%M%S).eti"
./make_eti.sh "$AUDIO" "$OUT" "$LABEL" "$BITRATE" "$SR" "$CH" 0

# Make the new ETI the active one
rm -f eti/myfirst.eti
ln -sf "$(basename "$OUT")" eti/myfirst.eti
echo "[OK] myfirst.eti -> $(readlink -f eti/myfirst.eti)"

./run_dabmod_tx.sh "$URI" "$FREQ" "$GAIN" "$LOOP" "$DUR"
