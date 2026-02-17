#!/bin/bash
# =============================================================================
# install.sh  —  CLIENT MACHINE  (run this to install ORB on a new machine)
#
# Downloads the pre-built Windows qcow2 disk image from S3 and starts the
# ORB Windows 11 environment via Docker.
#
# Usage:
#   DATA_IMG_URL="https://..." ./install.sh
#   ./install.sh --url "https://s3.amazonaws.com/..."
#   ./install.sh --url "https://..." --dir /opt/orb
# =============================================================================

set -euo pipefail

# ---- Defaults ----------------------------------------------------------------
ORB_DIR="${ORB_DIR:-$HOME/orb}"
DATA_IMG_URL="${DATA_IMG_URL:-}"
DISK_FILENAME="data.img"        # always stored as data.img (qcow2 inside, QEMU detects it)
MIN_FREE_GB=55                  # need space for the qcow2 download (~40 GB) + headroom

# ---- Colors ------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ---- Arg parsing -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)   DATA_IMG_URL="$2"; shift 2 ;;
        --dir)   ORB_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: DATA_IMG_URL=<url> $0"
            echo "       $0 --url <url> [--dir /path/to/install]"
            exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

STORAGE_DIR="$ORB_DIR/storage"

# ---- Header ------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  ORB Windows 11 Environment — Installer${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""

# ---- Step 1: Prerequisites ---------------------------------------------------
echo -e "${CYAN}[1/5] Checking prerequisites...${RESET}"

ERRORS=0

# Docker
if ! command -v docker &>/dev/null; then
    echo -e "  ${RED}FAIL: Docker not found.${RESET}"
    echo "       Install: https://docs.docker.com/engine/install/ubuntu/"
    ERRORS=1
else
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    echo -e "  ${GREEN}OK${RESET}   Docker $DOCKER_VER"
fi

# Docker running
if command -v docker &>/dev/null && ! docker info &>/dev/null 2>&1; then
    echo -e "  ${RED}FAIL: Docker daemon not running.${RESET}"
    echo "       Start it: sudo systemctl start docker"
    ERRORS=1
fi

# KVM
if [ ! -e /dev/kvm ]; then
    echo -e "  ${YELLOW}WARN: /dev/kvm not found. Windows will run slowly without KVM.${RESET}"
    echo "       Enable KVM: https://ubuntu.com/blog/kvm-hyphervisor"
elif [ ! -r /dev/kvm ]; then
    echo -e "  ${YELLOW}WARN: /dev/kvm exists but not readable.${RESET}"
    echo "       Fix: sudo usermod -aG kvm $USER && newgrp kvm"
else
    echo -e "  ${GREEN}OK${RESET}   KVM available"
fi

