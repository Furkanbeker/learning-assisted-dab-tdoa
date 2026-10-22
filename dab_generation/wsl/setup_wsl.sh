#!/usr/bin/env bash
# =============================================================================
# setup_wsl.sh
#
# Installs the DAB transmit chain tools inside WSL (Ubuntu):
#   - ffmpeg / ffprobe          audio conversion
#   - odr-audioenc              audio -> DAB+ payload (.dabp)
#   - odr-dabmux                DAB+ payload -> ETI stream
#   - odr-dabmod                ETI -> DAB Mode-I baseband IQ (file or SDR)
#   - SoapySDR + PlutoSDR module  transmission with an ADALM-PLUTO
#
# Usage (inside WSL):
#   bash setup_wsl.sh
#
# Missing odr-* or SoapySDR packages must be built from source
# (Opendigitalradio). odr-dabmod needs SoapySDR support for the PlutoSDR.
# =============================================================================
set -euo pipefail

echo "[1/6] Updating apt..."
sudo apt-get update -y

echo "[2/6] Installing base tools..."
sudo apt-get install -y git build-essential cmake pkg-config \
  python3 python3-pip \
  ffmpeg \
  avahi-daemon avahi-utils \
  libfftw3-dev

echo "[3/6] Installing ODR tools (dabmod/dabmux/audioenc)..."
# Available as packages on some distributions; otherwise build from source.
sudo apt-get install -y odr-dabmod odr-dabmux odr-audioenc || true

echo "[4/6] Installing SoapySDR + Pluto support..."
sudo apt-get install -y soapysdr-tools soapysdr-module-all || true

echo "[5/6] Enabling and starting avahi-daemon (removes the Avahi DNS-SD warning)..."
sudo systemctl enable avahi-daemon || true
sudo systemctl start avahi-daemon || true

echo "[6/6] Done."
echo "If the odr-* packages were not found, build them from source."
