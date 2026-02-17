#!/bin/bash
# =============================================================================
# convert-to-qcow2.sh  —  DEV MACHINE  (run this once to prepare the image)
#
# Converts storage/data.img (raw, 140 GB) → data.qcow2 (compressed, ~30–50 GB)
# using qemu-img with internal zstd compression + sparse block skipping.
#
# Usage:
#   ./scripts/convert-to-qcow2.sh
#   ./scripts/convert-to-qcow2.sh --output /mnt/external/data.qcow2
#   ./scripts/convert-to-qcow2.sh --upload --bucket my-s3-bucket
# =============================================================================

set -euo pipefail

# ---- Defaults ----------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMG="$REPO_DIR/storage/data.img"
OUTPUT_IMG="$REPO_DIR/storage/data.qcow2"
S3_BUCKET=""
DO_UPLOAD=false
SKIP_VERIFY=false

# ---- Colors ------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ---- Arg parsing -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)    OUTPUT_IMG="$2"; shift 2 ;;
        --source)    SOURCE_IMG="$2"; shift 2 ;;
        --upload)    DO_UPLOAD=true; shift ;;
        --bucket)    S3_BUCKET="$2"; shift 2 ;;
        --skip-verify) SKIP_VERIFY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--output PATH] [--source PATH] [--upload] [--bucket S3_BUCKET]"
            exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

OUTPUT_DIR="$(dirname "$OUTPUT_IMG")"

# ---- Header ------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  ORB — Convert data.img → qcow2${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""

# ---- Step 1: Prereqs ---------------------------------------------------------
echo -e "${CYAN}[1/5] Checking prerequisites...${RESET}"

if ! command -v qemu-img &>/dev/null; then
    echo -e "${RED}ERROR: qemu-img not found.${RESET}"
    echo "  Install with: sudo apt install qemu-utils"
    exit 1
fi

QEMU_VERSION=$(qemu-img --version | head -1)
echo "  qemu-img: $QEMU_VERSION"

# Check zstd compression support (qemu-img >= 6.x supports qcow2+zstd)
if qemu-img convert --help 2>&1 | grep -q "compression_type"; then
    COMPRESSION_OPT="-o compression_type=zstd"
    echo "  zstd compression: supported"
else
    COMPRESSION_OPT=""
    echo -e "  ${YELLOW}zstd not available in this qemu-img — falling back to zlib${RESET}"
fi

# ---- Step 2: Verify source ---------------------------------------------------
echo ""
echo -e "${CYAN}[2/5] Verifying source image...${RESET}"

if [ ! -f "$SOURCE_IMG" ]; then
    echo -e "${RED}ERROR: Source not found: $SOURCE_IMG${RESET}"
    exit 1
fi

SOURCE_SIZE_BYTES=$(stat -c%s "$SOURCE_IMG")
SOURCE_SIZE_GB=$(( SOURCE_SIZE_BYTES / 1024 / 1024 / 1024 ))
echo "  Source: $SOURCE_IMG"
echo "  Size:   ${SOURCE_SIZE_GB} GB (${SOURCE_SIZE_BYTES} bytes)"

if [ -f "$OUTPUT_IMG" ]; then
    EXISTING_SIZE=$(stat -c%s "$OUTPUT_IMG")
    EXISTING_GB=$(( EXISTING_SIZE / 1024 / 1024 / 1024 ))
    echo ""
    echo -e "${YELLOW}WARNING: Output already exists: $OUTPUT_IMG (${EXISTING_GB} GB)${RESET}"
    read -rp "  Overwrite? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ---- Step 3: Disk space check ------------------------------------------------
echo ""
echo -e "${CYAN}[3/5] Checking disk space...${RESET}"

# Estimate output: ~30-40% of source (Windows NTFS with large empty space)
ESTIMATED_OUTPUT_GB=$(( SOURCE_SIZE_GB * 35 / 100 ))
FREE_BYTES=$(df -B1 "$OUTPUT_DIR" | awk 'NR==2 {print $4}')
FREE_GB=$(( FREE_BYTES / 1024 / 1024 / 1024 ))

echo "  Output dir:      $OUTPUT_DIR"
echo "  Free space:      ${FREE_GB} GB"
echo "  Estimated output: ~${ESTIMATED_OUTPUT_GB} GB (35% of ${SOURCE_SIZE_GB} GB)"

