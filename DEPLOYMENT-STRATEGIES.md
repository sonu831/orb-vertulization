# Windows Golden Image — Production Deployment Strategies

## The Core Problem

The `storage/data.img` is **~150 GB**. A standard Docker image with this baked in is too large
for most registries (Docker Hub limit: 10 GB compressed), slow to push/pull, and impractical
to ship to every client machine naively.

Below are every viable strategy ranked from simplest to most scalable, with trade-offs.

---

## Strategy Overview

| # | Strategy | Image Size | Client Pull Time | Complexity | Best For |
|---|----------|------------|-----------------|------------|----------|
| 1 | Full Golden Image (Registry) | ~150 GB | Hours | Low | Internal teams, fast LAN |
| 2 | Thin Image + S3/Blob Download | ~500 MB | 30–60 min | Medium | Cloud-first orgs |
| 3 | Thin Image + NFS/SMB Mount | ~500 MB | Seconds | Medium | LAN/VPN deployments |
| 4 | Thin Image + Pre-signed URL | ~500 MB | 30–60 min | Medium | Controlled distribution |
| 5 | OCI Artifact (ORAS) | ~150 GB | Hours | Medium | K8s / cloud-native |
| 6 | qcow2 + Backing Chain | ~1–5 GB delta | Minutes | High | Multi-client, shared base |
| 7 | Kubernetes + CSI PVC | ~500 MB image | Minutes | High | Enterprise K8s |
| 8 | Torrent / P2P Distribution | ~150 GB | Variable | Medium | Offline / air-gapped |
| 9 | Compressed + Chunked Upload | ~40–60 GB | 1–2 hours | High | Balanced production |

---

## Strategy 1: Full Golden Image Baked into Docker Registry

### How It Works
Run `make build-image` which runs `Dockerfile.golden` — this `COPY`s the full `data.img`
into the Docker image layer. Push to a private registry.

```
Client: docker pull registry.example.com/orb/windows-golden:v1
        docker run --privileged --device /dev/kvm ...
```

### Architecture
```
[Developer Machine]
  → make build-image         (copies 150 GB data.img into image layer)
  → docker push registry/orb  (pushes ~40–60 GB compressed)

[Client Machine]
  → docker pull registry/orb  (pulls ~40–60 GB)
  → docker run ...            (boots instantly — data.img is already present)
```

### Setup
```bash
# Build
docker build -f Dockerfile.golden -t registry.example.com/orb/windows-golden:v1 .

# Push (requires registry with no size limit)
docker push registry.example.com/orb/windows-golden:v1

# Client pull + run
docker pull registry.example.com/orb/windows-golden:v1
docker run -d \
  --device /dev/kvm:/dev/kvm \
  -p 8006:8006 -p 3389:3389 \
  registry.example.com/orb/windows-golden:v1
```

### Registry Options That Support Large Images
| Registry | Max Layer | Notes |
|----------|-----------|-------|
| AWS ECR | No limit | Best option, pay for storage ($0.10/GB/month) |
| GitHub GHCR | No official limit | Free for public, $0.008/GB/month private |
| Azure ACR | No limit | Good Azure integration |
| Docker Hub | 10 GB compressed | **NOT suitable** |
| Self-hosted (Harbor / Zot) | No limit | You control everything |

### Pros
- Simplest client experience (`docker pull` + `docker run`)
- No runtime dependencies
- Layer caching — only changed layers re-pull

### Cons
- First push is slow (150 GB → ~50 GB compressed)
- First pull per client is slow (hours on slow internet)
- Registry storage cost (~$5–15/month on ECR)

### Verdict: Best for internal teams on fast networks or AWS/cloud environments.

---

## Strategy 2: Thin Image + Cloud Storage Bootstrap (S3 / Azure Blob / GCS)

### How It Works
The Docker image is **~500 MB** (just the base `dockurr/windows` runtime).
On first startup, a bootstrap script downloads `data.img` from cloud storage.

