# 🌐 ORB Virtualization: The Orbless Initiative

> **Vision:** A scalable, containerized Windows 11 environment that eliminates hardware dependencies and drastically reduces onboarding time.

This Proof of Concept (POC) demonstrates running a fully functional Windows 11 development environment inside Docker on a **Linux Host** with KVM acceleration.

---

## 🏗️ Architecture & Compatibility (READ FIRST)

This project supports both **Intel/AMD** and **Apple Silicon (ARM)**, but they require different configurations. **You must use the correct image for your machine.**

### 1. Intel / AMD (x64) - Recommended (POC Standard)
- **Target Machines:** Most Windows/Linux laptops, Desktops, Servers, AWS EC2.
- **Docker Image:** `dockurr/windows`
- **Performance:** 🚀 **Fast** (Uses KVM Hardware Acceleration).
- **Configuration (docker-compose.yml):**
  ```yaml
  image: dockurr/windows
  environment:
    KVM: "Y"
  ```

### 2. Apple Silicon (ARM64) - Mac M1/M2/M3
- **Target Machines:** MacBook M1, M2, M3, M4.
- **Docker Image:** `dockurr/windows-arm`
- **Performance:** 🐢 **Slower** (Uses Software Emulation / QEMU).
- **Configuration (docker-compose.yml):**
  ```yaml
  image: dockurr/windows-arm
  environment:
    KVM: "N"
  ```

> **⚠️ CRITICAL WARNING:**
> Do **NOT** mix these images. An ARM disk (`data.img`) created on a Mac **will not boot** on an Intel machine, and vice-versa.
> If you switch machines, you must delete the `storage` folder and let it re-download the correct version.

> **ℹ️ Merlin SDK Setup:**
> The `storage` folder contains Merlin SDK setup files for **both** architectures (ARM and x64).
> *   **Intel/AMD:** Use the x64 installer.
> *   **Apple Silicon:** Use the ARM/M-Series installer.
> *   **Action:** Browse to `\\host.lan\data` inside the VM and run the correct installer for your device.

---

## 🚀 Getting Started

### Prerequisites (Linux Host)

1.  **Docker Installed:** Native Docker Engine.
2.  **KVM Enabled:**
    Check with `kvm-ok`. If permission denied:
    ```bash
    sudo usermod -aG kvm $USER
    newgrp kvm
    ```
3.  **Permissions:** User must be in `docker` group.
    ```bash
    sudo usermod -aG docker $USER
    newgrp docker
    ```
4.  **Resources:** 
    - **RAM:** 32GB Minimum (Allocating 24GB to Windows).
    - **Swap:** Ensure host has ~64GB Swap to prevent OOM kills.
    - **Disk:** 100GB+ Free Space.

### Quick Launch

1.  **Clone the repository.**
2.  **Launch the Environment:**
    ```bash
    make up
    ```
    *(Or run `./start-orb.sh` directly)*

3.  **Wait for Installation:**
    The first run downloads Windows (~14GB) and installs it automatically. This takes **15-30 minutes**.
    Monitor progress:
    ```bash
    make logs
    ```

---

## ⚙️ Configuration Guide (docker-compose.yml)

You can customize the VM by editing `docker-compose.yml`. Here is a detailed breakdown of each setting:

| Field | Typical Value | Description |
| :--- | :--- | :--- |
| **`image`** | `dockurr/windows` | **Selection:** Use `windows` for Intel/AMD, `windows-arm` for Apple Silicon. |
| **`devices`** | `/dev/kvm` | Maps the KVM hardware interface to the container. **Required for speed on Linux.** Remove this section on Mac. |
| `RAM_SIZE` | `24G` | Amount of RAM given to Windows. Increase this for heavy apps (Visual Studio, Merlin). Minimum 24G recommended. |
| `CPU_CORES` | `14` | Number of CPU cores assigned to the VM. More cores = smoother UI. |
| `DISK_SIZE` | `120G` | Size of the virtual C: drive. Increase if you install many tools. |
| `KVM` | `Y` / `N` | `Y` enables hardware acceleration (Linux). `N` uses software emulation (Mac). |
| `volumes` | `./storage:/storage` | **Persistence:** Maps the local `storage` folder to the VM. This ensures your data survives container destruction. |
| `MANUAL` | `N` | set to `Y` if you want to perform the Windows installation steps manually (not recommended). |

