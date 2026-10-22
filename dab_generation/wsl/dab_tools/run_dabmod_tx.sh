#!/usr/bin/env bash
# =============================================================================
# run_dabmod_tx.sh
#
# Transmits eti/myfirst.eti in a loop with ODR-DabMod on an ADALM-PLUTO
# (SoapySDR) until stopped. URI, frequency and gain are written into a
# copy of configs/dabmod_pluto_tx.ini (dabmod_runtime.ini).
#
# Usage:
#   ./run_dabmod_tx.sh URI FREQ_HZ GAIN_DB [LOOP] [DURATION_S]
#
#   URI         Pluto URI, e.g. ip:192.168.2.1
#   FREQ_HZ     centre frequency in Hz, e.g. 195936000 (channel 8A)
#   GAIN_DB     PlutoSDR TX gain
#   LOOP, DURATION_S  accepted from the GUI but unused (loop is set in the .ini)
#
# Called by scripts/tx_file.sh and scripts/tx_random.sh.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

URI="$1"
FREQ="$2"
GAIN="$3"
LOOP="${4:-0}"
DUR="${5:-0}"

CONFIG="configs/dabmod_pluto_tx.ini"
TMP_CONFIG="dabmod_runtime.ini"

cp "$CONFIG" "$TMP_CONFIG"

# Fill in the runtime parameters
sed -i "s|uri=.*|uri=${URI}|" "$TMP_CONFIG"
sed -i "s|frequency=.*|frequency=${FREQ}|" "$TMP_CONFIG"
sed -i "s|txgain=.*|txgain=${GAIN}|" "$TMP_CONFIG"

echo "[TX] Using ETI source: $(grep '^source=' "$TMP_CONFIG")"
echo "[TX] Starting ODR-DabMod..."
odr-dabmod "$TMP_CONFIG"