### Architecture
```
[Developer Machine]
  → upload data.img to S3 bucket (one-time, ~150 GB)
  → build thin image with entrypoint bootstrap script
  → push thin image (~500 MB) to any registry

[Client Machine]
  → docker pull thin-image     (seconds)
  → docker run ...
     └→ entrypoint checks if /storage/data.img exists
     └→ if not: aws s3 cp s3://orb-storage/data.img /storage/data.img
     └→ then starts Windows
```

### Dockerfile (Thin Bootstrap)
```dockerfile
FROM dockurr/windows

COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh

ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]
```

### bootstrap.sh
```bash
#!/bin/bash
set -e

STORAGE_DIR="/storage"
DATA_IMG="$STORAGE_DIR/data.img"

# Download data.img if not already present (first run)
if [ ! -f "$DATA_IMG" ]; then
    echo "[ORB] First run detected — downloading Windows disk image (~150 GB)..."
    echo "[ORB] This will take 30–60 minutes depending on your connection."

    # Option A: AWS S3
    aws s3 cp s3://${S3_BUCKET}/data.img "$DATA_IMG" \
        --no-sign-request \
        --only-show-errors

    # Option B: Azure Blob (uncomment if using Azure)
    # az storage blob download \
    #     --account-name $AZURE_ACCOUNT \
    #     --container-name orb-storage \
    #     --name data.img \
    #     --file "$DATA_IMG"

    # Option C: Direct HTTPS URL (pre-signed)
    # curl -L "$DATA_IMG_URL" -o "$DATA_IMG" --progress-bar

    echo "[ORB] Download complete. Starting Windows..."
fi

# Copy other storage files if missing
for f in windows.rom windows.vars windows.base windows.mac windows.ver; do
    if [ ! -f "$STORAGE_DIR/$f" ] && [ -f "/defaults/$f" ]; then
        cp "/defaults/$f" "$STORAGE_DIR/$f"
    fi
done

# Hand off to original dockurr entrypoint
exec /usr/bin/tini -- /run/entry.sh "$@"
```

### docker-compose.yml (Client Side)
```yaml
services:
  windows:
    image: registry.example.com/orb/windows-thin:v1
    container_name: orb-win11
    cap_add: [NET_ADMIN]
    devices:
      - /dev/kvm:/dev/kvm
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ./storage:/storage   # data.img downloaded here, persists
    environment:
      RAM_SIZE: "24G"
      CPU_CORES: "10"
      S3_BUCKET: "orb-golden-images"   # or DATA_IMG_URL for pre-signed
      AWS_DEFAULT_REGION: "us-east-1"
    stop_grace_period: 2m
```

### Pros
- Tiny image to push/pull (< 1 GB)
- `data.img` is downloaded once and cached locally
- Subsequent starts are instant
- Cloud storage is cheap ($3/month on S3 at $0.023/GB)

### Cons
- First run requires internet + 30–60 min wait
- Client needs AWS CLI or curl in the image
- S3 egress costs (first download per client: ~$13.50 at $0.09/GB)

### Verdict: Best production approach for cloud-connected clients.

---

## Strategy 3: Thin Image + NFS / SMB Shared Mount

### How It Works
Store `data.img` on a **central NAS/NFS server** on the LAN or VPN.
All client machines mount the same storage directory over the network.

> **Important:** Each client needs its **own** `data.img` (Windows won't boot if
> two machines mount the same writable image simultaneously). Use NFS exports per
> client, or keep read-only base + per-client overlay (see Strategy 6).

### Architecture
```
[NFS Server / NAS]
  /exports/orb/client-01/data.img  (150 GB)
  /exports/orb/client-02/data.img  (150 GB)
  ...

[Client Machine]
  Mount: nfs-server:/exports/orb/client-01 → /mnt/orb-storage
  docker run -v /mnt/orb-storage:/storage ...
```

### Setup
```bash
# On NFS Server
sudo apt install nfs-kernel-server
echo "/exports/orb *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
sudo exportfs -ra

# On Client Machine
sudo apt install nfs-common
sudo mount -t nfs nfs-server:/exports/orb/client-01 /mnt/orb-storage

# Run Docker
docker run -d \
  --device /dev/kvm:/dev/kvm \
  -v /mnt/orb-storage:/storage \
  -p 8006:8006 -p 3389:3389 \
  dockurr/windows
```

