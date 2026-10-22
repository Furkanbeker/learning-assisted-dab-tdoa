#!/usr/bin/env bash
# =============================================================================
# tx_record.sh  ("Record" mode of the GUI)
#
# Offline DAB Mode-I baseband IQ file from an audio file (no SDR needed).
# data/dab_iq/basic.cf32 was made this way (audio/basic.wav, label
# "MediComm-DAB", 120 kbps).
#
#   audio --ffmpeg--> 48 kHz stereo WAV --odr-audioenc--> .dabp
#         --odr-dabmux--> .eti --odr-dabmod--> complex float32 IQ (.cf32)
#
# The IQ is cut to audio duration + 0.8 s; a JSON metadata file with the
# same name is written next to it.
#
# Usage:
#   bash tx_record.sh <audio_path> <label> <bitrate> <sr> <ch> <freq_hz> <iq_output>
#
# Example (inside WSL, from wsl/dab_tools):
#   bash scripts/tx_record.sh ../../audio/basic.wav MediComm-DAB 120 48000 2 195936000 ./basic.cf32
#
# freq_hz is only stored in the metadata (the IQ is baseband). The ensemble
# carries the local time, so a regenerated file is not byte-identical.
# Intermediate files go to offline_record/ and eti/.
# =============================================================================
set -euo pipefail

if [ "$#" -lt 7 ]; then
    echo "Usage: tx_record.sh <audio_path> <label> <bitrate> <sr> <ch> <freq_hz> <iq_output>"
    exit 1
fi

AUDIO_PATH="$1"
LABEL="$2"
BITRATE="$3"
SR="$4"
CH="$5"
FREQ_HZ="$6"
IQ_OUTPUT="$7"

if [ -z "$IQ_OUTPUT" ] || [ "$IQ_OUTPUT" = "(none)" ]; then
    echo "[ERR] IQ output path is invalid"
    exit 3
fi

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$BASE_DIR/offline_record"
ETI_DIR="$BASE_DIR/eti"

mkdir -p "$WORK_DIR"
mkdir -p "$ETI_DIR"
mkdir -p "$(dirname "$IQ_OUTPUT")"

STAMP="$(date +%Y%m%d_%H%M%S)"

# Label without special characters, used in file names
SAN_LABEL="$(echo "$LABEL" | tr -cd '[:alnum:]_-' | cut -c1-16)"
if [ -z "$SAN_LABEL" ]; then
    SAN_LABEL="MediCommDAB"
fi

NORMALIZED_WAV="$WORK_DIR/${STAMP}_${SAN_LABEL}_48k.wav"
ENC_FILE="$WORK_DIR/${STAMP}_${SAN_LABEL}.dabp"
MUX_FILE="$WORK_DIR/${STAMP}_${SAN_LABEL}.mux"
ETI_FILE="$ETI_DIR/render_${STAMP}.eti"
META_FILE="${IQ_OUTPUT%.*}.json"

# DAB short label: at most 8 characters
SHORT_LABEL="$(echo "$LABEL" | tr -cd '[:alnum:]' | cut -c1-8)"
if [ -z "$SHORT_LABEL" ]; then
    SHORT_LABEL="MEDICOMM"
fi

echo "[REC] Offline IQ record mode"
echo "[REC] Audio input : $AUDIO_PATH"
echo "[REC] IQ output   : $IQ_OUTPUT"
echo "[REC] Label       : $LABEL"
echo "[REC] Bitrate     : $BITRATE kbps"
echo "[REC] Frequency   : $FREQ_HZ Hz"

for cmd in ffmpeg ffprobe odr-audioenc odr-dabmux odr-dabmod timeout python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERR] $cmd not found in WSL"
        exit 2
    fi
done

# 1) Normalize the audio to 48 kHz stereo 16-bit PCM
echo "[FFMPEG] Normalizing input to 48 kHz stereo WAV..."
ffmpeg -y -i "$AUDIO_PATH" -ar 48000 -ac 2 -c:a pcm_s16le "$NORMALIZED_WAV" >/dev/null 2>&1

AUDIO_DUR="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$NORMALIZED_WAV" | head -n1)"
if [ -z "$AUDIO_DUR" ]; then
    echo "[ERR] Could not determine normalized WAV duration."
    exit 6