# Disk space
mkdir -p "$ORB_DIR"
FREE_GB=$(df -BG "$ORB_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
if [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
    echo -e "  ${RED}FAIL: Not enough disk space.${RESET}"
    echo "       Need: ${MIN_FREE_GB} GB free  |  Available: ${FREE_GB} GB"
    ERRORS=1
else
    echo -e "  ${GREEN}OK${RESET}   Disk space: ${FREE_GB} GB free"
fi

# Download tool (aria2c preferred, curl fallback)
if command -v aria2c &>/dev/null; then
    echo -e "  ${GREEN}OK${RESET}   Download tool: aria2c (fast parallel mode)"
    DOWNLOAD_TOOL="aria2c"
elif command -v curl &>/dev/null; then
    echo -e "  ${YELLOW}INFO${RESET} Download tool: curl (install aria2c for faster parallel downloads)"
    echo "       sudo apt install aria2"
    DOWNLOAD_TOOL="curl"
else
    echo -e "  ${RED}FAIL: No download tool found (need curl or aria2c).${RESET}"
    ERRORS=1
fi

# URL check
if [ -z "$DATA_IMG_URL" ]; then
    echo -e "  ${RED}FAIL: No download URL provided.${RESET}"
    echo "       Set it: DATA_IMG_URL=<url> $0"
    echo "       Or use: $0 --url <url>"
    ERRORS=1
fi

if [ "$ERRORS" -ne 0 ]; then
    echo ""
    echo -e "${RED}Fix the above errors and re-run.${RESET}"
    exit 1
fi

echo ""

# ---- Step 2: Pull Docker runtime image ---------------------------------------
echo -e "${CYAN}[2/5] Pulling Docker runtime image...${RESET}"
docker pull dockurr/windows
echo -e "  ${GREEN}Done.${RESET}"
echo ""

# ---- Step 3: Download disk image ---------------------------------------------
echo -e "${CYAN}[3/5] Downloading Windows disk image...${RESET}"
mkdir -p "$STORAGE_DIR"

TARGET="$STORAGE_DIR/$DISK_FILENAME"

if [ -f "$TARGET" ]; then
    EXISTING_GB=$(du -BG "$TARGET" | awk '{print $1}' | tr -d 'G')
    echo -e "  ${YELLOW}Found existing $DISK_FILENAME (${EXISTING_GB} GB).${RESET}"
    read -rp "  Re-download? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "  Skipping download — using existing file."
        SKIP_DOWNLOAD=true
    else
        SKIP_DOWNLOAD=false
        rm -f "$TARGET"
    fi
else
    SKIP_DOWNLOAD=false
fi

if [ "$SKIP_DOWNLOAD" = false ]; then
    echo "  Destination: $TARGET"
    echo "  URL: $DATA_IMG_URL"
    echo ""
    echo -e "  ${YELLOW}This downloads ~30–50 GB. Estimated time at common speeds:${RESET}"
    echo "    100 Mbps → ~45–65 min"
    echo "     50 Mbps → ~90 min – 2 hrs"
    echo "    Download is resumable — safe to interrupt and re-run."
    echo ""

    if [ "$DOWNLOAD_TOOL" = "aria2c" ]; then
        # aria2c: 16 parallel connections, resume on re-run
        aria2c \
            --max-connection-per-server=16 \
            --split=16 \
            --min-split-size=50M \
            --continue=true \
            --summary-interval=30 \
            --console-log-level=notice \
            --dir="$STORAGE_DIR" \
            --out="$DISK_FILENAME" \
            "$DATA_IMG_URL"
    else
        # curl: resume with -C -, retry on failure
        curl -L \
            -C - \
            "$DATA_IMG_URL" \
            -o "$TARGET" \
            --progress-bar \
            --retry 10 \
            --retry-delay 10 \
            --retry-max-time 3600
    fi

    echo ""
    DOWNLOADED_GB=$(du -BG "$TARGET" | awk '{print $1}' | tr -d 'G')
    echo -e "  ${GREEN}Download complete: ${DOWNLOADED_GB} GB${RESET}"
fi

echo ""

# ---- Step 4: Write docker-compose.yml ----------------------------------------
echo -e "${CYAN}[4/5] Writing docker-compose.yml...${RESET}"

cat > "$ORB_DIR/docker-compose.yml" << 'COMPOSE_EOF'
version: "3"
services:
  windows:
    image: dockurr/windows
    container_name: orb-win11
    cap_add:
      - NET_ADMIN
    stop_grace_period: 2m
    restart: on-failure
    devices:
      - /dev/kvm:/dev/kvm
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ./storage:/storage
      - ./shared:/shared
    environment:
      RAM_SIZE: "16G"
      CPU_CORES: "8"
      DISK_SIZE: "150G"
      VERSION: "11"
      USERNAME: "alkami"
      PASSWORD: "alkami123"
      KVM: "Y"
    stop_grace_period: 2m
COMPOSE_EOF

mkdir -p "$ORB_DIR/shared"
echo -e "  ${GREEN}Done.${RESET}"
echo ""

# ---- Step 5: Start -----------------------------------------------------------
echo -e "${CYAN}[5/5] Starting ORB Windows environment...${RESET}"
cd "$ORB_DIR"
docker compose up -d

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${GREEN}  ORB is running!${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo "  Browser UI:  http://localhost:8006"
echo "  RDP:         localhost:3389"
echo "  Username:    alkami"
echo "  Password:    alkami123"
echo ""
echo "  Windows takes ~2–3 min to fully boot."
echo "  Open http://localhost:8006 in your browser."
echo ""
echo "  Useful commands:"
echo "    docker compose -f $ORB_DIR/docker-compose.yml logs -f   # watch logs"
echo "    docker compose -f $ORB_DIR/docker-compose.yml down       # stop"
echo ""