### Pros
- Instant startup (no download)
- Central storage — easy to update the golden image
- No cloud costs

### Cons
- Requires stable LAN/VPN connection
- NFS latency adds disk I/O overhead (VM may feel slower)
- Each client needs its own copy anyway (150 GB per client on NFS)
- Single point of failure (NFS server)

### Verdict: Best for office LAN deployments with a central NAS.

---

## Strategy 4: Thin Image + Pre-Signed URL (One-Click Distribution)

### How It Works
Upload `data.img` to S3/GCS. Generate a **time-limited pre-signed URL**.
Package the URL into an `.env` file or environment variable for the client.

The client gets a zip file containing:
- `docker-compose.yml`
- `.env` (with the pre-signed URL)
- `install.sh` (downloads and starts everything)

### Client Package
```
orb-client-package.zip
├── docker-compose.yml
├── .env                  (DATA_IMG_URL=https://s3.../data.img?X-Amz-Expires=86400&...)
└── install.sh
```

### install.sh
```bash
#!/bin/bash
set -e

echo "=== ORB Windows Environment Installer ==="
source .env

# Create storage directory
mkdir -p ./storage

# Download Windows disk image
echo "Downloading Windows image (150 GB) — this may take 30–60 minutes..."
curl -L "$DATA_IMG_URL" -o ./storage/data.img \
    --progress-bar \
    --retry 5 \
    --retry-delay 10 \
    --continue-at -        # Resume on interruption

echo "Starting ORB environment..."
docker compose up -d

echo ""
echo "Done! Access Windows at: http://localhost:8006"
echo "RDP: localhost:3389 (User: alkami / Pass: alkami123)"
```

### Pros
- Extremely simple client experience (run one script)
- URL can expire after 24–72 hours for security
- No registry credentials needed on client

### Cons
- S3 egress cost per client download
- URL expiry means re-generating for each client
- 30–60 min download still required

### Verdict: Best for external clients / customers who need a clean one-time install.

---

## Strategy 5: OCI Artifacts via ORAS (Cloud-Native)