---

## 🖥️ Accessing Your Environment

Once installed (check `make logs`), connect using one of these methods:

### 1. Web Browser (Quick Access)
- **URL:** [http://localhost:8006](http://localhost:8006)
- **Use Case:** Quick checks, installation monitoring.

### 2. Microsoft Remote Desktop (Best Performance)
- **App:** Use Remmina (Linux) or Microsoft Remote Desktop (Mac/Windows).
- **PC Address:** `localhost:3389`
- **Primary Credentials:**
  - **User:** `alkami`
  - **Password:** `alkami123`
- **Default/Fallback Credentials:**
  - If you are unable to login with `alkami`, try the default user:
  - **User:** `Docker`
  - **Password:** `admin`
- **Features:** Supports clipboard sync, better resolution, and drag-and-drop file transfer.

---

## 📂 File Transfer & Persistence

### Persistence (YES, it saves!)
**Q: "If I stop Docker, do I lose my work?"**
**A: NO.**
All data is stored in the `./storage` folder on your host machine. This folder contains the `data.img` (virtual disk). As long as this folder exists, your Windows state is safe.

### Transferring Files

**Method 1: The Shared Folder (Recommended)**
1.  **On Host:** Copy files to the `orb-virtualization/shared` folder.
2.  **Inside Windows:** Open File Explorer -> Navigate to the "Shared" folder on Desktop (or `\\host.lan\data`).
3.  Your files are instantly available there.

**Method 2: Drag & Drop (RDP Only)**
If using a robust RDP client (like Microsoft Remote Desktop or Remmina with clipboard enabled), simply drag files from your host machine into the Windows RDP window.

---

## 🔧 Troubleshooting

### 1. "Permission denied accessing Docker socket"
- **Cause:** Your user is not in the `docker` group.
- **Fix:** Run `sudo usermod -aG docker $USER && newgrp docker`.

### 2. "Error gathering device information ... /dev/kvm: no such file"
- **Cause:** KVM is missing or disconnected.
- **Fix:**
    1.  Ensure virtualization is enabled in BIOS.
    2.  Run `sudo usermod -aG kvm $USER`.
    3.  Log out and back in.

### 3. Boot Loop / "Blue Screen" Timeout
- **Cause:** Architecture mismatch. You ran an ARM image on Intel (or vice versa).
- **Fix:**
    1.  Check `docker-compose.yml` image setting.
    2.  **Delete** the `./storage` folder (it contains the wrong architecture data).
    3.  Run `docker-compose up -d` to fresh install.

### 4. Linux Host Freezes/Crashes
- **Cause:** Windows took all the RAM.
- **Fix:** Ensure you have at least **32GB Swap** on the host and limit Docker's memory usage if possible.

### 5. "Microsoft blocked the automated download"
- **Cause:** Microsoft sometimes rate-limits IPs for ISO downloads.
- **Fix:** Wait 1 hour or manually download a Windows 11 ISO (x64) and place it in `./storage` named `win11.iso`.

---

## 📦 Production Distribution (qcow2 + S3)

The raw `data.img` is **~140 GB** which is too large to ship as-is.
The production pipeline converts it to **qcow2** (compressed to ~35–50 GB) and hosts it on S3.

### How It Works

```
Developer Machine                       Client Machine
─────────────────                       ──────────────
storage/data.img (140 GB raw)
       │
  make convert-qcow2
       │
storage/data.qcow2 (~40 GB)
       │
  make upload-s3 S3_BUCKET=xxx
       │
    AWS S3  ─── presigned URL ───→  ./install.sh
                                         │
                                    downloads qcow2 (~40 GB)
                                    pulls dockurr/windows image
                                    writes docker-compose.yml
                                    docker compose up -d
                                         │
                                    Windows 11 running
```

### Developer Side (Build + Ship)

```bash
# Step 1: Stop the running VM
make down

# Step 2: Convert data.img → qcow2 (20–45 min, ~70% smaller)
make convert-qcow2

# Step 3: Verify output
qemu-img check storage/data.qcow2
qemu-img info storage/data.qcow2

# Step 4: Upload to S3
make upload-s3 S3_BUCKET=orb-golden-images

# Step 5: Generate a download URL (valid 7 days)
aws s3 presign s3://orb-golden-images/orb/v1/data.qcow2 --expires-in 604800

# Step 6: Package for client
make package-client DATA_IMG_URL="https://s3.amazonaws.com/..."
# Creates orb-client.zip → send to client
```

### Client Side (Install)

```bash
unzip orb-client.zip && cd orb-client
chmod +x install.sh
./install.sh
```

The install script checks Docker, KVM, disk space, downloads the qcow2 image (resumable), and starts Windows. First install takes ~45 min at 100 Mbps. Subsequent starts are instant.

### Local Testing After Conversion

```bash
# Swap qcow2 in for local testing
mv storage/data.img storage/data.img.raw   # backup original
mv storage/data.qcow2 storage/data.img     # swap in (QEMU auto-detects format)
make up                                    # test boot → http://localhost:8006

# Rollback if needed
make down
mv storage/data.img storage/data.qcow2
mv storage/data.img.raw storage/data.img
```

> For a deep dive into all 9 deployment strategies, cost estimates, and compression benchmarks, see [DEPLOYMENT-STRATEGIES.md](DEPLOYMENT-STRATEGIES.md).

---

## ☁️ Cloud Deployment (AWS)

**Recommended Instance:** `c5.4xlarge` (16 vCPU, 32GB RAM).
**OS:** Amazon Linux 2023 or Ubuntu.

**User Data Script (Auto-Launch):**
```bash
#!/bin/bash
yum update -y
yum install -y docker qemu-kvm libvirt
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

docker run -d --name windows-orb --device /dev/kvm --cap-add NET_ADMIN \
  -p 8006:8006 -p 3389:3389 \
  -v /home/ec2-user/storage:/storage \
  dockurr/windows
```

---

## 🛠️ Management Commands

| Command | Description |
| :--- | :--- |
| `make up` | Start the Windows environment (checks Docker, KVM, context) |
| `make down` | Stop gracefully (saves state to `./storage`) |
| `make restart` | Restart the environment |
| `make logs` | Follow container logs |
| `make status` | Show container status |
| `make convert-qcow2` | Convert `data.img` → `data.qcow2` (~70% smaller) |
| `make upload-s3 S3_BUCKET=xxx` | Upload `data.qcow2` to S3 |
| `make package-client DATA_IMG_URL=xxx` | Create client install zip |

---

## 📁 Project Structure

```
orb-virtualization/
├── docker-compose.yml          # VM configuration (ports, RAM, CPU, disk)
├── Dockerfile.golden           # Legacy: bake full image into Docker layer
├── Makefile                    # All management commands
├── start-orb.sh               # Startup script (Docker context, KVM checks)
├── scripts/
│   ├── convert-to-qcow2.sh    # Convert data.img → compressed qcow2
│   └── install.sh             # Client-side installer
├── storage/                    # VM persistence (gitignored)
│   ├── data.img                # Windows 11 disk (140 GB raw or qcow2)
│   ├── merlin-x64.exe          # Merlin SDK (Intel/AMD)
│   ├── merlin-arm64-arm.exe    # Merlin SDK (ARM)
│   └── windows.*               # UEFI/BIOS config files
├── shared/                     # Host ↔ VM file sharing
├── oem/                        # Post-install scripts (optional)
├── DEPLOYMENT-STRATEGIES.md    # Full deployment strategy guide (9 strategies)
└── README.md
```

---
*Maintained by the DevEx Team - Alkami India GCC*