fi

# Target IQ length: audio duration + 0.8 s (complex float32 = 8 bytes/sample)
TARGET_IQ_SECONDS="$(python3 -c "d=float('$AUDIO_DUR'); print(max(1.0, d+0.8))")"
TARGET_IQ_BYTES="$(python3 -c "d=float('$TARGET_IQ_SECONDS'); print(int(d*2048000*8))")"

echo "[INFO] Normalized audio duration : ${AUDIO_DUR} s"
echo "[INFO] Target IQ duration        : ${TARGET_IQ_SECONDS} s"
echo "[INFO] Target IQ bytes           : ${TARGET_IQ_BYTES}"

# 2) WAV -> DAB+ audio payload
echo "[ENC] Encoding normalized WAV to DAB+ payload..."
odr-audioenc -i "$NORMALIZED_WAV" -b "$BITRATE" -o "$ENC_FILE"

# 3) ODR-DabMux configuration (DAB Mode I, one service, raw ETI file output)
cat > "$MUX_FILE" <<EOF2
general {
 dabmode 1
}

ensemble {
 id 0x4fff
 ecc 0xec
 local-time-offset auto
 international-table 1
 label "$LABEL"
 shortlabel "$SHORT_LABEL"
}

services {
 srv0 {
  label "$LABEL"
  shortlabel "$SHORT_LABEL"
 }
}

subchannels {
 sub0 {
  type dabplus
  inputfile "$ENC_FILE"
  bitrate $BITRATE
  id 1
  protection 1
 }
}

components {
 comp0 {
  service srv0
  subchannel sub0
 }
}

outputs {
 output0 "file://$ETI_FILE?type=raw"
}
EOF2

# 4) Run the multiplexer for a limited time (it does not stop by itself)
echo "[MUX] Generating ETI (duration-limited)..."
rm -f "$ETI_FILE"
timeout 4s odr-dabmux "$MUX_FILE" || true

if [ ! -s "$ETI_FILE" ]; then
    echo "[ERR] ETI file was not created."
    exit 4
fi

# 5) ETI -> complex float32 baseband IQ at 2.048 MS/s
echo "[MOD] Modulating ETI to IQ file..."
odr-dabmod "$ETI_FILE" -f "$IQ_OUTPUT" -F complexf

if [ ! -s "$IQ_OUTPUT" ]; then
    echo "[ERR] IQ file was not created."
    exit 5
fi

ACTUAL_BYTES="$(stat -c%s "$IQ_OUTPUT")"
echo "[INFO] IQ bytes before trim      : ${ACTUAL_BYTES}"

# 6) Cut the IQ file to the target duration
if [ "$ACTUAL_BYTES" -gt "$TARGET_IQ_BYTES" ]; then
    echo "[TRIM] Truncating IQ file to target duration..."
    python3 -c "path=r'''$IQ_OUTPUT'''; target=int('$TARGET_IQ_BYTES'); f=open(path,'r+b'); f.truncate(target); f.close()"
fi

FINAL_BYTES="$(stat -c%s "$IQ_OUTPUT")"
echo "[INFO] IQ bytes after trim       : ${FINAL_BYTES}"

# 7) Metadata file next to the IQ file
cat > "$META_FILE" <<EOF2
{
  "label": "$LABEL",
  "short_label": "$SHORT_LABEL",
  "audio_input": "$AUDIO_PATH",
  "normalized_wav": "$NORMALIZED_WAV",
  "audio_duration_s": $AUDIO_DUR,
  "target_iq_duration_s": $TARGET_IQ_SECONDS,
  "iq_output": "$IQ_OUTPUT",
  "eti_file": "$ETI_FILE",
  "frequency_hz": $FREQ_HZ,
  "bitrate_kbps": $BITRATE,
  "sample_rate_hz": 2048000,
  "format": "complexf",
  "channels": 2,
  "source_sample_rate_hz": 48000,
  "final_iq_bytes": $FINAL_BYTES
}
EOF2

echo "[OK] IQ file saved: $IQ_OUTPUT"
echo "[OK] Metadata saved: $META_FILE"