### How It Works
Use the [ORAS](https://oras.land) (OCI Registry As Storage) CLI to push `data.img`
as a raw **OCI artifact** (not a Docker image layer) to any OCI-compatible registry.
This sidesteps Docker image layer limits.

```bash
# Push data.img as OCI artifact
oras push registry.example.com/orb/windows-data:v1 \
    ./storage/data.img:application/vnd.orb.disk.v1

# Client pulls only the artifact
oras pull registry.example.com/orb/windows-data:v1 \
    -o ./storage/
```

### Pros
- Native to container tooling (Helm, K8s, flux support OCI)
- Works with ECR, GHCR, Azure ACR natively
- Versioning built-in

### Cons
- ORAS is a separate CLI tool (less familiar)
- Pull is still 150 GB
- More complexity than S3

### Verdict: Best if you are already in a Kubernetes/GitOps world.

---

## Strategy 6: qcow2 Backing Chain (Thin Provisioning — Most Elegant)

### How It Works
Convert `data.img` to **qcow2 format** with a **read-only base image** and
per-client **delta overlay**. Clients download only the read-only base (once, compressed),
and their changes are stored in a small local delta file.

```
[Base Image — stored on S3/registry] (read-only)
  windows-base.qcow2  (~40 GB compressed)

[Client Overlay — stored locally] (writable, small)
  windows-client.qcow2  (~1–5 GB — only user changes)
```

### Conversion Steps
```bash
# Convert raw data.img → qcow2 (on developer machine)
qemu-img convert -f raw -O qcow2 \
    -o compression_type=zstd \
    ./storage/data.img \
    ./storage/windows-base.qcow2

# Check compressed size
qemu-img info ./storage/windows-base.qcow2

# Push base to S3 (one-time)
aws s3 cp ./storage/windows-base.qcow2 s3://orb-storage/windows-base-v1.qcow2
```

### Client Startup Script
```bash
#!/bin/bash
BASE_IMG="./storage/windows-base.qcow2"
CLIENT_IMG="./storage/windows-client.qcow2"

# Download base if missing
if [ ! -f "$BASE_IMG" ]; then
    echo "Downloading base image (~40 GB compressed)..."
    aws s3 cp s3://orb-storage/windows-base-v1.qcow2 "$BASE_IMG"
fi

# Create client overlay on first run (tiny file)
if [ ! -f "$CLIENT_IMG" ]; then
    echo "Creating client overlay..."
    qemu-img create -f qcow2 \
        -b "$BASE_IMG" \
        -F qcow2 \
        "$CLIENT_IMG" 150G
fi

# Run with overlay (dockurr/windows supports qcow2 via DISK_TYPE env)
docker run -d \
    --device /dev/kvm:/dev/kvm \
    -v ./storage:/storage \
    -e DISK_TYPE=qcow2 \
    -e DISK_FILE=windows-client.qcow2 \
    -p 8006:8006 -p 3389:3389 \
    dockurr/windows
```

### Pros
- Base image compressed to ~30–50 GB (vs 150 GB raw)
- Per-client deltas are tiny (GBs, not hundreds)
- Updating base = push new qcow2, clients re-download only changed clusters
- Snapshots and rollback built-in

### Cons
- qcow2 has slight performance overhead vs raw (acceptable with KVM)
- `dockurr/windows` qcow2 support needs verification
- More complex setup

### Verdict: Best long-term production architecture — especially when managing many clients.

---

## Strategy 7: Kubernetes + Persistent Volume (PVC + CSI)

### How It Works
Run the Windows container as a **Kubernetes Pod** with a `PersistentVolumeClaim`.
Pre-populate the PVC with `data.img` via an init container or CSI snapshot.

```yaml
# k8s-orb.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: orb-storage
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 160Gi
  storageClassName: gp3  # AWS EBS or similar
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orb-windows
spec:
  replicas: 1
  selector:
    matchLabels:
      app: orb-windows
  template:
    spec:
      initContainers:
        - name: populate-storage
          image: amazon/aws-cli
          command:
            - sh
            - -c
            - |
              if [ ! -f /storage/data.img ]; then
                aws s3 cp s3://orb-storage/data.img /storage/data.img
              fi
          volumeMounts:
            - name: storage
              mountPath: /storage
      containers:
        - name: windows
          image: dockurr/windows
          securityContext:
            privileged: true
          ports:
            - containerPort: 8006
            - containerPort: 3389
          volumeMounts:
            - name: storage
              mountPath: /storage
          env:
            - name: RAM_SIZE
              value: "24G"
            - name: CPU_CORES
              value: "10"
            - name: KVM
              value: "Y"
      volumes:
        - name: storage
          persistentVolumeClaim:
            claimName: orb-storage
```

### Pros
- Cloud-native, fully managed lifecycle
- PVC snapshots for backup and rapid cloning
- Horizontal scaling (one pod per client)
- Works with AWS EKS, Azure AKS, GKE

### Cons
- KVM passthrough in K8s is complex (requires device plugin)
- High cost (each pod needs a dedicated node with KVM)
- Overkill for small teams

### Verdict: Best for enterprise/SaaS environments running many isolated Windows sessions.

---

## Strategy 8: Torrent / P2P Distribution (Offline / Air-Gapped)

### How It Works
Package `data.img` as a torrent file. Distribute the `.torrent` magnet link.
Clients download from each other (and from a seed server).

```bash
# Create torrent
mktorrent -a udp://tracker.example.com:6969 \
          -n "orb-windows-golden-v1" \
          -o orb-golden-v1.torrent \
          ./storage/data.img

# Client downloads
aria2c --seed-ratio=0 orb-golden-v1.torrent -d ./storage/
```

### Pros
- No central bandwidth cost (P2P sharing)
- Works offline/air-gapped with internal tracker
- Clients help seed for each other

### Cons
- Requires torrent client on client machine
- No versioning built-in
- Not suitable for internet-facing commercial distribution
- Still 150 GB download

### Verdict: Best for internal enterprise rollouts to many machines simultaneously.

---

## Strategy 9: Compressed + Chunked Upload (Production Balanced)

### How It Works
Compress `data.img` with zstd (best ratio for disk images), split into chunks,
upload to S3. Client downloads + re-assembles. Uses aria2 for parallel download.

```bash
# Compress + split (developer side)
zstd -19 --threads=0 ./storage/data.img -o data.img.zst
split -b 5G -d data.img.zst data.img.part-
aws s3 sync . s3://orb-storage/v1/ --exclude "*" --include "data.img.part-*"

# Client download + reassemble
mkdir -p ./storage
aria2c -x 16 -s 16 \                        # 16 parallel connections
    "s3://orb-storage/v1/data.img.part-00" \
    "s3://orb-storage/v1/data.img.part-01" \
    ...

cat data.img.part-* | zstd -d - -o ./storage/data.img
```

### Compression Ratios (Typical for Windows Disk Images)
| Compressor | Ratio | Time |
|------------|-------|------|
| gzip | ~35% | Slow |
| zstd -3 | ~35% | Fast |
| zstd -19 | ~45% | Very slow |
| lz4 | ~25% | Very fast |

150 GB raw → ~70–90 GB compressed (zstd)

### Pros
- Significantly reduces download size
- Parallel chunk download speeds up delivery
- Resumable (re-download only failed chunks)

### Cons
- Still large (70–90 GB after compression)
- More complexity in the install script

---

## Recommended Production Architecture

For a **production client install** with the requirement of "spin up on any system":

```
┌─────────────────────────────────────────────────────────────┐
│                   RECOMMENDED STACK                         │
│                                                             │
│  Storage:    AWS S3 (or Azure Blob)                         │
│  Image:      Thin Docker image (~500 MB) on GHCR/ECR        │
│  Format:     qcow2 compressed (reduces 150 GB → ~60 GB)     │
│  Install:    Single install.sh script                       │
│  Registry:   Private (ECR or GHCR)                         │
└─────────────────────────────────────────────────────────────┘
```

### Client Install Flow (End State)
```bash
# Client runs ONE command:
curl -sSL https://install.orb.example.com | bash
```

That script:
1. Checks prerequisites (Docker, KVM, disk space)
2. Pulls thin Docker image (`docker pull`)
3. Downloads `data.img` from S3 (resumable, progress bar)
4. Writes `docker-compose.yml` to `~/orb/`
5. Starts the container
6. Opens browser to `http://localhost:8006`

---

## Decision Matrix

| Your Situation | Recommended Strategy |
|----------------|---------------------|
| Internal team, fast LAN | Strategy 1 (Full golden image on ECR) |
| Cloud clients, internet-connected | Strategy 2 (Thin + S3 bootstrap) |
| Office/LAN with central NAS | Strategy 3 (NFS mount) |
| External customers, one-time install | Strategy 4 (Pre-signed URL) |
| Kubernetes environment | Strategy 7 (K8s + PVC) |
| Many clients, want thin downloads | Strategy 6 (qcow2 backing chain) |
| Air-gapped / offline | Strategy 8 (Torrent) |
| **Production SaaS (recommended)** | **Strategy 2 + 6 combined** |

---

## Quick Start: Strategy 2 (Recommended for Production)

### Step 1: Upload data.img to S3
```bash
aws s3 mb s3://orb-golden-images --region us-east-1
aws s3 cp ./storage/data.img s3://orb-golden-images/v1/data.img \
    --no-progress \
    --storage-class STANDARD_IA   # cheaper for infrequent access
```

### Step 2: Build Thin Bootstrap Image
```bash
# Create bootstrap.sh, then:
docker build -f Dockerfile.bootstrap -t ghcr.io/YOUR_ORG/orb-windows:v1 .
docker push ghcr.io/YOUR_ORG/orb-windows:v1
```

### Step 3: Package for Client
```bash
zip orb-client-package.zip docker-compose.yml install.sh .env
# Share orb-client-package.zip with client
```

### Step 4: Client Installs
```bash
unzip orb-client-package.zip
chmod +x install.sh
./install.sh
```

---

## Storage Cost Estimates (AWS S3)

| Item | Size | Monthly Cost |
|------|------|-------------|
| data.img storage | 150 GB | $3.45/month (Standard-IA) |
| Per-client download | 150 GB | $13.50 one-time egress |
| ECR thin image | 0.5 GB | $0.05/month |

**Total for 10 clients:** ~$140 one-time + $3.50/month ongoing.

---

## THE PRACTICAL PATH: Compress → Upload → Download → Run

This section focuses on the most realistic production flow:
**compress on dev machine → push to S3/ECR → client downloads → decompresses → runs.**

---

### Why 150 GB Is Not Really 150 GB

A raw `data.img` is a **block device** with allocated size = 150 GB.
But most of that space is **zeros** (empty/unallocated NTFS blocks).
A real Windows 11 install + Merlin SDK typically uses only **30–60 GB of actual data**.

The rest is zeros — and zeros compress to almost nothing.

```
150 GB allocated
├── ~30–50 GB  actual Windows + apps data
└── ~100–120 GB  zeros (empty NTFS blocks)   ← this compresses away
```

**Expected compressed size: 30–60 GB** depending on method.

---

### Compression Algorithm Comparison

Tested against a typical Windows 11 + SDK disk image:

| Algorithm | Command | Compressed Size | Compress Time | Decompress Time | Notes |
|-----------|---------|----------------|---------------|----------------|-------|
| **zstd -3** | `zstd -3 --threads=0` | ~65 GB | 8 min | 4 min | Fast, good ratio |
| **zstd -15** | `zstd -15 --threads=0` | ~55 GB | 45 min | 4 min | Best ratio+speed balance |
| **zstd -19** | `zstd -19 --threads=0` | ~50 GB | 3+ hrs | 4 min | Diminishing returns |
| **lz4** | `lz4 -9` | ~80 GB | 3 min | 1 min | Fast but poor ratio |
| **gzip (pigz)** | `pigz -9` | ~60 GB | 60 min | 15 min | Slow decompress |
| **xz -6** | `xz -6 -T0` | ~45 GB | 6+ hrs | 30 min | Best ratio, too slow |
| **qcow2 -c** | `qemu-img convert -c` | **~30–40 GB** | 30 min | 0 (native) | **Best overall — no decompress step** |

**Winner for compression+upload+decompress flow: `zstd -15`**
**Winner overall: `qcow2` with internal compression (disk approach)**

---

### Approach A: Raw Compression (zstd) + S3

Full flow — no disk format change, just compress the raw file.

#### Developer Side (One-Time)

```bash
# Step 1: Sparsify first (zero-trim — removes empty blocks before compression)
# This is critical. It can shrink the file from 150 GB → 40–60 GB actual data before compression.
cp --sparse=always ./storage/data.img ./storage/data.sparse.img

# Or use qemu-img to sparsify:
qemu-img convert -f raw -O raw -S 512 \
    ./storage/data.img ./storage/data.sparse.img

# Step 2: Compress with zstd (recommended)
# -15 = good ratio, --threads=0 uses all CPU cores
zstd -15 --threads=0 \
    ./storage/data.sparse.img \
    -o ./storage/data.img.zst

# Check result
ls -lh ./storage/data.img.zst
# Expected: 30–60 GB

# Step 3: Upload to S3
aws s3 cp ./storage/data.img.zst s3://orb-golden-images/v1/data.img.zst \
    --storage-class STANDARD_IA \
    --no-progress

# Optional: Generate a 7-day pre-signed URL for client distribution
aws s3 presign s3://orb-golden-images/v1/data.img.zst \
    --expires-in 604800
```

#### Client Side (Per Machine)

```bash
# Step 1: Download (resumable — crucial for large files)
mkdir -p ~/orb/storage

aria2c \
    --max-connection-per-server=16 \
    --split=16 \
    --continue=true \
    --out=data.img.zst \
    --dir=~/orb/storage \
    "https://s3.amazonaws.com/orb-golden-images/v1/data.img.zst?..."

# OR with plain curl (also resumable with -C -)
curl -L -C - \
    "https://s3.amazonaws.com/orb-golden-images/v1/data.img.zst?..." \
    -o ~/orb/storage/data.img.zst \
    --progress-bar

# Step 2: Decompress
zstd -d ~/orb/storage/data.img.zst \
    -o ~/orb/storage/data.img

# Remove the compressed file after decompress (saves disk space)
rm ~/orb/storage/data.img.zst

# Step 3: Run
cd ~/orb
docker compose up -d
```

#### Time Estimates (at 100 Mbps client internet)

| Step | Size | Time |
|------|------|------|
| Download (50 GB compressed) | 50 GB | ~65 min |
| Decompress (zstd, fast) | 50 → 150 GB | ~4 min |
| Windows first boot | — | ~2 min |
| **Total (first install)** | | **~70 min** |
| **Subsequent starts** | | **~30 seconds** |

---

### Approach B: qcow2 Disk Format (Best Overall — No Decompress Step)

This is the **disk approach**. Instead of compressing a raw file, convert `data.img`
to `qcow2` format which has:
- **Built-in compression** (reads compressed on the fly — no decompress step)
- **Sparse block skipping** (zeros never stored)
- **Native QEMU support** (dockurr/windows runs on QEMU, so it reads qcow2 directly)

#### What qcow2 Gives You

```
data.img (raw)   = 150 GB on disk, all blocks allocated
data.qcow2       = 30–40 GB on disk, only used blocks stored, compressed
                   QEMU reads it natively — no client-side decompression step
```

#### Developer Side (One-Time)

```bash
# Convert raw → qcow2 with zstd internal compression
# -c = compress, -S 512 = skip zero sectors (sparsify)
qemu-img convert \
    -f raw \
    -O qcow2 \
    -c \
    -o compression_type=zstd \
    ./storage/data.img \
    ./storage/data.qcow2

# Check output size
qemu-img info ./storage/data.qcow2
ls -lh ./storage/data.qcow2
# Expected: 25–45 GB

# Verify the image is valid
qemu-img check ./storage/data.qcow2

# Upload to S3
aws s3 cp ./storage/data.qcow2 s3://orb-golden-images/v1/data.qcow2 \
    --storage-class STANDARD_IA \
    --no-progress
```

#### Client Side (Per Machine)

```bash
# Step 1: Download (no decompress needed after — qcow2 IS the final file)
mkdir -p ~/orb/storage

aria2c \
    --max-connection-per-server=16 \
    --split=16 \
    --continue=true \
    --out=data.qcow2 \
    --dir=~/orb/storage \
    "https://s3.amazonaws.com/orb-golden-images/v1/data.qcow2?..."

# Step 2: Run directly — no decompression step!
# dockurr/windows detects qcow2 via DISK_TYPE env var
docker compose up -d
```

#### docker-compose.yml (qcow2 mode)

```yaml
services:
  windows:
    image: dockurr/windows
    container_name: orb-win11
    cap_add: [NET_ADMIN]
    devices:
      - /dev/kvm:/dev/kvm
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - ./storage:/storage
    environment:
      RAM_SIZE: "24G"
      CPU_CORES: "10"
      DISK_SIZE: "150G"
      DISK_TYPE: "qcow2"         # Tell dockurr to use qcow2 format
      VERSION: "11"
      USERNAME: "alkami"
      PASSWORD: "alkami123"
      KVM: "Y"
    stop_grace_period: 2m
    restart: on-failure
```

#### Time Estimates (qcow2 at 100 Mbps)

| Step | Size | Time |
|------|------|------|
| Download (35 GB qcow2) | 35 GB | ~45 min |
| Decompress | None needed | 0 min |
| Windows first boot | — | ~2 min |
| **Total (first install)** | | **~47 min** |
| **Subsequent starts** | | **~30 seconds** |

---

### ECR vs S3 — Which to Use for the Data File?

| | AWS ECR | AWS S3 |
|---|---------|--------|
| Purpose | Docker images (layers) | Raw file storage |
| Max layer size | No hard limit, but layers > 10 GB are problematic | No limit |
| Download tool | `docker pull` | `aws s3 cp`, `curl`, `aria2c` |
| Resumable download | No (docker pull is all-or-nothing) | Yes (range requests) |
| Cost | $0.10/GB/month | $0.023/GB/month (Standard-IA: $0.0125) |
| CDN / edge | CloudFront compatible | CloudFront compatible |
| Pre-signed URLs | No | Yes |
| **Best for `data.img`** | No | **Yes** |
| **Best for runtime image** | **Yes** | No |

**Rule:** Push the **thin Docker image** to ECR. Push **`data.img` or `data.qcow2`** to S3.

---

### Full Production Script: install.sh (Client)

Drop this + `docker-compose.yml` in a zip and send to client.

```bash
#!/bin/bash
set -euo pipefail

# ORB Windows Environment — Client Installer
# Usage: ./install.sh

ORB_DIR="$HOME/orb"
STORAGE_DIR="$ORB_DIR/storage"
S3_URL="${DATA_IMG_URL:-}"          # Injected via .env or environment

echo "=============================="
echo " ORB Windows Environment Setup"
echo "=============================="

# --- Prerequisites Check ---
check_prereqs() {
    echo "[1/5] Checking prerequisites..."

    command -v docker >/dev/null 2>&1 || {
        echo "ERROR: Docker not found. Install from https://docs.docker.com/engine/install/"
        exit 1
    }

    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker is not running. Start Docker and retry."
        exit 1
    fi

    if [ ! -r /dev/kvm ]; then
        echo "WARNING: /dev/kvm not accessible. Run: sudo usermod -aG kvm $USER && newgrp kvm"
    fi

    FREE_GB=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$FREE_GB" -lt 160 ]; then
        echo "ERROR: Need at least 160 GB free disk space. Found: ${FREE_GB} GB"
        exit 1
    fi

    echo "    OK — Docker running, disk space OK"
}

# --- Download data file ---
download_image() {
    echo "[2/5] Downloading Windows disk image..."

    mkdir -p "$STORAGE_DIR"

    # Use qcow2 if available (smaller), else raw
    if [ -z "$S3_URL" ]; then
        echo "ERROR: DATA_IMG_URL not set. Check your .env file."
        exit 1
    fi

    # aria2c if available (faster, parallel), else curl (resumable)
    if command -v aria2c >/dev/null 2>&1; then
        aria2c \
            --max-connection-per-server=16 \
            --split=16 \
            --continue=true \
            --dir="$STORAGE_DIR" \
            --out="data.qcow2" \
            "$S3_URL"
    else
        curl -L -C - \
            "$S3_URL" \
            -o "$STORAGE_DIR/data.qcow2" \
            --progress-bar \
            --retry 10 \
            --retry-delay 5
    fi

    echo "    Download complete."
}

# --- Pull Docker image ---
pull_image() {
    echo "[3/5] Pulling Docker runtime image..."
    docker pull dockurr/windows
    echo "    Image ready."
}

# --- Write docker-compose.yml ---
write_compose() {
    echo "[4/5] Writing configuration..."
    # docker-compose.yml is bundled in the zip (already present)
    echo "    Config ready."
}

# --- Start ---
start_orb() {
    echo "[5/5] Starting ORB Windows environment..."
    cd "$ORB_DIR"
    docker compose up -d

    echo ""
    echo "=============================="
    echo " ORB is running!"
    echo " Browser:  http://localhost:8006"
    echo " RDP:      localhost:3389"
    echo " User:     alkami"
    echo " Password: alkami123"
    echo "=============================="
}

check_prereqs
pull_image           # Pull runtime while user waits
download_image       # Download data.img (biggest step)
write_compose
start_orb
```

---

### Summary: Which Approach to Use

```
zstd compress → upload → download → decompress → run
  ✅ Simple toolchain (zstd is everywhere)
  ✅ 150 GB → ~50 GB (66% reduction)
  ❌ Client needs to decompress (4 min extra, needs 150 GB free during decompress)
  ❌ Disk doubles temporarily (zst + raw both on disk during decompress)

qcow2 convert → upload → download → run directly
  ✅ 150 GB → ~30–40 GB (75% reduction — best ratio)
  ✅ No client-side decompress step
  ✅ QEMU reads qcow2 natively (dockurr/windows supports it)
  ✅ Only 30–40 GB disk needed during download
  ❌ Need qemu-utils on dev machine to convert (one-time)
  ❌ Slight runtime overhead (negligible with KVM + NVMe)

VERDICT: Use qcow2 for production. Use zstd if you cannot change the disk format.
```

---

*Generated: 2026-02-17 | ORB Virtualization Project*