if [ "$FREE_GB" -lt "$ESTIMATED_OUTPUT_GB" ]; then
    echo ""
    echo -e "${RED}ERROR: Not enough free space.${RESET}"
    echo "  Need:      ~${ESTIMATED_OUTPUT_GB} GB"
    echo "  Available: ${FREE_GB} GB"
    echo "  Shortfall: $(( ESTIMATED_OUTPUT_GB - FREE_GB )) GB"
    echo ""
    echo -e "${YELLOW}Solutions:${RESET}"
    echo "  1. Point output to a different drive:"
    echo "     $0 --output /mnt/external-drive/data.qcow2"
    echo ""
    echo "  2. Free up space (e.g. clear old Docker images):"
    echo "     docker system prune -a"
    echo ""
    echo "  3. If you're SURE there's enough (sparse source), force with:"
    echo "     $0 --skip-verify"
    echo ""
    if [ "$SKIP_VERIFY" = false ]; then
        exit 1
    else
        echo -e "${YELLOW}--skip-verify passed, continuing anyway...${RESET}"
    fi
else
    echo -e "  ${GREEN}OK — sufficient space available.${RESET}"
fi

# ---- Step 4: Convert ---------------------------------------------------------
echo ""
echo -e "${CYAN}[4/5] Converting to qcow2 (this will take 20–60 minutes)...${RESET}"
echo "  Source: $SOURCE_IMG"
echo "  Output: $OUTPUT_IMG"
echo "  Format: qcow2 + zstd compression + sparse block skip"
echo ""

START_TIME=$(date +%s)

# -p = progress bar
# -c = enable internal compression
# -O qcow2 = output format
# -f raw = source format (explicit, safer)
# -o compression_type=zstd = use zstd inside qcow2 (best ratio)
# qemu-img skips zero sectors automatically during conversion
qemu-img convert \
    -p \
    -f raw \
    -O qcow2 \
    -c \
    $COMPRESSION_OPT \
    "$SOURCE_IMG" \
    "$OUTPUT_IMG"

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
ELAPSED_MIN=$(( ELAPSED / 60 ))
ELAPSED_SEC=$(( ELAPSED % 60 ))

echo ""
echo -e "${GREEN}Conversion complete in ${ELAPSED_MIN}m ${ELAPSED_SEC}s${RESET}"

# ---- Step 5: Report + Verify -------------------------------------------------
echo ""
echo -e "${CYAN}[5/5] Verifying output...${RESET}"

qemu-img check "$OUTPUT_IMG"

OUTPUT_SIZE_BYTES=$(stat -c%s "$OUTPUT_IMG")
OUTPUT_SIZE_GB=$(( OUTPUT_SIZE_BYTES / 1024 / 1024 / 1024 ))
REDUCTION=$(( 100 - (OUTPUT_SIZE_BYTES * 100 / SOURCE_SIZE_BYTES) ))

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${GREEN}  Conversion successful!${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo "  Source (raw):  ${SOURCE_SIZE_GB} GB"
echo "  Output (qcow2): ${OUTPUT_SIZE_GB} GB"
echo "  Reduction:     ${REDUCTION}%  (saved $(( SOURCE_SIZE_GB - OUTPUT_SIZE_GB )) GB)"
echo ""

# Show qemu-img info
echo -e "${CYAN}Image info:${RESET}"
qemu-img info "$OUTPUT_IMG"
echo ""

# ---- Step 6: Upload to S3 (optional) ----------------------------------------
if [ "$DO_UPLOAD" = true ]; then
    if [ -z "$S3_BUCKET" ]; then
        echo -e "${RED}ERROR: --upload requires --bucket <bucket-name>${RESET}"
        exit 1
    fi

    if ! command -v aws &>/dev/null; then
        echo -e "${RED}ERROR: aws CLI not found. Install with: pip install awscli${RESET}"
        exit 1
    fi

    echo -e "${CYAN}[6/6] Uploading to S3...${RESET}"
    echo "  Bucket: s3://$S3_BUCKET/orb/v1/data.qcow2"
    echo "  Size:   ${OUTPUT_SIZE_GB} GB (this will take a while)"
    echo ""

    aws s3 cp "$OUTPUT_IMG" "s3://$S3_BUCKET/orb/v1/data.qcow2" \
        --storage-class STANDARD_IA \
        --no-progress \
        --expected-size "$OUTPUT_SIZE_BYTES"

    echo ""
    echo -e "${GREEN}Upload complete!${RESET}"
    echo ""
    echo "Generate a 7-day download URL:"
    echo "  aws s3 presign s3://$S3_BUCKET/orb/v1/data.qcow2 --expires-in 604800"
fi

# ---- Next steps --------------------------------------------------------------
echo -e "${BOLD}Next steps:${RESET}"
echo ""
echo "  1. Upload to S3 (if not done above):"
echo "     aws s3 cp $OUTPUT_IMG s3://YOUR-BUCKET/orb/v1/data.qcow2 --storage-class STANDARD_IA"
echo ""
echo "  2. Generate a client download URL:"
echo "     aws s3 presign s3://YOUR-BUCKET/orb/v1/data.qcow2 --expires-in 604800"
echo ""
echo "  3. Give clients the URL + scripts/install.sh + docker-compose.yml"
echo ""
echo "  Or run with upload in one step:"
echo "     $0 --upload --bucket YOUR-BUCKET"
echo ""
